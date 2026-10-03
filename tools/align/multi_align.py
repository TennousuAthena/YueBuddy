"""Re-annotate teacher clips with several methods at once.

The single whisper-zh + loudness pass fails in two ways this lesson hit:

  * Tone. A quiet or low tone is still pitched, but the energy gate has
    already called it silence, so the syllable is cut off. Character
    times from whisper are an even split of a word, not the tone.
  * Coverage. The lesson is traditional and whisper writes simplified,
    so only the characters that look the same matched, and a sentence
    the teacher read in full came back as a fragment. A later phrase
    can also vanish when one ASR hypothesis never writes it.

This stacks, per recording:

  1. RMS loudness, pitch voicing, and voice-band spectrum (cues.py)
  2. ASR pass A: medium / zh, previous-text conditioning off
  3. ASR pass B: same, plus the lesson lines as hotwords and a looser
     silence filter, so a fully-read line is more likely to be written
  4. A rescue pass only on speech islands no clip claimed

Each line keeps the hypothesis with the better text match, then the
clip grows to the whole speech island and out to the edge of any tone
it landed inside. Character times follow pitch nuclei when the tone
count agrees with the characters; otherwise they follow ASR.

Usage:
    python3 tools/align/multi_align.py --lesson assets/lessons/lesson_3.json
    python3 tools/align/multi_align.py --lesson assets/lessons/lesson_3.json --apply
"""
import argparse
import json
import os
import re
import sys
from types import SimpleNamespace

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "tools", "align"))

from align_module import (  # noqa: E402
    MIN_SCORE,
    asr_chars,
    best_span,
    canonical,
)
from cues import (  # noqa: E402
    analyze,
    extend_through_tone,
    fit_nuclei,
    nuclei,
    unvoiced_split,
)
from extract_words import map_words  # noqa: E402
from refine_clips import decode_mono  # noqa: E402

HAN_OR_DIGIT = re.compile(r"^[\u4e00-\u9fff\u3400-\u4dbf0-9]+$")
RESCUE_SCORE = 0.75
# Below this, keep the previous clip. A weak match is usually this line
# glued onto a neighbour, or a practice prompt the teacher never read.
ACCEPT_SCORE = 0.58


def hotwords_for(items):
    parts = []
    n = 0
    for it in items:
        text = it["cantonese"]
        if n + len(text) > 240:
            break
        parts.append(text)
        n += len(text)
    return "，".join(parts)


def words_to_chars(words):
    segs = [
        SimpleNamespace(
            words=[
                SimpleNamespace(word=w["w"], start=w["s"], end=w["e"])
                for w in words
            ]
        )
    ]
    return asr_chars(segs)


def transcribe_pass(model, audio_path, hotwords=None, clip=None):
    kwargs = dict(
        language="zh",
        word_timestamps=True,
        vad_filter=False,
        beam_size=5,
        temperature=0.0,
        condition_on_previous_text=False,
        log_progress=False,
    )
    if hotwords:
        kwargs["hotwords"] = hotwords
        kwargs["no_speech_threshold"] = 0.92
        kwargs["log_prob_threshold"] = -1.4
    if clip is not None:
        kwargs["clip_timestamps"] = [clip[0], clip[1]]
        kwargs["no_speech_threshold"] = 0.95
    segments, _ = model.transcribe(audio_path, **kwargs)
    out = []
    for seg in segments:
        for w in seg.words or []:
            if w.end <= w.start or not (w.word or "").strip():
                continue
            out.append({"w": w.word, "s": round(w.start, 3), "e": round(w.end, 3)})
    return out


def load_or_transcribe(model, audio_path, cache_path, items, retranscribe):
    if os.path.exists(cache_path) and not retranscribe:
        with open(cache_path, encoding="utf-8") as f:
            data = json.load(f)
        print(f"[multi] cache {os.path.basename(cache_path)}", flush=True)
        return data
    print(f"[multi] transcribing {audio_path}", flush=True)
    plain = transcribe_pass(model, audio_path)
    print(f"[multi]   plain {len(plain)} words", flush=True)
    recall = transcribe_pass(model, audio_path, hotwords=hotwords_for(items))
    print(f"[multi]   recall {len(recall)} words", flush=True)
    data = {"plain": plain, "recall": recall}
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    return data


def pick_matches(items, streams):
    """Best text match per item across ASR hypotheses, then claim times.

    Same conflict rule as align_module: a worse overlap is left unmatched
    rather than given the wrong slice. A repeated line (score >= 0.8 on
    both) may share one slice.
    """
    picked = []
    for item in items:
        text = canonical(item["cantonese"])
        best = (0.0, 0, 0, None)
        if text:
            for chars in streams:
                if not chars:
                    continue
                cs, ce, score = best_span(text, chars, 0)
                # Same score: keep the tighter span. A longer one is usually
                # this line plus the neighbouring word it also matched.
                width = ce - cs
                best_width = best[2] - best[1]
                tighter = width < best_width or best[3] is None
                if score > best[0] + 0.02 or (abs(score - best[0]) <= 0.02 and tighter):
                    best = (score, cs, ce, chars)
        picked.append(best)

    claimed = []
    results = [None] * len(items)
    order = sorted(range(len(items)), key=lambda i: picked[i][0], reverse=True)
    for idx in order:
        score, cs, ce, chars = picked[idx]
        if chars is None or ce <= cs or score < MIN_SCORE:
            results[idx] = {"score": score, "span": None, "chars": None}
            continue
        t0 = chars[cs][1]
        t1 = chars[ce - 1][2]
        if t1 <= t0:
            results[idx] = {"score": score, "span": None, "chars": None}
            continue
        # Claim wall-clock time. The two hypotheses do not share a
        # character index, so overlap has to be measured in seconds.
        clash = None
        for qs, qe, qscore in claimed:
            overlap = max(0.0, min(t1, qe) - max(t0, qs))
            if overlap > 0.5 * (t1 - t0):
                clash = (qs, qe, qscore)
                break
        if clash is not None and not (score >= 0.8 and clash[2] >= 0.8):
            results[idx] = {"score": score, "span": None, "chars": None}
            continue
        results[idx] = {"score": score, "span": (t0, t1), "chars": chars}
        claimed.append((t0, t1, score))
    return results


def _plausible(n_chars, dur):
    if n_chars <= 0:
        return False
    return 0.11 * n_chars <= dur <= 0.9 * n_chars + 1.1


def expand_span(span, islands, cores, n_chars, duration):
    """Grow a fragment to the rest of its own speech island.

    The cut stops at the midpoint before the next line's match, so a
    quiet tone at the tail is kept and the next sentence is not.
    """
    s, e = span
    mid = (s + e) / 2
    home = None
    for iv in islands:
        if iv[0] <= mid <= iv[1]:
            home = iv
            break
    if home is None:
        touched = [iv for iv in islands if iv[0] < e and iv[1] > s]
        home = touched[0] if touched else (s, e)
    ns, ne = home
    for cs, ce in cores:
        if ce <= s:
            ns = max(ns, (ce + s) / 2)
        elif cs >= e:
            ne = min(ne, (e + cs) / 2)
    # A match that only caught the middle of a long island can still run
    # away. Cap the growth, but leave room for a trailing tone.
    expect = max(0.4, n_chars * 0.45 + 0.45)
    if (ne - ns) > max(expect * 2.0, (e - s) + 0.8):
        ns = max(ns, s - 0.28)
        ne = min(ne, e + 0.45)
    # Don't pull the start back to a whisper timestamp of 0. The island
    # onset is the acoustic start; the end still follows the ASR if the
    # recogniser heard a tone the island stopped short of.
    ns = max(0.0, ns)
    ne = min(duration, max(ne, e))
    if ne - ns < 0.2:
        return s, e
    return ns, ne


def absorb_slash(cantonese, span, islands, taken, duration):
    """A slash item is two readings. Pull in the next island if it's free."""
    if "／" not in cantonese and "/" not in cantonese:
        return span
    s, e = span
    for iv in islands:
        if iv[0] >= e - 0.05 and iv[0] - e <= 1.0:
            if any(not (iv[1] <= a or iv[0] >= b) for a, b in taken):
                continue
            e = min(duration, iv[1])
            break
        if iv[1] <= s + 0.05 and s - iv[1] <= 1.0:
            if any(not (iv[1] <= a or iv[0] >= b) for a, b in taken):
                continue
            s = max(0.0, iv[0])
    return s, e


def rescue_unmatched(model, audio_path, items, results, spans, islands, duration, hotwords):
    claimed = [tuple(sp) for sp in spans if sp]
    free = []
    for iv in islands:
        covered = 0.0
        for s, e in claimed:
            covered += max(0.0, min(iv[1], e) - max(iv[0], s))
        if covered < 0.4 * (iv[1] - iv[0]) and iv[1] - iv[0] >= 0.45:
            free.append(iv)
    if not free:
        return
    pending = [i for i, r in enumerate(results) if not r or not r.get("span")]
    if not pending:
        return
    print(f"[multi] rescue {len(free)} uncovered islands, {len(pending)} lines", flush=True)
    for iv in free:
        words = transcribe_pass(model, audio_path, hotwords=hotwords, clip=iv)
        chars = words_to_chars(words)
        text = "".join(w["w"] for w in words).strip()
        if not chars:
            print(f"  island {iv[0]:.2f}-{iv[1]:.2f}s empty ({text!r})", flush=True)
            continue
        print(f"  island {iv[0]:.2f}-{iv[1]:.2f}s {text}", flush=True)
        best_i = None
        best = 0.0
        for i in pending:
            if results[i] and results[i].get("span"):
                continue
            item_text = canonical(items[i]["cantonese"])
            if not item_text:
                continue
            cs, ce, score = best_span(item_text, chars, 0)
            dur = iv[1] - iv[0]
            if score > best and score >= RESCUE_SCORE and _plausible(len(item_text), dur):
                best = score
                best_i = i
                _ = (cs, ce)
        if best_i is None:
            continue
        results[best_i] = {
            "score": round(best, 3),
            "span": iv,
            "chars": chars,
            "rescue": True,
        }
        spans[best_i] = [iv[0], iv[1]]


def _covered_by_stronger(i, spans, scores):
    """How much of span i already belongs to other lines that match as well."""
    me = spans[i]
    intervals = []
    for j, sp in enumerate(spans):
        if j == i or not sp or scores[j] + 0.02 < scores[i]:
            continue
        lo = max(me[0], sp[0])
        hi = min(me[1], sp[1])
        if hi > lo:
            intervals.append((lo, hi))
    if not intervals:
        return 0.0
    intervals.sort()
    total = 0.0
    cs, ce = intervals[0]
    for lo, hi in intervals[1:]:
        if lo <= ce:
            ce = max(ce, hi)
        else:
            total += ce - cs
            cs, ce = lo, hi
    return total + (ce - cs)


def resolve_overlaps(spans, scores, voiced):
    """spans: list of [s, e] or None, mutated in place.

    A line whose audio is already covered by a stronger line is dropped
    (the practice prompt that just repeats two examples). What remains
    is cut on an unvoiced frame so the cut is not mid-tone.
    """
    for _ in range(8):
        dropped = False
        for i, me in enumerate(spans):
            if not me:
                continue
            covered = _covered_by_stronger(i, spans, scores)
            dur = me[1] - me[0]
            if dur > 0 and covered > 0.55 * dur:
                spans[i] = None
                dropped = True
        if not dropped:
            break
    order = sorted(
        [i for i, sp in enumerate(spans) if sp],
        key=lambda i: spans[i][0],
    )
    for a, b in zip(order, order[1:]):
        sa, sb = spans[a], spans[b]
        if sa == sb:
            continue
        if sb[0] < sa[1]:
            cut = unvoiced_split(voiced, sb[0], sa[1])
            sa[1] = cut
            sb[0] = cut
            if sa[1] - sa[0] < 0.2:
                spans[a] = None
            if sb[1] - sb[0] < 0.2:
                spans[b] = None


def tone_edges(spans, voiced, duration):
    order = sorted(
        [i for i, sp in enumerate(spans) if sp],
        key=lambda i: spans[i][0],
    )
    for n, i in enumerate(order):
        left = spans[order[n - 1]][1] if n else 0.0
        right = spans[order[n + 1]][0] if n + 1 < len(order) else duration
        s, e = spans[i]
        spans[i] = list(extend_through_tone(voiced, s, e, left, right))


def spoken_len(text):
    """Characters the teacher actually voices: Han, digits, latin."""
    return len(re.sub(r"[\W_]+", "", text.lower()))


def pitch_words(cantonese, voiced, start_s, end_s):
    target_src = re.sub(r"[\W_]+", "", cantonese.lower())
    if not target_src or not HAN_OR_DIGIT.match(target_src):
        return None
    runs = nuclei(voiced, start_s, end_s)
    fitted = fit_nuclei(runs, len(target_src))
    if not fitted:
        return None
    flat = []
    for a, b in fitted:
        flat += [int(round(a * 1000)), int(round(b * 1000))]
    start_ms = int(round(start_s * 1000))
    end_ms = int(round(end_s * 1000))
    for i in range(0, len(flat), 2):
        flat[i] = min(max(flat[i], start_ms), end_ms)
        flat[i + 1] = min(max(flat[i + 1], start_ms), end_ms)
        if flat[i + 1] < flat[i]:
            flat[i + 1] = flat[i]
    return target_src, flat


def build_words(cantonese, chars, voiced, start_s, end_s):
    pitched = pitch_words(cantonese, voiced, start_s, end_s)
    if pitched is not None:
        return pitched[0], pitched[1], "pitch"
    if not chars:
        return None, None, "none"
    start_ms = int(round(start_s * 1000))
    end_ms = int(round(end_s * 1000))
    window = [
        c for c in chars
        if c[2] * 1000 > start_ms - 120 and c[1] * 1000 < end_ms + 120
    ]
    mapped = map_words(cantonese, window, start_ms, end_ms)
    if mapped is None:
        return None, None, "none"
    return mapped[0], mapped[1], "asr"


def process_module(model, module, cache_dir, retranscribe, rescue):
    recordings = module.get("recordings") or []
    if not recordings:
        return []
    items = module["items"]
    # Lesson 3 modules each have one recording. A second file would need
    # the same per-file pick as align_module; bail rather than guess.
    if len(recordings) != 1:
        print(f"[multi] {module['id']}: skip, {len(recordings)} recordings", flush=True)
        return []
    rec = recordings[0]
    audio_path = os.path.join(REPO, "assets", rec)
    cache_path = os.path.join(
        cache_dir, os.path.splitext(os.path.basename(rec))[0] + ".json"
    )
    data = load_or_transcribe(model, audio_path, cache_path, items, retranscribe)
    streams = [words_to_chars(data.get("plain") or []), words_to_chars(data.get("recall") or [])]
    audio = decode_mono(audio_path)
    islands, voiced, duration = analyze(audio)
    speech_s = sum(e - s for s, e in islands)
    print(
        f"[multi] {module['id']}: {len(islands)} islands, "
        f"{speech_s:.1f}s speech / {duration:.1f}s",
        flush=True,
    )
    results = pick_matches(items, streams)
    spans = []
    for item, result in zip(items, results):
        if not result or not result.get("span"):
            spans.append(None)
            continue
        cores = [
            other["span"]
            for other in results
            if other is not result and other and other.get("span")
        ]
        grown = expand_span(
            result["span"], islands, cores, spoken_len(item["cantonese"]), duration
        )
        spans.append(list(grown))
    occupied = [tuple(sp) for sp in spans if sp]
    for i, item in enumerate(items):
        if not spans[i]:
            continue
        spans[i] = list(
            absorb_slash(item["cantonese"], spans[i], islands, occupied, duration)
        )

    if rescue and model is not None:
        rescue_unmatched(
            model, audio_path, items, results, spans, islands, duration,
            hotwords_for(items),
        )

    scores = [r["score"] if r else 0.0 for r in results]
    resolve_overlaps(spans, scores, voiced)
    tone_edges(spans, voiced, duration)

    proposals = []
    for item, result, span in zip(items, results, spans):
        old = item.get("clip")
        if not span:
            proposals.append({
                "id": item["id"],
                "text": item["cantonese"],
                "score": result["score"] if result else 0,
                "clip": None,
                "old": _ms(old),
                "timing": "none",
            })
            continue
        s, e = span
        if result and result["score"] < ACCEPT_SCORE and not result.get("rescue"):
            proposals.append({
                "id": item["id"],
                "text": item["cantonese"],
                "score": result["score"],
                "clip": None,
                "old": _ms(old),
                "timing": "none",
            })
            continue
        if e - s < 0.2 or not _plausible(max(spoken_len(item["cantonese"]), 1), e - s):
            # Keep a high-scoring match even if the duration looks odd;
            # drop only low-confidence stretches that ran away.
            if not result or result["score"] < 0.62:
                proposals.append({
                    "id": item["id"],
                    "text": item["cantonese"],
                    "score": result["score"] if result else 0,
                    "clip": None,
                    "old": _ms(old),
                    "timing": "none",
                })
                continue
        t, w, how = build_words(
            item["cantonese"], result.get("chars") if result else None, voiced, s, e
        )
        clip = {"startMs": int(round(s * 1000)), "endMs": int(round(e * 1000))}
        if t and w:
            clip["words"] = {"t": t, "w": w}
        proposals.append({
            "id": item["id"],
            "text": item["cantonese"],
            "score": round(result["score"], 3) if result else 0,
            "clip": clip,
            "old": _ms(old),
            "timing": how,
            "rescue": bool(result and result.get("rescue")),
        })
    return proposals


def _ms(clip):
    if not clip:
        return None
    return [clip.get("startMs"), clip.get("endMs")]


def report(module_id, proposals):
    print(f"\n== {module_id}", flush=True)
    for p in proposals:
        new = p["clip"]
        old = p["old"]
        old_s = f"{old[0]}-{old[1]}" if old else "—"
        if new:
            new_s = f"{new['startMs']}-{new['endMs']} ({new['endMs'] - new['startMs']}ms)"
        else:
            new_s = "—"
        flag = ""
        if p.get("rescue"):
            flag += " RESCUE"
        if not new:
            flag += " MISS"
        elif old and abs((new["endMs"] - new["startMs"]) - (old[1] - old[0])) > 400:
            flag += " MOVED"
        print(
            f"  {p['id']:<12} {p['score']:.2f} {p['timing']:<5} "
            f"old {old_s:<14} new {new_s:<22}{flag} {p['text'][:28]}",
            flush=True,
        )


def apply_proposals(lesson, module_id, proposals):
    by_id = {p["id"]: p for p in proposals}
    module = next(m for m in lesson["modules"] if m["id"] == module_id)
    kept = 0
    for it in module["items"]:
        p = by_id.get(it["id"])
        if not p:
            continue
        if p["clip"] and p["score"] >= ACCEPT_SCORE:
            it["clip"] = p["clip"]
            kept += 1
        elif p["score"] < MIN_SCORE and "clip" in it and p["clip"] is None:
            # Don't delete a clip the new pass merely failed to confirm
            # when we have nothing better. Rescue misses stay clipless
            # only if they never had one.
            pass
    return kept


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", default="assets/lessons/lesson_3.json")
    parser.add_argument("--module", default=None)
    parser.add_argument("--model", default="medium")
    parser.add_argument("--out-dir", default="tools/align/out")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--retranscribe", action="store_true")
    parser.add_argument("--no-rescue", action="store_true")
    args = parser.parse_args()

    lesson_path = args.lesson if os.path.isabs(args.lesson) else os.path.join(REPO, args.lesson)
    with open(lesson_path, encoding="utf-8") as f:
        lesson = json.load(f)
    out_dir = args.out_dir if os.path.isabs(args.out_dir) else os.path.join(REPO, args.out_dir)
    cache_dir = os.path.join(out_dir, "cache")

    model = None
    if args.retranscribe or not args.no_rescue:
        from faster_whisper import WhisperModel

        model_name = args.model
        snap_root = os.path.expanduser(
            f"~/.cache/huggingface/hub/models--Systran--faster-whisper-{args.model}/snapshots"
        )
        if os.path.isdir(snap_root):
            snaps = sorted(os.listdir(snap_root))
            if snaps:
                model_name = os.path.join(snap_root, snaps[-1])
        print(f"[multi] loading {model_name}", flush=True)
        model = WhisperModel(model_name, device="auto", compute_type="auto")

    all_proposals = {}
    for module in lesson["modules"]:
        if args.module and module["id"] != args.module:
            continue
        if not module.get("recordings"):
            continue
        proposals = process_module(
            model, module, cache_dir, args.retranscribe, rescue=not args.no_rescue
        )
        all_proposals[module["id"]] = proposals
        report(module["id"], proposals)

    if args.apply:
        total = 0
        for module_id, proposals in all_proposals.items():
            total += apply_proposals(lesson, module_id, proposals)
        with open(lesson_path, "w", encoding="utf-8") as f:
            json.dump(lesson, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"[multi] applied {total} clips to {lesson_path}", flush=True)
    print("MULTI_DONE", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
