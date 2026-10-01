# 老师录音时间戳（自动对齐）

单句"原音"点读的时间戳由语音识别自动生成，无需手工打点。

## 原理

1. 用 `faster-whisper`（`medium` 模型，语言强制 `zh`，VAD 关闭）转写老师录音，
   输出字级时间戳。注意：`small` 模型用 `yue` 会输出空结果，
   必须用 `zh`（会把书面粤语规整成标准书面语，但时间戳可靠）。
2. 课文与 ASR 文本先过粤语别名折叠（`ALIASES`：唔該=麻煩、食=吃、
   喺=在……），再逐句在全录音上滑窗找最佳局部匹配（与顺序无关——
   老师并不总是按课文顺序读，如 `l2-eat` 先读時段最后读點餐）。
3. 匹配按分数从高到低认领时间片；与已认领重叠超一半的句子留空，
   宁可没有时间戳也不给错时间戳。
4. 多录音文件的模块（如 `l1-datetime`）会对每个文件分别对齐，
   每句取分数最高的那个文件（`clip.rec` 记录文件下标）。

## 用法

```bash
# 单个模块：生成 clips + 审听页（默认 small 模型，最快）
python3 tools/align/align_module.py \
  --lesson assets/lessons/lesson_1.json \
  --module l1-dialogue-1 \
  --out-dir tools/align/out

# 练习类模块建议用 medium（粤语误听明显更少），VAD 默认关闭
#（实测 Silero VAD 会吃掉偏轻的老师语音导致漏句）
python3 tools/align/align_module.py \
  --lesson assets/lessons/lesson_1.json \
  --module l1-daily --model medium \
  --out-dir tools/align/out

# 确认审听页无误后，写回 lesson JSON（单个模块）
python3 tools/align/align_module.py \
  --lesson assets/lessons/lesson_1.json \
  --module l1-dialogue-1 --apply

# 或一键合并所有已生成的 clips（不重跑转写）
python3 tools/align/apply_all.py
```

## 边界精修（能量 VAD）

字级时间戳前后加固定留白会切半句，所以多一步精修：

```bash
# 单个模块
python3 tools/align/refine_clips.py \
  --lesson assets/lessons/lesson_1.json \
  --module l1-daily --out-dir tools/align/out

# 全部模块
python3 tools/align/batch_refine.py
```

做法：`ffmpeg` 解成 16k 单声道，按 20ms 帧算 RMS 能量，
阈值取 `max(噪声×3, 峰值×1.5%)`；凡是碰到原时间片的语音岛都保留
（只修边、不掐中间），边界外扩找语音、内收去静音，
最多挪动 ±1s，最后卡零交叉点避免爆音。
非法跨度（翻转/过短）直接丢弃、该句回退 TTS。
精修完记得重跑 `apply_all.py` 写回 lesson JSON。

## 审听（必须）

每个模块会生成 `tools/align/out/<module>.review.html`，
每行可直接试听该句切片。重点检查：

- `score < 0.5` 的行（脚本会标黄并在控制台提示 `LOW`）；
- 首尾句（容易吞前 100ms 或拖尾）；
- 对话模块里说话人是否对得上。

审听发现偏移可直接改 JSON 里的 `startMs`/`endMs`（毫秒）。

## 数据格式

时间戳以内联 `clip` 存放在 lesson JSON 的 item 上：

```json
{"id": "l1-dg1-01", "cantonese": "早晨！", "clip": {"startMs": 310, "endMs": 4140}}
{"id": "x", "clip": {"rec": 1, "startMs": 100, "endMs": 900}}
```

- 单录音模块省略 `rec`（默认为 0）；
- 无 `clip` 的句子：卡片上"原音"按钮置灰，仅 TTS 可用；
- `clip` 非法（`endMs <= startMs`、越界）会被 `teacherAudioFor` 忽略。

## 字级时间戳（卡拉 OK 跟播）

对话"跟播整段"需要每句每个字的起唱时间，由 `extract_words.py` 生成。
它**不重跑对齐**，而是复用已入库的 clip 边界去切字级时间：

```bash
# 单个模块（只生成，不断库）
python3 tools/align/extract_words.py \
  --lesson assets/lessons/lesson_1.json --module l1-dialogue-1

# 全部模块 + 写回 lesson JSON
python3 tools/align/extract_words.py --all --apply
```

做法：每个录音转写一次（`medium`，`zh`，`word_timestamps=True`），
取落在 `[startMs, endMs]` 内的 ASR 字，用课文做 `SequenceMatcher`
映射到每个字；匹配不上的字按邻居线性插值。

两个质量 guard（实测发现的问题）：

- whisper 对中文音频里的英文词（如 `hello`）偶发错乱/倒置的词级
  时间戳——`end <= start` 的词直接丢弃，该字退化为插值；
- VAD 精修可能切掉轻声起音——字时间钳制进 clip 边界内，
  卡拉 OK 只在真实播放区间内变色。

入库格式（`t` 是去标点小写后的课文，`w` 是 `[起,止,…]` 毫秒，
与 `t` 的字符一一对应，录音绝对时间）：

```json
{"clip": {"startMs": 699, "endMs": 4170,
  "words": {"t": "hello我係陳小明", "w": [699, 699, 699, 928, ...]}}}
```

- App 端用同样的 `norm` 比对（见 `karaoke.dart`），对不上就回退
  到句级高亮，不会崩；
- 重跑 `align_module.py --apply` 时 span 没变的句子会自动保留旧
  `words`，只有边界动了才需要重跑本脚本。

## 依赖

- `ffmpeg` / `ffprobe`；
- Python 包见 `requirements.txt`（`faster-whisper`、`numpy`）。建议装进单独的虚拟环境：

```bash
python3 -m venv ~/.venv
source ~/.venv/bin/activate
pip install -r tools/align/requirements.txt
```

- 首次转写会自动下载模型（约几百 MB，需要外网）。

精度不够时可把 `--model` 换成 `medium` 重跑，流程不变。
