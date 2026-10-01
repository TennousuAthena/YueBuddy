"""Batch-align every module (medium model, independent matcher)."""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

jobs = []
for lesson in ["assets/lessons/lesson_1.json", "assets/lessons/lesson_2.json"]:
    d = json.load(open(os.path.join(REPO, lesson)))
    for m in d["modules"]:
        if m.get("recordings"):
            jobs.append((lesson, m["id"]))

print(f"[final] {len(jobs)} modules, model=medium", flush=True)
for lesson, mid in jobs:
    r = subprocess.run(
        [sys.executable, os.path.join(REPO, "tools/align/align_module.py"),
         "--lesson", lesson, "--module", mid, "--model", "medium",
         "--out-dir", "tools/align/out"],
        capture_output=True, text=True)
    out = r.stdout or ""
    lines = [line for line in out.splitlines()
             if "matched" in line or "LOW" in line]
    print(f"[final] {mid}:", flush=True)
    for line in lines:
        print(f"    {line.strip()[:100]}", flush=True)
    if r.returncode != 0:
        print(r.stderr[-800:], flush=True)
print("FINAL_DONE", flush=True)
