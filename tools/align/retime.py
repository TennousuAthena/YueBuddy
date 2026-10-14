"""Rebuild teacher-audio timelines from speech energy, not from cut points.

The old pipeline did two things that make karaoke run ahead of the voice:

* Refined clips grow until they touch a neighbour, then the overlap is
  cut at its midpoint — often through a syllable. Every character that
  fell before that cut is clamped onto the same millisecond, so they
  light up together.
* Word times trust Whisper's raw clock. Those starts sit in the pause
  (or in the previous word), and unmatched characters get a 30 ms stub
  instead of a share of the syllable.

This pass keeps Whisper for *what* was said and uses the energy islands
for *when* it was said. Each lesson item owns the islands its text
actually matches. Character starts are placed inside those islands, in
order, and never share a millisecond.

    python3 tools/align/retime.py --lesson assets/lessons/lesson_4.json --module l4-sport
    python3 tools/align/retime.py --all --apply
"""
import argparse
import difflib
import json
import os
import sys

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from align_module import asr_chars, canonical  # noqa: E402
from extract_words import fold_with_map  # noqa: E402
from align_module import norm, simp_text  # noqa: E402
from refine_clips import (  # noqa: E402
    HOP,
    SR,
    decode_mono,
    frame_rms,
    speech_mask,
    to_ms,
)

MIN_ISLAND_MS = 160
# A short vocab item that also contains the next word's island.
SHORT_ITEM_CHARS = 8
STEAL_OWNER = 0.55
STEAL_OTHER = 0.80
MATCH_COVERAGE = 0.40


def speech_islands(audio):
    """Audible spans in milliseconds. Pauses under 150 ms stay inside."""
    rms = frame_rms(audio)
    if len(rms) == 0:
        return []
    noise = float(np.percentile(rms, 10))
    peak = float(rms.max())
    threshold = max(noise * 3.0, peak * 0.015, 5e-4)
    mask = speech_mask(rms, threshold)
    islands = []
    i = 0
    n = len(mask)
    while i < n:
        if not mask[i]:
            i += 1
            continue
        j = i
        while j < n and mask[j]:
            j += 1
        start, end = to_ms(i), to_ms(j)
        if end - start >= MIN_ISLAND_MS:
            islands.append((start, end))
        i = j
    return islands


def monotonic_chars(chars):
    """Drop inverted Whisper times and keep the stream from running backward."""
    out = []
    prev = 0.0
    for ch, start, end in chars:
        if not ch or end <= start:
            continue
        start = max(start, prev)
        if end <= start:
            continue
        out.append((ch, start, end))
        prev = end
    return out


def chars_from_segments(segments):
    return monotonic_chars(asr_chars(segments))


def island_labels(islands, chars):
    """Canonical ASR text of each island, using word *ends* as the clock."""
    labels = []
    grouped = [[] for _ in islands]
    for ch, _start, end in chars:
        idx = island_index(end, islands)
        if idx is not None:
            grouped[idx].append(ch)
    for group in grouped:
        labels.append("".join(group))
    return labels


def island_index(end_s, islands, pad_ms=150):
    end_ms = end_s * 1000
    for i, (start, stop) in enumerate(islands):
        if start - pad_ms <= end_ms <= stop + pad_ms:
            return i
    best, dist = None, 1e9
    for i, (start, stop) in enumerate(islands):
        if start <= end_ms <= stop:
            return i
        dist_i = min(abs(end_ms - start), abs(end_ms - stop))
        if dist_i < dist:
            best, dist = i, dist_i
    if dist <= 250:
        return best
    return None


def island_coverage(item_text, label):
    """How much of an island's ASR text is found, in order, in the item."""
    item = canonical(item_text)
    if not item or not label:
        return 0.0
    matcher = difflib.SequenceMatcher(None, item, label, autojunk=False)
    matched = sum(block.size for block in matcher.get_matching_blocks())
    return matched / len(label)


def _clip_pair(item, rec):
    clip = item.get("clip")
    if not clip:
        return None
    if clip.get("rec", 0) != rec:
        return None
    return clip["startMs"], clip["endMs"]


def _same_clip(a, b):
    if not a or not b:
        return False
    return abs(a[0] - b[0]) <= 40 and abs(a[1] - b[1]) <= 40


def carve_unclaimed_tails(items, islands, chars, shares, eligible):
    """Split one energy island that actually contains two sentences.

    A short pause never opens a second island, so the whole stretch was
    given to whichever card contained the midpoint. If another card with
    no audio of its own matches the unused tail, hand that tail over.
    """
    carves = []  # (island, tail_item, cut_ms, end_ms)
    for k, (lo, hi) in enumerate(islands):
        if len(shares[k]) != 1:
            continue
        owner = shares[k][0]
        local = [
            c for c in chars
            if lo - 120 <= c[2] * 1000 <= hi + 150
        ]
        if len(local) < 4:
            continue
        label = "".join(c[0] for c in local)
        owner_text = canonical(items[owner]["cantonese"])
        matcher = difflib.SequenceMatcher(None, owner_text, label, autojunk=False)
        blocks = [b for b in matcher.get_matching_blocks() if b.size and b.b < len(label) * 0.8]
        if not blocks:
            continue
        last = max(b.b + b.size for b in blocks)
        if last >= len(label) - 2:
            continue
        tail = label[last:]
        tail_chars = local[last:]
        best = None
        for i, item in enumerate(items):
            if i == owner or not eligible[i]:
                continue
            if any(i in shares[j] for j in range(len(islands))):
                continue
            score = island_coverage(item["cantonese"], tail)
            if best is None or score > best[0]:
                best = (score, i)
        if not best or best[0] < 0.55:
            continue
        cut = int(round(tail_chars[0][1] * 1000))
        cut = min(max(cut, lo + 200), hi - 200)
        carves.append((k, best[1], cut, hi))
    return carves


def assign_islands(items, islands, labels, clips, eligible=None):
    """Return shares[island] = [item indexes] that should use that island.

    `clips[i]` is (startMs, endMs) or None for this recording.
    `eligible[i]` is false for cards whose clip lives on another file.
    """
    if eligible is None:
        eligible = [True] * len(items)
    n = len(islands)
    shares = [[] for _ in range(n)]

    def cov(item_i, island_i):
        return island_coverage(items[item_i]["cantonese"], labels[island_i])

    def owns(item_i):
        return [k for k in range(n) if item_i in shares[k]]

    # The existing clip is only a hint: an island belongs to every item
    # whose clip contains the island's midpoint. Identical shared clips
    # (one utterance, two cards) stay shared.
    for k, (start, stop) in enumerate(islands):
        mid = (start + stop) // 2
        contenders = [
            i for i, clip in enumerate(clips)
            if eligible[i] and clip and clip[0] <= mid <= clip[1]
        ]
        if not contenders:
            continue
        contenders.sort(key=lambda i: cov(i, k), reverse=True)
        primary = contenders[0]
        shares[k].append(primary)
        for other in contenders[1:]:
            if _same_clip(clips[other], clips[primary]) and cov(other, k) >= 0.45:
                shares[k].append(other)

    def drop(item_i, island_i):
        if item_i in shares[island_i]:
            shares[island_i].remove(item_i)

    # A two-character card must not keep the next word just because the
    # old clip was wide enough to cover both midpoints.
    for i, item in enumerate(items):
        owned = owns(i)
        if len(owned) < 2:
            continue
        if len(canonical(item["cantonese"])) > SHORT_ITEM_CHARS:
            continue
        if not eligible[i]:
            continue
        good = [k for k in owned if labels[k] and cov(i, k) >= 0.35]
        if not good:
            good = [max(owned, key=lambda k: cov(i, k))]
        for k in owned:
            if k in good:
                continue
            # A one-syllable mishear ("廿" → "三") must not knock the
            # second reading off a slash card.
            if len(labels[k]) < 2:
                continue
            prev_good = max((g for g in good if g < k), default=None)
            gap = islands[k][0] - islands[prev_good][1] if prev_good is not None else 9999
            if gap > 400 or cov(i, k) < 0.35:
                drop(i, k)

    # Hand an island to the sentence it actually belongs to when the
    # midpoint hint grabbed the neighbour.
    for k in range(n):
        if not labels[k]:
            continue
        scored = sorted(
            ((cov(i, k), i) for i in range(len(items)) if eligible[i]),
            reverse=True,
        )
        if not scored:
            continue
        best_s, best_i = scored[0]
        current = shares[k][0] if shares[k] else None
        current_s = cov(current, k) if current is not None else 0.0
        if current is not None and current_s >= STEAL_OWNER:
            continue
        # One recognized syllable is not enough to pull an island off
        # the card that already covers it. "廿" misheard as "三" would
        # otherwise be stolen by 三十.
        if current is not None and len(labels[k]) < 2:
            continue
        if best_s < STEAL_OTHER or best_s < current_s + 0.25:
            continue
        shares[k] = [best_i]

    def contiguous_runs(indexes):
        if not indexes:
            return []
        runs = [[indexes[0]]]
        for k in indexes[1:]:
            if k == runs[-1][-1] + 1:
                runs[-1].append(k)
            else:
                runs.append([k])
        return runs

    # Drop a far-away island that a steal attached to the wrong card.
    for i, clip in enumerate(clips):
        owned = owns(i)
        runs = contiguous_runs(owned)
        if len(runs) <= 1:
            continue
        def run_key(run):
            dur = sum(islands[k][1] - islands[k][0] for k in run)
            if not clip:
                return (0, dur)
            overlap = 0
            for k in run:
                overlap += max(0, min(clip[1], islands[k][1]) - max(clip[0], islands[k][0]))
            return (overlap, dur)
        keep = max(runs, key=run_key)
        for run in runs:
            if run is keep:
                continue
            for k in run:
                drop(i, k)

    # A slash card often has a second reading Whisper mangled
    # (躺平／Hea heard as 戏). Keep the following unclaimed island.
    for i, item in enumerate(items):
        if not eligible[i]:
            continue
        text = item["cantonese"]
        if "／" not in text and "/" not in text:
            continue
        owned = owns(i)
        if not owned:
            continue
        nxt = owned[-1] + 1
        if nxt < n and not shares[nxt]:
            gap = islands[nxt][0] - islands[owned[-1]][1]
            if 0 <= gap < 2000:
                shares[nxt].append(i)

    # Leftover islands: only a card with no island yet, and only on a
    # clear text match. Guessing by lesson order mis-files words the
    # teacher read out of order.
    for k in range(n):
        if shares[k] or not labels[k]:
            continue
        scored = []
        for i in range(len(items)):
            if not eligible[i] or owns(i):
                continue
            score = cov(i, k)
            if score >= 0.6:
                scored.append((score, i))
        if scored:
            scored.sort(reverse=True)
            shares[k] = [scored[0][1]]

    leftover = [k for k in range(n) if not shares[k]]
    needy = [
        i for i in range(len(items))
        if eligible[i] and clips[i] is None and not owns(i)
    ]
    if len(leftover) == 1 and len(needy) == 1:
        shares[leftover[0]] = [needy[0]]
    return shares


def _explode(chars):
    """One timing per character. Whisper sometimes emits a whole latin word."""
    flat = []
    for ch, start, end in chars:
        if not ch:
            continue
        if len(ch) == 1:
            flat.append((ch, start, end))
            continue
        dur = max(end - start, 0.01) / len(ch)
        for i, piece in enumerate(ch):
            flat.append((piece, start + dur * i, start + dur * (i + 1)))
    return flat


def match_char_times(display, chars):
    """Align lesson characters to ASR times. Unmatched slots stay None.

    Returns (normalized text, list of (start_s, end_s) or None).
    """
    target = norm(display)
    chars = _explode(chars)
    if not target:
        return target, []
    if not chars:
        return target, [None] * len(target)
    match_base = simp_text(target)
    if len(match_base) != len(target):
        match_base = target
    folded, src_of = fold_with_map(match_base)
    heard = "".join(ch for ch, _s, _e in chars)
    wanted = "".join(folded)
    matcher = difflib.SequenceMatcher(None, wanted, heard, autojunk=False)
    timed = [None] * len(folded)
    for block in matcher.get_matching_blocks():
        for k in range(block.size):
            timed[block.a + k] = chars[block.b + k][1:3]
    per_src = {}
    for folded_i, src_i in enumerate(src_of):
        if timed[folded_i] is not None:
            per_src.setdefault(src_i, []).append(timed[folded_i])
    out = []
    for i in range(len(target)):
        segs = per_src.get(i)
        if not segs:
            out.append(None)
            continue
        out.append((min(s for s, _e in segs), max(e for _s, e in segs)))
    return target, out


def _coverage(times):
    if not times:
        return 0.0
    return sum(1 for t in times if t) / len(times)


def _even_over_speech(count, islands):
    """Place `count` slices across islands, skipping the silences between."""
    if count <= 0:
        return []
    total = sum(stop - start for start, stop in islands)
    if total <= 0:
        return [(islands[0][0], islands[0][0] + 1)] * count

    def at(speech_ms):
        speech_ms = min(max(speech_ms, 0), total)
        cursor = 0
        for start, stop in islands:
            span = stop - start
            if cursor + span >= speech_ms or (start, stop) == islands[-1]:
                return start + (speech_ms - cursor)
            cursor += span
        return islands[-1][1]

    slices = []
    for i in range(count):
        start = at(total * i / count)
        end = at(total * (i + 1) / count)
        slices.append((start, max(end, start + 1)))
    return _strict(slices, islands[0][0], islands[-1][1])


def _separate_clumps(starts, hi, min_gap):
    """Push characters that would light on the same tick apart.

    Only a clump moves, and only into the gap before the next character
    that already has its own time. A sentence with real syllable gaps
    stays where Whisper put it.
    """
    out = starts[:]
    i = 0
    count = len(out)
    while i < count:
        j = i
        while j + 1 < count and out[j + 1] - out[j] < min_gap:
            j += 1
        if j == i:
            i += 1
            continue
        limit = out[j + 1] if j + 1 < count else hi
        slots = j - i
        width = limit - out[i]
        if width >= min_gap * slots + 1:
            for k in range(1, slots + 1):
                out[i + k] = out[i] + min_gap * k
        else:
            for k in range(1, slots + 1):
                out[i + k] = out[i] + max(1, width * k // (slots + 1))
        i = j + 1
    return out


def _strict(slices, lo, hi):
    """Integer milliseconds, strictly increasing, inside [lo, hi)."""
    if not slices:
        return []
    span = max(hi - lo, len(slices))
    starts = []
    for i, (start, _end) in enumerate(slices):
        start = min(max(int(round(start)), lo), hi - 1)
        starts.append(start)
    for i in range(1, len(starts)):
        if starts[i] <= starts[i - 1]:
            starts[i] = starts[i - 1] + 1
    starts = _separate_clumps(starts, hi, min_gap=40)
    overflow = starts[-1] - (hi - 1)
    if overflow > 0:
        starts = [s - overflow for s in starts]
        for i in range(len(starts)):
            starts[i] = max(starts[i], lo + i)
    ends = starts[1:] + [max(hi, starts[-1] + 1)]
    for i in range(len(starts)):
        if ends[i] <= starts[i]:
            ends[i] = starts[i] + 1
    return list(zip(starts, ends))


def _layout_group(indexes, times, lo, hi):
    """Lay character indexes out inside one island [lo, hi] (seconds)."""
    count = len(indexes)
    if count == 0:
        return {}
    anchors = []
    for pos, idx in enumerate(indexes):
        if not times[idx]:
            continue
        start, end = times[idx]
        start = min(max(start, lo), hi)
        end = min(max(end, start), hi)
        anchors.append((pos, start, end))
    if not anchors:
        slices = _even_over_speech(count, [(int(lo * 1000), int(hi * 1000))])
        return {indexes[i]: slices[i] for i in range(count)}

    starts = [None] * count
    ends = [None] * count
    for pos, start, end in anchors:
        starts[pos] = start
        ends[pos] = end
    points = [(-1, lo, lo)]
    points += [(pos, starts[pos], ends[pos]) for pos in range(count) if starts[pos] is not None]
    points.append((count, hi, hi))
    for (pos0, start0, end0), (pos1, start1, end1) in zip(points, points[1:]):
        gap = pos1 - pos0 - 1
        if gap <= 0:
            continue
        left, right = end0, max(start1, end0)
        need = gap * 0.05
        if right - left < need:
            prev_dur = max(end0 - start0, 0.0) if pos0 >= 0 else 0.0
            next_dur = max(end1 - start1, 0.0) if pos1 < count else 0.0
            extra = need - (right - left)
            take_left = min(extra * 0.5, prev_dur * 0.45)
            take_right = min(extra - take_left, next_dur * 0.45)
            left -= take_left
            right += take_right
            if pos0 >= 0 and ends[pos0] is not None:
                ends[pos0] = min(ends[pos0], left)
            if pos1 < count and starts[pos1] is not None:
                starts[pos1] = max(starts[pos1], right)
        width = max(right - left, gap * 0.001)
        for g in range(gap):
            slot = pos0 + 1 + g
            starts[slot] = left + width * g / gap
            ends[slot] = left + width * (g + 1) / gap
    pairs = []
    for pos in range(count):
        start = lo if starts[pos] is None else starts[pos]
        end = hi if ends[pos] is None else ends[pos]
        pairs.append((start * 1000, max(end, start) * 1000))
    fixed = _strict(pairs, int(round(lo * 1000)), int(round(hi * 1000)))
    fixed = _fill_island(fixed, int(round(lo * 1000)), int(round(hi * 1000)))
    return {indexes[pos]: fixed[pos] for pos in range(count)}


def _fill_island(pairs, lo, hi):
    """Spread a word that Whisper crushed into the start of a long island.

    Vocab islands are one utterance. If every character landed in the
    first half, the clock was the early Whisper stamp, not the voice.
    """
    if len(pairs) <= 1:
        return pairs
    starts = [start for start, _end in pairs]
    dur = hi - lo
    used = starts[-1] - lo
    if dur < 200 or used >= dur * 0.5 or starts[-1] <= starts[0]:
        return pairs
    scale = (dur - 1) / (starts[-1] - starts[0])
    stretched = []
    for start, end in pairs:
        ns = lo + (start - starts[0]) * scale
        ne = lo + (end - starts[0]) * scale
        stretched.append((ns, max(ne, ns + 1)))
    return _strict(stretched, lo, hi)


def _assign_chars_to_islands(times, islands):
    """Island index per character. Unmatched characters stay with a neighbour."""
    assigned = [None] * len(times)
    for i, timing in enumerate(times):
        if not timing:
            continue
        assigned[i] = island_index(timing[1], islands)
    i = 0
    while i < len(assigned):
        if assigned[i] is not None:
            i += 1
            continue
        j = i
        while j < len(assigned) and assigned[j] is None:
            j += 1
        left = assigned[i - 1] if i > 0 else None
        right = assigned[j] if j < len(assigned) else None
        if left is None and right is None:
            return None
        if left is None or left == right:
            fill = right if left is None else left
            for k in range(i, j):
                assigned[k] = fill
        elif right is None:
            for k in range(i, j):
                assigned[k] = left
        else:
            island_ids = list(range(left, right + 1))
            weights = []
            for pos, island_i in enumerate(island_ids):
                dur = islands[island_i][1] - islands[island_i][0]
                if pos == 0 or pos == len(island_ids) - 1:
                    dur *= 0.35
                weights.append(max(dur, 1))
            counts = _apportion(j - i, weights)
            cursor = i
            for island_i, take in zip(island_ids, counts):
                for k in range(cursor, cursor + take):
                    assigned[k] = island_i
                cursor += take
        i = j
    # A later island with no ASR match still belongs to this card
    # (the second reading of 躺平／Hea). Park the unmatched tail there
    # instead of leaving it on the previous word.
    matched_islands = {
        assigned[i] for i, timing in enumerate(times) if timing and assigned[i] is not None
    }
    suffix = []
    for island_i in range(len(islands) - 1, -1, -1):
        if island_i in matched_islands:
            break
        suffix.append(island_i)
    suffix.reverse()
    if suffix:
        end = len(times)
        while end > 0 and not times[end - 1]:
            end -= 1
        trail = list(range(end, len(times)))
        if trail:
            weights = [max(islands[k][1] - islands[k][0], 1) for k in suffix]
            counts = _apportion(len(trail), weights)
            cursor = 0
            for island_i, take in zip(suffix, counts):
                for idx in trail[cursor:cursor + take]:
                    assigned[idx] = island_i
                cursor += take
    return assigned


def _apportion(total, weights):
    if total <= 0:
        return [0] * len(weights)
    weight_sum = sum(weights) or 1
    raw = [total * w / weight_sum for w in weights]
    counts = [int(v) for v in raw]
    leftover = total - sum(counts)
    order = sorted(range(len(raw)), key=lambda i: raw[i] - counts[i], reverse=True)
    for i in range(leftover):
        counts[order[i % len(order)]] += 1
    return counts


def build_timeline(display, chars, islands):
    """Return {t, w, startMs, endMs, method} or None.

    `islands` are the audible spans for this one item, in order.
    """
    if not islands:
        return None
    target, times = match_char_times(display, chars)
    if not target:
        return None
    method = "asr"
    if _coverage(times) < MATCH_COVERAGE:
        slices = _even_over_speech(len(target), islands)
        method = "even"
    else:
        local_chars = [
            (ch, start, end)
            for ch, start, end in chars
            if island_index(end, islands) is not None
        ]
        # Rematch against only this item's audio so a neighbour's
        # repeated word cannot steal a character.
        target, times = match_char_times(display, local_chars)
        if _coverage(times) < MATCH_COVERAGE:
            slices = _even_over_speech(len(target), islands)
            method = "even"
        else:
            assigned = _assign_chars_to_islands(times, islands)
            if assigned is None:
                slices = _even_over_speech(len(target), islands)
                method = "even"
            else:
                placed = {}
                for island_i, (lo, hi) in enumerate(islands):
                    indexes = [i for i, owner in enumerate(assigned) if owner == island_i]
                    placed.update(_layout_group(indexes, times, lo / 1000, hi / 1000))
                slices = [placed[i] for i in range(len(target))]
                slices = _strict(slices, islands[0][0], islands[-1][1])
    flat = []
    for start, end in slices:
        flat += [int(start), int(end)]
    # Starts have to fall inside some island. The strict pass can pull a
    # start across a silence when an island is shorter than its character
    # count; snap those back and re-spread inside the islands.
    if not _starts_inside(flat, islands):
        slices = _even_over_speech(len(target), islands)
        flat = []
        for start, end in slices:
            flat += [int(start), int(end)]
        method = "even"
    return {
        "t": target,
        "w": flat,
        "startMs": islands[0][0],
        "endMs": islands[-1][1],
        "method": method,
    }


def _starts_inside(flat, islands):
    starts = flat[0::2]
    for start in starts:
        if not any(lo <= start < hi for lo, hi in islands):
            return False
    return True


def clip_bounds(island_indexes, islands):
    """Island union plus a short pad that stops halfway to the neighbour."""
    first = island_indexes[0]
    last = island_indexes[-1]
    start = islands[first][0]
    end = islands[last][1]
    prev_end = islands[first - 1][1] if first > 0 else 0
    next_start = islands[last + 1][0] if last + 1 < len(islands) else end + 1000
    pad_left = min(50, max(0, (start - prev_end) // 2))
    pad_right = min(80, max(0, (next_start - end) // 2))
    return start - pad_left, end + pad_right


def _chars_touching(chars, island_indexes, islands):
    wanted = set(island_indexes)
    out = []
    for ch, start, end in chars:
        idx = island_index(end, islands)
        if idx in wanted:
            out.append((ch, start, end))
    return out


def plan_recording(items, islands, chars, rec):
    """Per-item timelines for one recording. Items keep their original index."""
    labels = island_labels(islands, chars)
    clips = [_clip_pair(item, rec) for item in items]
    eligible = [
        item.get("clip") is None or item["clip"].get("rec", 0) == rec
        for item in items
    ]
    shares = assign_islands(items, islands, labels, clips, eligible)
    carves = carve_unclaimed_tails(items, islands, chars, shares, eligible)
    shrunk = {}
    tails = {}
    for island_i, tail_item, cut, end in carves:
        shrunk[(shares[island_i][0], island_i)] = cut
        tails.setdefault(tail_item, []).append((cut, end))
    results = [None] * len(items)
    for item_i, item in enumerate(items):
        owned = [k for k in range(len(islands)) if item_i in shares[k]]
        ranges = []
        for k in owned:
            lo, hi = islands[k]
            hi = shrunk.get((item_i, k), hi)
            if hi - lo >= 200:
                ranges.append((lo, hi))
        ranges.extend(tails.get(item_i, []))
        ranges.sort()
        if not ranges:
            continue
        # A carved tail meets the previous card at `cut`, so it must not
        # be padded back across that boundary.
        if item_i in tails or any((item_i, k) in shrunk for k in owned):
            bounds = (ranges[0][0], ranges[-1][1])
        else:
            bounds = clip_bounds(owned, islands)
        local = [
            c for c in chars
            if any(lo - 120 <= c[2] * 1000 <= hi + 150 for lo, hi in ranges)
        ]
        timeline = build_timeline(item["cantonese"], local, ranges)
        if timeline is None:
            continue
        timeline["startMs"] = bounds[0]
        timeline["endMs"] = bounds[1]
        if not _valid(timeline):
            continue
        timeline["islands"] = ranges
        timeline["rec"] = rec
        results[item_i] = timeline
    return results, labels, shares


def _valid(timeline):
    text = timeline["t"]
    flat = timeline["w"]
    if len(flat) != len(text) * 2 or not text:
        return False
    starts = flat[0::2]
    if any(starts[i] <= starts[i - 1] for i in range(1, len(starts))):
        return False
    if timeline["endMs"] - timeline["startMs"] < 200:
        return False
    if starts[0] < timeline["startMs"] or starts[-1] >= timeline["endMs"]:
        return False
    return True


def apply_timeline(item, timeline):
    clip = {
        "startMs": int(timeline["startMs"]),
        "endMs": int(timeline["endMs"]),
        "words": {"t": timeline["t"], "w": [int(v) for v in timeline["w"]]},
    }
    rec = timeline.get("rec", 0)
    if rec:
        clip = {"rec": rec, **clip}
    item["clip"] = clip


def transcribe_words(model, path):
    segments, _info = model.transcribe(
        path, language="zh", word_timestamps=True, vad_filter=False
    )
    rows = []
    for seg in segments:
        for word in seg.words or []:
            if not word.word:
                continue
            rows.append({"w": word.word, "s": word.start, "e": word.end})
    return rows


class _Word:
    def __init__(self, word, start, end):
        self.word = word
        self.start = start
        self.end = end


class _Segment:
    def __init__(self, words):
        self.words = words


def chars_from_words(rows):
    segment = _Segment([_Word(row["w"], row["s"], row["e"]) for row in rows])
    return chars_from_segments([segment])


def load_or_transcribe(model, audio_path, cache_path):
    """Cache raw Whisper words so alias edits don't force a re-transcribe."""
    if os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as handle:
            rows = json.load(handle)
    else:
        rows = transcribe_words(model, audio_path)
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path, "w", encoding="utf-8") as handle:
            json.dump(rows, handle, ensure_ascii=False)
    return chars_from_words(rows)


def process_lesson(lesson_path, module_id, model_name, cache_dir, apply, only_report):
    from faster_whisper import WhisperModel

    with open(lesson_path, encoding="utf-8") as handle:
        lesson = json.load(handle)
    modules = lesson["modules"]
    if module_id:
        modules = [m for m in modules if m["id"] == module_id]
    model = None
    changed = 0
    for module in modules:
        recordings = module.get("recordings") or []
        if not recordings:
            continue
        print(f"\n== {module['id']} ==", flush=True)
        for rec, rel in enumerate(recordings):
            audio_path = os.path.join(REPO, "assets", rel)
            safe = rel.replace("/", "__")
            cache_path = os.path.join(cache_dir, safe + ".chars.json")
            if model is None and not os.path.exists(cache_path):
                print(f"[retime] loading {model_name}", flush=True)
                model = WhisperModel(model_name, device="auto", compute_type="int8")
            print(f"[retime] {rel}", flush=True)
            chars = load_or_transcribe(model, audio_path, cache_path)
            audio = decode_mono(audio_path)
            islands = speech_islands(audio)
            results, labels, shares = plan_recording(module["items"], islands, chars, rec)
            for item_i, item in enumerate(module["items"]):
                # A clipless item may be planned against every recording;
                # keep the first recording that produced a timeline.
                if item.get("clip") and item["clip"].get("rec", 0) != rec:
                    continue
                timeline = results[item_i]
                old = item.get("clip")
                if timeline is None:
                    if old and old.get("rec", 0) == rec:
                        mid = (old["startMs"] + old["endMs"]) // 2
                        taken = False
                        for k, (start, stop) in enumerate(islands):
                            if start <= mid <= stop and item_i not in shares[k] and shares[k]:
                                taken = True
                                break
                        if taken:
                            print(
                                f"  {item['id']} DROP stale clip "
                                f"{old['startMs']}-{old['endMs']} {item['cantonese'][:20]}",
                                flush=True,
                            )
                            if apply and not only_report:
                                item.pop("clip", None)
                                changed += 1
                    continue
                if item.get("clip") and item["clip"].get("rec", 0) != rec:
                    continue
                old = item.get("clip")
                new_span = (timeline["startMs"], timeline["endMs"])
                old_span = (old["startMs"], old["endMs"]) if old else None
                moved = old_span != new_span
                flag = ""
                if moved:
                    flag = f"  MOVED {old_span} -> {new_span}"
                owned = [k for k in range(len(islands)) if item_i in shares[k]]
                print(
                    f"  {item['id']} {timeline['method']} islands={owned} "
                    f"{item['cantonese'][:28]}{flag}",
                    flush=True,
                )
                if apply and not only_report:
                    # Don't let a later recording overwrite a clip that
                    # already belongs to an earlier file.
                    if old and old.get("rec", 0) != rec:
                        continue
                    apply_timeline(item, timeline)
                    changed += 1
            for k, label in enumerate(labels):
                if not shares[k]:
                    print(
                        f"  .. unused island {islands[k][0]}-{islands[k][1]} '{label}'",
                        flush=True,
                    )
        if apply and not only_report:
            for item in module["items"]:
                if item.get("clip"):
                    continue
                # Left clipless on purpose when no island matched.
    if apply and not only_report:
        with open(lesson_path, "w", encoding="utf-8") as handle:
            json.dump(lesson, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
        print(f"[retime] wrote {lesson_path} ({changed} clips)", flush=True)
    return changed


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lesson", default=None)
    parser.add_argument("--module", default=None)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--model", default="small")
    parser.add_argument("--cache", default="tools/align/out/cache/retime")
    args = parser.parse_args()
    lessons = [
        "assets/lessons/lesson_1.json",
        "assets/lessons/lesson_2.json",
        "assets/lessons/lesson_3.json",
        "assets/lessons/lesson_4.json",
    ] if args.all else [args.lesson]
    cache = args.cache if os.path.isabs(args.cache) else os.path.join(REPO, args.cache)
    total = 0
    for rel in lessons:
        path = rel if os.path.isabs(rel) else os.path.join(REPO, rel)
        total += process_lesson(path, args.module, args.model, cache, args.apply, False)
    print(f"RETIME_DONE changed={total}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
