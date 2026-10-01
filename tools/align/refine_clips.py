"""Refine clip boundaries with energy-VAD + zero-crossing snap.

Whisper word timings can start late / end early, cutting half a
sentence. This pass decodes the teacher recording, finds real speech
onset/offset around each clip via RMS energy, and snaps cuts to
zero-crossings (no clicks).

Usage:
    python3 tools/align/refine_clips.py \
        --lesson assets/lessons/lesson_1.json \
        --module l1-daily --out-dir tools/align/out
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from align_module import REPO, write_review  # noqa: E402

SR = 16000
FRAME = 320  # 20 ms
HOP = 160  # 10 ms
MAX_EXPAND = 1.0  # never move a boundary more than this (seconds)
MARGIN = 0.08  # breathing room kept around detected speech
MIN_LEN = 0.30
BRIDGE_GAP = 0.15  # merge speech separated by shorter silence


def decode_mono(path):
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path,
         "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
        capture_output=True, check=True)
    return np.frombuffer(proc.stdout, dtype=np.float32)


def frame_rms(audio):
    n = 1 + max(0, (len(audio) - FRAME) // HOP)
    if n <= 0:
        return np.zeros(0, dtype=np.float64)
    idx = (np.arange(FRAME)[None, :] + HOP * np.arange(n)[:, None])
    frames = audio[idx]
    return np.sqrt((frames ** 2).mean(axis=1))


def speech_mask(rms, threshold):
    speech = rms > threshold
    # Bridge short gaps so pauses inside a sentence don't split it.
    bridge = int(BRIDGE_GAP * SR / HOP)
    out = speech.copy()
    i = 0
    n = len(out)
    while i < n:
        if not out[i]:
            j = i
            while j < n and not out[j]:
                j += 1
            if j < n and (j - i) <= bridge and i > 0:
                out[i:j] = True
            i = j
        else:
            i += 1
    return out


def to_ms(frame_idx):
    return int(round(frame_idx * HOP / SR * 1000))


def snap_zero_crossing(audio, ms):
    i = int(ms / 1000 * SR)
    i = max(0, min(len(audio) - 1, i))
    span = int(0.005 * SR)
    lo, hi = max(0, i - span), min(len(audio) - 1, i + span)
    best, best_dist = i, span + 1
    for k in range(lo, hi):
        if audio[k] == 0 or audio[k] * audio[k + 1] < 0:
            dist = abs(k - i)
            if dist < best_dist:
                best, best_dist = k, dist
    return int(round(best / SR * 1000))


def refine_clip(audio, rms, mask, start_ms, end_ms):
    dur_ms = len(audio) / SR * 1000
    if len(mask) == 0:
        return start_ms, end_ms, "empty"
    s = max(0, int(start_ms / 1000 * SR / HOP))
    e = min(len(mask) - 1, int(end_ms / 1000 * SR / HOP))
    if e <= s:
        return start_ms, end_ms, "empty"

    window_lo = max(0, int((start_ms / 1000 - MAX_EXPAND) * SR / HOP))
    window_hi = min(len(mask) - 1, int((end_ms / 1000 + MAX_EXPAND) * SR / HOP))
    seg = np.where(mask[window_lo: window_hi + 1])[0]
    if len(seg) == 0:
        return start_ms, end_ms, "no-speech"
    # Split bridged mask into islands, keep every island touching the
    # original span: refine trims/extends edges but never drops the
    # middle of a sentence.
    islands = []
    run = [seg[0]]
    for k in seg[1:]:
        if k == run[-1] + 1:
            run.append(k)
        else:
            islands.append(run)
            run = [k]
    islands.append(run)
    touching = [r for r in islands
                if r[0] + window_lo <= e and r[-1] + window_lo >= s]
    if not touching:
        return start_ms, end_ms, "no-overlap"
    ns = max(window_lo, touching[0][0] + window_lo - int(MARGIN * SR / HOP))
    ne = min(window_hi, touching[-1][-1] + window_lo + int(MARGIN * SR / HOP))
    ns_ms = snap_zero_crossing(audio, to_ms(ns))
    ne_ms = snap_zero_crossing(audio, to_ms(ne))
    if ne_ms - ns_ms < MIN_LEN * 1000:
        return start_ms, end_ms, "too-short"
    return ns_ms, ne_ms, "ok"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--out-dir", default="tools/align/out")
    args = parser.parse_args()

    lesson_path = args.lesson if os.path.isabs(args.lesson) else os.path.join(REPO, args.lesson)
    lesson = json.load(open(lesson_path, encoding="utf-8"))
    module = next(m for m in lesson["modules"] if m["id"] == args.module)
    out_dir = args.out_dir if os.path.isabs(args.out_dir) else os.path.join(REPO, args.out_dir)
    clips_path = os.path.join(out_dir, f"{args.module}.clips.json")
    data = json.load(open(clips_path, encoding="utf-8"))

    decoded = {}
    changed = 0
    for entry in data["clips"]:
        clip = entry.get("clip")
        if not clip:
            continue
        rec = clip.get("rec", 0)
        if rec not in decoded:
            audio_path = os.path.join(REPO, "assets", data["recordings"][rec])
            audio = decode_mono(audio_path)
            rms = frame_rms(audio)
            noise = float(np.percentile(rms, 10)) if len(rms) else 0.0
            decoded[rec] = (audio, rms, noise)
        audio, rms, noise = decoded[rec]
        peak = float(rms.max()) if len(rms) else 0.0
        threshold = max(noise * 3.0, peak * 0.015, 5e-4)
        mask = speech_mask(rms, threshold)
        ns, ne, status = refine_clip(audio, rms, mask, clip["startMs"], clip["endMs"])
        if status == "ok" and (ns != clip["startMs"] or ne != clip["endMs"]):
            entry["clip"] = dict(clip, startMs=ns, endMs=ne)
            entry["refined"] = f"{clip['startMs']}-{clip['endMs']}->{ns}-{ne}"
            changed += 1
        entry["refine_status"] = status

    # Re-split small overlaps within the SAME recording (different files
    # have independent timelines; skip identical shared spans).
    with_spans = [e for e in data["clips"] if e.get("clip")]
    by_rec = {}
    for e in with_spans:
        by_rec.setdefault(e["clip"].get("rec", 0), []).append(e)
    for group in by_rec.values():
        order = sorted(group, key=lambda r: r["clip"]["startMs"])
        for a, b in zip(order, order[1:]):
            ca, cb = a["clip"], b["clip"]
            if (ca["startMs"], ca["endMs"]) == (cb["startMs"], cb["endMs"]):
                continue
            if cb["startMs"] < ca["endMs"]:
                mid = (ca["endMs"] + cb["startMs"]) // 2
                ca["endMs"], cb["startMs"] = mid, mid

    # Final guard: never persist an inverted or tiny span.
    for entry in data["clips"]:
        clip = entry.get("clip")
        if clip and clip["endMs"] - clip["startMs"] < MIN_LEN * 1000:
            print(f"[refine] WARNING {entry['id']}: dropping invalid "
                  f"span {clip['startMs']}-{clip['endMs']}", flush=True)
            entry["clip"] = None
            entry.pop("refined", None)

    with open(clips_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"[refine] {args.module}: adjusted {changed} clips", flush=True)
    for entry in data["clips"]:
        if entry.get("refined"):
            print(f"  {entry['id']}: {entry['refined']}", flush=True)

    items_by_id = {it["id"]: it for it in module["items"]}
    audio_rel = os.path.join("..", "..", "..", "assets", data["recordings"][0])
    write_review(
        os.path.join(out_dir, f"{args.module}.review.html"),
        audio_rel, items_by_id,
        [{"id": e["id"], "score": e["score"],
          "span": (e["clip"]["startMs"], e["clip"]["endMs"]) if e.get("clip") else None}
         for e in data["clips"]])
    print("REFINE_DONE", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
