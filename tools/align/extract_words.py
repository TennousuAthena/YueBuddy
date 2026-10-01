"""Extract per-character timings for items that already have clips.

Re-transcribes each recording once (medium, zh, word_timestamps) and cuts
word timings by the FINAL clip boundaries stored in the lesson JSON — no
re-alignment, so energy-VAD-refined boundaries stay valid.

Matching is done in canonical space (same alias folding as align_module),
then timings are unfolded back onto the plain-normalized display text so
the app can map them without knowing the alias table:

    clip.words = {"t": "<normed display text>", "w": [s,e,s,e,...]}

Usage:
    python3 tools/align/extract_words.py --lesson assets/lessons/lesson_1.json --module l1-dialogue-1
    python3 tools/align/extract_words.py --all --apply   # everything + merge
"""
import argparse
import difflib
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "tools", "align"))

from align_module import ALIASES, canonical, norm, transcribe  # noqa: E402

MIN_COVERAGE = 0.5
WINDOW_SLACK_MS = 120


def safe_asr_chars(segments):
    """asr_chars + guards: whisper sometimes emits junk/inverted timings
    for short English interjections (e.g. "hello" inside Cantonese audio).
    Drop words with end <= start and clamp overlaps so the char stream
    stays monotonic; dropped words become interpolation gaps."""
    out = []
    prev_end = 0.0
    for seg in segments:
        for w in seg.words or []:
            text = canonical(w.word)
            if not text:
                continue
            s, e = w.start, w.end
            if e <= s:
                continue
            s = max(s, prev_end)
            if e <= s:
                continue
            dur = max(e - s, 0.01)
            per = dur / len(text)
            for i, ch in enumerate(text):
                out.append((ch, s + per * i, s + per * (i + 1)))
            prev_end = e
    return out


def fold_with_map(text):
    """canonical() equivalent that also tracks unfolding.

    Returns (folded_chars, src_index_of_each_folded_char) where src indexes
    into the plain-normed input. A folded char produced by a multi-char
    replacement maps to the first source index of the replaced range; the
    caller shares its timing across the whole range.
    """
    toks = [[ch, i] for i, ch in enumerate(text)]  # [char, src_idx]
    for canto, std in ALIASES:
        if not std:
            continue
        cur = "".join(t[0] for t in toks)
        if std not in cur:
            continue
        out = []
        i = 0
        while i < len(cur):
            if cur.startswith(std, i):
                rng = toks[i : i + len(std)]
                first = rng[0][1]
                last = rng[-1][1]
                span = max(last - first + 1, 1)
                for k, ch in enumerate(canto):
                    # Proportional pick of a source index inside the range.
                    src = first + min(int(k * span / len(canto)), span - 1)
                    out.append([ch, src])
                i += len(std)
            else:
                out.append(toks[i])
                i += 1
        toks = out
        cur = "".join(t[0] for t in toks)
    folded = [t[0] for t in toks]
    src_of = [t[1] for t in toks]
    return folded, src_of


def map_words(display, chars, start_ms, end_ms):
    """Return (target, flat_ms) or None when coverage is too low.

    target is the plain-normed display text; flat_ms is [s,e]*len(target)
    in recording-absolute milliseconds.
    """
    target = norm(display)
    if not target or not chars:
        return None
    folded, src_of = fold_with_map(target)
    wtext = "".join(c[0] for c in chars)
    ftext = "".join(folded)
    matcher = difflib.SequenceMatcher(None, ftext, wtext, autojunk=False)
    timed = [None] * len(folded)
    for b in matcher.get_matching_blocks():
        for k in range(b.size):
            timed[b.a + k] = chars[b.b + k][1:3]
    covered = sum(1 for t in timed if t is not None)
    if covered / len(folded) < MIN_COVERAGE:
        return None
    # Fill gaps by interpolation between neighbours (or span edges).
    # Fill gaps by linear interpolation across each run of unmatched chars.
    times = list(timed)
    i = 0
    while i < len(times):
        if times[i] is not None:
            i += 1
            continue
        j = i
        while j < len(times) and times[j] is None:
            j += 1
        left = times[i - 1] if i > 0 else None
        right = times[j] if j < len(times) else None
        lo = left[1] if left else start_ms / 1000.0
        hi = right[0] if right else end_ms / 1000.0
        gap = j - i
        for k in range(gap):
            s = lo + (hi - lo) * (k + 1) / (gap + 1)
            times[i + k] = (round(s, 3), round(s + 0.03, 3))
        i = j
    # Unfold back onto plain-normed display chars: every source char that
    # produced a folded char shares that folded char's timing.
    per_src = {}
    for f_idx, src_idx in enumerate(src_of):
        per_src.setdefault(src_idx, []).append(times[f_idx])
    flat = []
    for i in range(len(target)):
        segs = per_src.get(i)
        if not segs:
            # Source char folded away entirely (shouldn't happen); reuse edge.
            s = start_ms / 1000.0
            e = end_ms / 1000.0
        else:
            s = min(s for s, _ in segs)
            e = max(e for _, e in segs)
        flat += [int(round(s * 1000)), int(round(e * 1000))]
    # Clamp into the played clip: refined edges may have trimmed soft
    # onsets, and karaoke must light words only while audio actually plays.
    for i in range(0, len(flat), 2):
        flat[i] = min(max(flat[i], start_ms), end_ms)
        flat[i + 1] = min(max(flat[i + 1], start_ms), end_ms)
    for i in range(2, len(flat), 2):
        flat[i] = max(flat[i], flat[i - 2])
    for i in range(0, len(flat), 2):
        flat[i + 1] = max(flat[i + 1], flat[i])
    return target, flat


def process_module(lesson_path, module, model, out_dir, apply):
    from faster_whisper import WhisperModel

    recordings = module.get("recordings", [])
    items = [it for it in module.get("items", []) if it.get("clip")]
    if not recordings or not items:
        print(f"[words] {module['id']}: nothing to do", flush=True)
        return 0
    print(f"[words] loading model {model} ...", flush=True)
    fw = WhisperModel(model, device="auto", compute_type="auto")
    per_rec_chars = []
    for rec in recordings:
        audio_path = os.path.join(REPO, "assets", rec)
        print(f"[words] transcribing {rec} ...", flush=True)
        segments, _ = transcribe(fw, audio_path)
        per_rec_chars.append(safe_asr_chars(segments))
    results = []
    for it in items:
        clip = it["clip"]
        rec_idx = clip.get("rec", 0)
        chars = per_rec_chars[rec_idx] if rec_idx < len(per_rec_chars) else []
        s, e = clip["startMs"], clip["endMs"]
        window = [c for c in chars
                  if c[2] * 1000 > s - WINDOW_SLACK_MS
                  and c[1] * 1000 < e + WINDOW_SLACK_MS]
        mapped = map_words(it["cantonese"], window, s, e)
        if mapped is None:
            print(f"  {it['id']}: low coverage, skipped", flush=True)
            results.append({"id": it["id"], "words": None})
        else:
            t, w = mapped
            results.append({"id": it["id"], "t": t, "w": w})
    n_ok = sum(1 for r in results if r.get("w"))
    print(f"[words] {module['id']}: {n_ok}/{len(items)} with word timings",
          flush=True)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{module['id']}.words.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"module": module["id"], "items": results}, f,
                  ensure_ascii=False, indent=1)
    print(f"[words] wrote {out_path}", flush=True)
    if apply:
        by_id = {r["id"]: r for r in results if r.get("w")}
        with open(lesson_path, encoding="utf-8") as f:
            lesson = json.load(f)
        applied = 0
        for m in lesson["modules"]:
            if m["id"] != module["id"]:
                continue
            for it in m["items"]:
                r = by_id.get(it["id"])
                if r and it.get("clip"):
                    it["clip"]["words"] = {"t": r["t"], "w": r["w"]}
                    applied += 1
        with open(lesson_path, "w", encoding="utf-8") as f:
            json.dump(lesson, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"[words] applied {applied} to {lesson_path}", flush=True)
    return n_ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", default="assets/lessons/lesson_1.json")
    parser.add_argument("--module", default=None)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--model", default="medium")
    parser.add_argument("--out-dir", default="tools/align/out")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    lessons = ["assets/lessons/lesson_1.json", "assets/lessons/lesson_2.json"] \
        if args.all else [args.lesson]
    total = 0
    for lesson_rel in lessons:
        lesson_path = os.path.join(REPO, lesson_rel)
        with open(lesson_path, encoding="utf-8") as f:
            lesson = json.load(f)
        for module in lesson["modules"]:
            if not module.get("recordings"):
                continue
            if not args.all and module["id"] != args.module:
                continue
            out_dir = args.out_dir if os.path.isabs(args.out_dir) \
                else os.path.join(REPO, args.out_dir)
            total += process_module(lesson_path, module, args.model,
                                    out_dir, args.apply)
    print(f"WORDS_DONE total={total}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
