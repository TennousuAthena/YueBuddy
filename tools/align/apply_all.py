"""Merge tools/align/out/*.clips.json into lesson JSON files (no ASR rerun)."""
import glob
import json
import os

REPO = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LESSONS = {
    "l1": "assets/lessons/lesson_1.json",
    "l2": "assets/lessons/lesson_2.json",
    "l3": "assets/lessons/lesson_3.json",
}

applied_total = 0
for clips_path in sorted(glob.glob(os.path.join(REPO, "tools/align/out/*.clips.json"))):
    data = json.load(open(clips_path, encoding="utf-8"))
    module_id = data["module"]
    lesson_id = module_id.split("-", 1)[0]
    lesson_path = os.path.join(REPO, LESSONS[lesson_id])
    lesson = json.load(open(lesson_path, encoding="utf-8"))
    module = next(m for m in lesson["modules"] if m["id"] == module_id)
    by_id = {c["id"]: c.get("clip") for c in data["clips"]}
    n = 0
    for item in module["items"]:
        clip = by_id.get(item["id"])
        if clip:
            item["clip"] = clip
            n += 1
        else:
            item.pop("clip", None)
    with open(lesson_path, "w", encoding="utf-8") as f:
        json.dump(lesson, f, ensure_ascii=False, indent=1)
        f.write("\n")
    applied_total += n
    print(f"{module_id}: applied {n}/{len(data['clips'])}")
print(f"TOTAL applied: {applied_total}")
