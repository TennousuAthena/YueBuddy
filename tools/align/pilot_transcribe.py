"""Pilot: transcribe one teacher recording with word timestamps.

Usage:
    python3 tools/align/pilot_transcribe.py \
        --audio assets/audio/l1/dialogue-1.m4a \
        --model small \
        --lang yue \
        --out tools/align/out/dialogue-1.words.json
"""
import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True)
    parser.add_argument("--model", default="small")
    # Note: faster-whisper `small` cannot transcribe Cantonese as `yue`
    # (returns nothing); use `zh`, which normalizes Written Cantonese
    # into standard written Chinese but keeps reliable word timings.
    parser.add_argument("--lang", default="zh")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    from faster_whisper import WhisperModel

    print(f"[pilot] loading model {args.model} ...", flush=True)
    model = WhisperModel(args.model, device="auto", compute_type="auto")
    print("[pilot] transcribing ...", flush=True)
    segments, info = model.transcribe(
        args.audio,
        language=args.lang,
        word_timestamps=True,
        vad_filter=True,
    )
    out_segments = []
    for seg in segments:
        words = []
        for w in seg.words or []:
            words.append({"w": w.word, "s": round(w.start, 2), "e": round(w.end, 2)})
        out_segments.append(
            {
                "s": round(seg.start, 2),
                "e": round(seg.end, 2),
                "text": seg.text,
                "words": words,
            }
        )
    payload = {
        "audio": args.audio,
        "model": args.model,
        "lang": args.lang,
        "detected": getattr(info, "language", None),
        "segments": out_segments,
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
    print(f"[pilot] wrote {args.out} ({len(out_segments)} segments)", flush=True)
    print("PILOT_DONE", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
