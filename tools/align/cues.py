"""Speech regions from three acoustic cues, not loudness alone.

Cantonese tones — especially low and falling ones — stay pitched after
the RMS has already dropped under a loudness gate, so an energy-only
cut chops the syllable. Unvoiced onsets (fricatives) have almost no
pitch but a clear voice-band spectrum. A frame counts as speech when
any of the three says so:

  * RMS loudness above the noise floor
  * autocorrelation pitch in the tone range (about 75–420 Hz)
  * energy concentrated in the voice band (200–4200 Hz)
"""
import numpy as np

from refine_clips import FRAME, HOP, SR, decode_mono, frame_rms

BRIDGE_GAP = 0.18
MIN_ISLAND = 0.12
PAD = 0.06


def _frames(audio):
    n = 1 + max(0, (len(audio) - FRAME) // HOP)
    if n <= 0:
        return np.zeros((0, FRAME), dtype=np.float64)
    idx = np.arange(FRAME)[None, :] + HOP * np.arange(n)[:, None]
    return audio[idx].astype(np.float64)


def frame_voiced(frames, rms):
    """True where a stable pitch (a tone) is present, even if quiet."""
    if len(frames) == 0:
        return np.zeros(0, dtype=bool)
    centered = frames - frames.mean(axis=1, keepdims=True)
    nfft = 512
    spec = np.fft.rfft(centered, n=nfft, axis=1)
    ac = np.fft.irfft(np.abs(spec) ** 2, n=nfft, axis=1)
    ac0 = ac[:, 0] + 1e-8
    min_lag = max(1, int(SR / 420))
    max_lag = min(ac.shape[1] - 1, int(SR / 75))
    peak = ac[:, min_lag:max_lag].max(axis=1) / ac0
    # Low / falling tones get quiet. Keep them if a pitch is still there.
    return (peak > 0.34) & (rms > 0.0014)


def frame_voice_ratio(frames):
    """Share of energy sitting in the speech band, per frame."""
    if len(frames) == 0:
        return np.zeros(0, dtype=np.float64)
    window = np.hanning(FRAME)
    power = np.abs(np.fft.rfft(frames * window, axis=1)) ** 2
    freqs = np.fft.rfftfreq(FRAME, 1.0 / SR)
    band = (freqs >= 200) & (freqs <= 4200)
    total = power.sum(axis=1) + 1e-12
    return power[:, band].sum(axis=1) / total


def _bridge(mask, gap_s):
    out = mask.copy()
    gap = int(gap_s * SR / HOP)
    i = 0
    n = len(out)
    while i < n:
        if out[i]:
            i += 1
            continue
        j = i
        while j < n and not out[j]:
            j += 1
        if j < n and (j - i) <= gap and i > 0:
            out[i:j] = True
        i = j
    return out


def _islands(mask):
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
        s = i * HOP / SR
        e = j * HOP / SR
        if e - s >= MIN_ISLAND:
            islands.append((s, e))
        i = j
    return islands


def _pad(islands, duration):
    padded = []
    for i, (s, e) in enumerate(islands):
        left = 0.0 if i == 0 else (islands[i - 1][1] + s) / 2
        right = duration if i + 1 == len(islands) else (e + islands[i + 1][0]) / 2
        padded.append((max(left, s - PAD), min(right, e + PAD)))
    return padded


def analyze(audio):
    """Return (islands, voiced, duration_s).

    islands are (start, end) in seconds. voiced is one bool per 10 ms frame.
    """
    duration = len(audio) / SR
    rms = frame_rms(audio)
    frames = _frames(audio)
    voiced = frame_voiced(frames, rms)
    ratio = frame_voice_ratio(frames)
    if len(rms) == 0:
        return [], voiced, duration
    noise = float(np.percentile(rms, 12))
    peak = float(np.percentile(rms, 98))
    hi = max(noise * 3.0, peak * 0.02, 7e-4)
    lo = max(noise * 1.45, peak * 0.0045, 1.8e-4)
    speech = (rms >= hi) | ((rms >= lo) & voiced) | ((rms >= lo) & (ratio > 0.55))
    speech = _bridge(speech, BRIDGE_GAP)
    islands = _trim_onset(_islands(speech), rms, hi)
    return _pad(islands, duration), voiced, duration


def _trim_onset(islands, rms, hi):
    """Drop a quiet lead-in. The tone tail at the end stays."""
    trimmed = []
    for s, e in islands:
        sf = int(s * SR / HOP)
        ef = min(len(rms) - 1, int(e * SR / HOP))
        k = sf
        while k < ef and rms[k] < hi:
            k += 1
        ns = k * HOP / SR
        if e - ns >= MIN_ISLAND:
            trimmed.append((min(ns, e - MIN_ISLAND), e))
    return trimmed


def nuclei(voiced, start_s, end_s):
    """Voiced runs inside [start_s, end_s]: one run is one tone syllable."""
    if len(voiced) == 0:
        return []
    sf = max(0, int(start_s * SR / HOP))
    ef = min(len(voiced) - 1, int(end_s * SR / HOP))
    runs = []
    i = sf
    while i <= ef:
        if not voiced[i]:
            i += 1
            continue
        j = i
        while j <= ef and voiced[j]:
            j += 1
        s = i * HOP / SR
        e = j * HOP / SR
        if e - s >= 0.045:
            if runs and s - runs[-1][1] < 0.04:
                runs[-1] = (runs[-1][0], e)
            else:
                runs.append((s, e))
        i = j
    return runs


def fit_nuclei(runs, n):
    """Merge extra pitch splits, or split one glued pair, to get n tones.

    Returns None when the pitch track is too far from the character count
    to trust — the caller keeps the ASR timings in that case.
    """
    if n <= 0 or not runs:
        return None
    nuc = [list(r) for r in runs]
    while len(nuc) > n:
        if len(nuc) < 2:
            return None
        i = min(range(len(nuc) - 1), key=lambda k: nuc[k + 1][0] - nuc[k][1])
        nuc[i][1] = nuc[i + 1][1]
        del nuc[i + 1]
    if len(nuc) == n:
        return [(a, b) for a, b in nuc]
    # One short means a tone boundary was missed. Chopping the longest
    # run in half is a guess, so leave timings to ASR instead.
    return None


def extend_through_tone(voiced, start_s, end_s, left_limit, right_limit, limit=1.15):
    """If a boundary lands inside a tone, move it out to the tone edge."""
    if len(voiced) == 0:
        return start_s, end_s

    def frame_at(t):
        return max(0, min(len(voiced) - 1, int(t * SR / HOP)))

    def time_at(i):
        return i * HOP / SR

    s, e = start_s, end_s
    # A cut often lands in the dip before a low tone. Peek ahead, then
    # consume the whole voiced run so the tone is not left on the floor.
    i = frame_at(e)
    stop = frame_at(min(right_limit, e + limit))
    j = i
    if not voiced[i]:
        peek = frame_at(min(right_limit, e + 0.18))
        k = i
        while k < peek and not voiced[k]:
            k += 1
        if k < peek and voiced[k]:
            j = k
    if voiced[min(j, len(voiced) - 1)]:
        while j < stop and j + 1 < len(voiced) and voiced[j + 1]:
            j += 1
        e = min(right_limit, max(e, time_at(j + 1)))
    i = frame_at(s)
    if 0 <= i < len(voiced) and voiced[i]:
        j = i
        stop = frame_at(max(left_limit, s - limit))
        while j > stop and j - 1 >= 0 and voiced[j - 1]:
            j -= 1
        s = max(left_limit, time_at(j))
    if e <= s:
        return start_s, end_s
    return s, e


def unvoiced_split(voiced, overlap_s, overlap_e):
    """Cut overlapping clips on the nearest unvoiced frame, not mid-tone."""
    mid = (overlap_s + overlap_e) / 2
    if len(voiced) == 0 or overlap_e <= overlap_s:
        return mid
    sf = max(0, int(overlap_s * SR / HOP))
    ef = min(len(voiced) - 1, int(overlap_e * SR / HOP))
    best = None
    best_dist = 1e9
    for i in range(sf, ef + 1):
        if voiced[i]:
            continue
        t = i * HOP / SR
        dist = abs(t - mid)
        if dist < best_dist:
            best, best_dist = t, dist
    return mid if best is None else best
