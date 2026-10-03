"""Refine every module's clips JSON in tools/align/out/."""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

lessons = {}
for name in ("lesson_1.json", "lesson_2.json", "lesson_3.json"):
    key = name.removeprefix("lesson_").removesuffix(".json")
    key = f"l{key}"
    d = json.load(open(os.path.join(REPO, "assets/lessons", name)))
    lessons[key] = [m["id"] for m in d["modules"] if m.get("recordings")]

for key, modules in lessons.items():
    for mid in modules:
        r = subprocess.run(
            [sys.executable, os.path.join(REPO, "tools/align/refine_clips.py"),
             "--lesson", f"assets/lessons/lesson_{key[1]}.json",
             "--module", mid, "--out-dir", "tools/align/out"],
            capture_output=True, text=True)
        out = r.stdout or ""
        first = next((l for l in out.splitlines() if "adjusted" in l), "?")
        print(f"[batch-refine] {mid}: {first.strip()}", flush=True)
        if r.returncode != 0:
            print(r.stderr[-600:], flush=True)
print("REFINE_ALL_DONE", flush=True)
