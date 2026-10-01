"""Align lesson item texts to teacher recordings via ASR word timings.

Pipeline (per module):
  1. Transcribe each recording with faster-whisper (lang=zh, word timestamps).
  2. Order-preserving fuzzy match of the known item texts against the ASR
     character stream (handles Written-Cantonese normalization + mishears).
  3. Emit per-item clips {startMs, endMs, rec} + QA report + HTML review page.

Usage:
    python3 tools/align/align_module.py \
        --lesson assets/lessons/lesson_1.json \
        --module l1-dialogue-1 \
        --model small \
        --out-dir tools/align/out

    # then merge into the lesson file:
    python3 tools/align/align_module.py \
        --lesson assets/lessons/lesson_1.json \
        --module l1-dialogue-1 --apply
"""
import argparse
import difflib
import html
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

START_PAD = 0.15
END_PAD = 0.30
MIN_SCORE = 0.40


def norm(s: str) -> str:
    """Keep unicode letters/digits only (CJK incl. Ext-A, latin, digits)."""
    return re.sub(r"[\W_]+", "", s.lower())


# Written-Cantonese <-> standard-written-Chinese equivalences, plus
# systematic small/medium-model mis-hearings. Applied to BOTH the lesson
# text and the ASR text so they meet in the middle. Order matters:
# longer phrases first.
ALIASES = [
    ("唔使喇唔該", "不用了麻煩"),
    ("唔該借借", "麻煩借借"),
    ("唔該", "麻煩"),
    ("唔使", "不用"),
    ("對唔住", "對不起"),
    ("唔好意思", "不好意思"),
    ("唔緊要", "沒關係"),
    ("冇問題", "沒問題"),
    ("食咗", "吃了"),
    ("飲咗", "喝了"),
    ("食", "吃"),
    ("飲", "喝"),
    ("你會不會說", "你識唔識講"),
    ("我會說一點", "我識講少少"),
    ("忙不忙", "忙唔忙"),
    ("找", "搵"),
    ("一起", "一齊"),
    ("沒有", "未"),
    ("啦", "喇"),
    ("啊", "呀"),
    ("冧把", "lumber"),
    ("冧把", "number"),
    ("零", "0"),
    ("一", "1"),
    ("二", "2"),
    ("兩", "2"),
    ("三", "3"),
    ("四", "4"),
    ("五", "5"),
    ("六", "6"),
    ("七", "7"),
    ("八", "8"),
    ("九", "9"),
    ("我係", "我是"),
    ("你係", "你是"),
    ("喺度", "在這"),
    ("喺", "在"),
    ("咩", "什麼"),
    ("點稱呼", "怎麼稱呼"),
    ("點", "怎麼"),
    ("邊科", "哪一科"),
    ("邊", "哪"),
    ("嘅", "的"),
    ("嘢", "東西"),
    ("搵日", "找天"),
    ("搵", "找"),
    ("得閒", "有空"),
    ("近排", "近來"),
    ("早唞", "早頭"),
    ("吖", "吧"),
    ("喇", "啦"),
    ("咗", "了"),
    ("嚟", "來"),
    ("佢", "他"),
    ("哋", "們"),
    ("咁", "這"),
    ("係", "是"),
    ("嘅", "的"),
]


def canonical(s: str) -> str:
    """norm() + alias folding for fuzzy matching."""
    s = norm(s)
    for cantonese, standard in ALIASES:
        if standard in s:
            s = s.replace(standard, cantonese)
    return s


def asr_chars(segments):
    """Flatten ASR words into (char, start, end) with even intra-word split."""
    out = []
    for seg in segments:
        for w in seg.words or []:
            text = canonical(w.word)
            if not text:
                continue
            dur = max(w.end - w.start, 0.01)
            per = dur / len(text)
            for i, ch in enumerate(text):
                out.append((ch, w.start + per * i, w.start + per * (i + 1)))
    return out


def best_span(item_text, chars, start_pos):
    """Best local window match for item_text at/after start_pos.

    Slides a ~2x-length window and scores by recall
    (matched_chars / len(item)). Returns (char_start, char_end, score).
    """
    n = len(item_text)
    if n == 0:
        return start_pos, start_pos, 0.0
    win_len = n * 2 + 12
    best = (0.0, start_pos, start_pos)
    last_start = len(chars)
    s = start_pos
    while s < last_start:
        wtext = "".join(c[0] for c in chars[s : s + win_len])
        if not wtext:
            break
        matcher = difflib.SequenceMatcher(None, item_text, wtext, autojunk=False)
        blocks = [b for b in matcher.get_matching_blocks() if b.size > 0]
        if not blocks:
            s += 1
            continue
        # Cluster around the longest block: absorb only nearby blocks so
        # repeats elsewhere in the window can't balloon the span.
        blocks.sort(key=lambda b: (-b.size, b.b))
        seed = blocks[0]
        lo, hi = seed.b, seed.b + seed.size
        used = {id(seed)}
        changed = True
        while changed:
            changed = False
            for b in blocks:
                if id(b) in used:
                    continue
                if b.b + b.size >= lo - 3 and b.b <= hi + 3:
                    lo = min(lo, b.b)
                    hi = max(hi, b.b + b.size)
                    used.add(id(b))
                    changed = True
        matched = sum(b.size for b in blocks if id(b) in used)
        recall = matched / n
        if recall > best[0]:
            best = (recall, s + lo, s + hi)
        s += 1
    score, cs, ce = best
    return cs, ce, round(score, 3)


def align_items(items, chars):
    """Independent (order-free) alignment with conflict resolution.

    Each item takes its best window anywhere in the recording, because
    teachers don't always read in lesson order (e.g. l2-eat reads the
    時段 section first). Claims are resolved best-score-first: an item
    that overlaps an already-claimed span by more than half is left
    clipless for manual review instead of getting a wrong timestamp.
    """
    scored = []
    for idx, item in enumerate(items):
        text = canonical(item["cantonese"])
        if not text:
            scored.append((0.0, 0, 0, idx))
            continue
        cs, ce, score = best_span(text, chars, 0)
        scored.append((score, cs, ce, idx))

    claimed = []  # (cs, ce, score)
    results = [None] * len(items)
    for score, cs, ce, idx in sorted(scored, reverse=True):
        if ce <= cs or score < MIN_SCORE:
            results[idx] = {"id": items[idx]["id"], "score": score, "span": None}
            continue
        span_len = ce - cs
        clash = None
        for qs, qe, qscore in claimed:
            overlap = max(0, min(ce, qe) - max(cs, qs))
            if overlap > 0.5 * span_len:
                clash = (qs, qe, qscore)
                break
        if clash is not None:
            qs, qe, qscore = clash
            if score >= 0.8 and qscore >= 0.8:
                # Same phrase read once, referenced twice (e.g. 今日):
                # share the slice instead of dropping it.
                t0 = max(chars[qs][1] - START_PAD, 0.0)
                t1 = chars[qe - 1][2] + END_PAD
                results[idx] = {
                    "id": items[idx]["id"],
                    "score": score,
                    "span": (round(t0 * 1000), round(t1 * 1000)),
                }
            else:
                results[idx] = {
                    "id": items[idx]["id"], "score": score, "span": None}
            continue
        t0 = max(chars[cs][1] - START_PAD, 0.0)
        t1 = chars[ce - 1][2] + END_PAD
        results[idx] = {
            "id": items[idx]["id"],
            "score": score,
            "span": (round(t0 * 1000), round(t1 * 1000)),
        }
        claimed.append((cs, ce, score))
    # Fix small overlaps: split at midpoint (skip identical shared spans).
    order = sorted(
        [r for r in results if r and r["span"]],
        key=lambda r: r["span"][0],
    )
    for a, b in zip(order, order[1:]):
        if a["span"] == b["span"]:
            continue
        if b["span"][0] < a["span"][1]:
            mid = (a["span"][1] + b["span"][0]) // 2
            a["span"] = (a["span"][0], mid)
            b["span"] = (mid, b["span"][1])
    return results


def transcribe(model, audio_path, vad=False):
    segments, info = model.transcribe(
        audio_path, language="zh", word_timestamps=True, vad_filter=vad
    )
    return list(segments), getattr(info, "duration", 0.0)


def write_review(out_path, audio_rel, items_by_id, aligned):
    rows = []
    for r in aligned:
        item = items_by_id[r["id"]]
        if r["span"]:
            s, e = r["span"]
            player = (
                f'<audio controls preload="none" '
                f'src="{audio_rel}#t={s / 1000:.2f},{e / 1000:.2f}"></audio>'
            )
            stamp = f"{s}–{e} ms"
        else:
            player = "<em>no match</em>"
            stamp = "—"
        low = " style='background:#fff3d6'" if r["score"] < MIN_SCORE else ""
        rows.append(
            f"<tr{low}><td>{html.escape(r['id'])}</td>"
            f"<td>{html.escape(item['cantonese'])}</td>"
            f"<td>{r['score']}</td><td>{stamp}</td><td>{player}</td></tr>"
        )
    page = (
        "<!doctype html><html lang='zh'><meta charset='utf-8'>"
        "<title>timestamp review</title><body>"
        "<h1>Timestamp review — listen & verify each clip</h1>"
        "<table border='1' cellpadding='8'><tr><th>id</th><th>text</th>"
        "<th>score</th><th>clip</th><th>audio</th></tr>"
        + "".join(rows)
        + "</table></body></html>"
    )
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(page)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--model", default="small")
    parser.add_argument("--vad", action="store_true",
                        help="enable Silero VAD pre-filter (default off: "
                             "VAD was found to drop quiet teacher speech)")
    parser.add_argument("--out-dir", default="tools/align/out")
    parser.add_argument("--apply", action="store_true",
                        help="merge clips into the lesson JSON in place")
    args = parser.parse_args()

    lesson_path = args.lesson if os.path.isabs(args.lesson) else os.path.join(REPO, args.lesson)
    with open(lesson_path, encoding="utf-8") as f:
        lesson = json.load(f)
    modules = [m for m in lesson["modules"] if m["id"] == args.module]
    if not modules:
        print(f"module {args.module} not found", file=sys.stderr)
        return 1
    module = modules[0]
    items = module["items"]
    recordings = module.get("recordings", [])
    if not recordings:
        print("module has no recordings", file=sys.stderr)
        return 1

    from faster_whisper import WhisperModel

    print(f"[align] loading model {args.model} ...", flush=True)
    model = WhisperModel(args.model, device="auto", compute_type="auto")

    # Align against every recording, assign each item to its best match.
    per_rec = []
    for ri, rec in enumerate(recordings):
        audio_path = os.path.join(REPO, "assets", rec)
        print(f"[align] transcribing {rec} ...", flush=True)
        segments, _ = transcribe(model, audio_path, vad=args.vad)
        chars = asr_chars(segments)
        print(f"[align] {len(chars)} asr chars", flush=True)
        per_rec.append(align_items(items, chars))

    final = []
    for i, item in enumerate(items):
        best = max(
            ((per_rec[ri][i], ri) for ri in range(len(recordings))),
            key=lambda t: t[0]["score"],
        )
        (match, ri) = best
        clip = None
        if match["span"] and match["score"] >= MIN_SCORE:
            s, e = match["span"]
            clip = {"rec": ri, "startMs": s, "endMs": e} if len(recordings) > 1 else {
                "startMs": s,
                "endMs": e,
            }
        final.append(
            {
                "id": item["id"],
                "score": match["score"],
                "rec": ri,
                "clip": clip,
            }
        )

    n_ok = sum(1 for r in final if r["clip"])
    print(f"[align] matched {n_ok}/{len(items)} items", flush=True)
    for r in final:
        flag = "" if r["clip"] else "  <-- LOW, needs manual check"
        print(f"  {r['id']} score={r['score']} clip={r['clip']}{flag}", flush=True)

    out_dir = args.out_dir if os.path.isabs(args.out_dir) else os.path.join(REPO, args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    clips_path = os.path.join(out_dir, f"{args.module}.clips.json")
    with open(clips_path, "w", encoding="utf-8") as f:
        json.dump(
            {"module": args.module, "recordings": recordings, "clips": final},
            f,
            ensure_ascii=False,
            indent=1,
        )
    print(f"[align] wrote {clips_path}", flush=True)

    items_by_id = {it["id"]: it for it in items}
    audio_rel = os.path.join("..", "..", "..", "assets", recordings[0])
    review_path = os.path.join(out_dir, f"{args.module}.review.html")
    write_review(review_path, audio_rel, items_by_id,
                 [{"id": r["id"], "score": r["score"],
                   "span": (r["clip"]["startMs"], r["clip"]["endMs"]) if r["clip"] else None}
                  for r in final])
    print(f"[align] wrote {review_path}", flush=True)

    if args.apply:
        by_id = {r["id"]: r["clip"] for r in final}
        applied = 0
        for it in module["items"]:
            clip = by_id.get(it["id"])
            if clip:
                # Keep existing word timings when the span is unchanged so a
                # re-align never nukes karaoke data (extract_words.py only
                # needs re-running when spans actually move).
                old = it.get("clip") or {}
                if (isinstance(old, dict) and old.get("words")
                        and old.get("startMs") == clip.get("startMs")
                        and old.get("endMs") == clip.get("endMs")
                        and old.get("rec", 0) == clip.get("rec", 0)):
                    clip["words"] = old["words"]
                it["clip"] = clip
                applied += 1
            else:
                it.pop("clip", None)
        with open(lesson_path, "w", encoding="utf-8") as f:
            json.dump(lesson, f, ensure_ascii=False, indent=1)
            f.write("\n")
        print(f"[align] applied {applied} clips to {lesson_path}", flush=True)

    print("ALIGN_DONE", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
