# 粤语伴 YueBuddy

把广东话兴趣班讲义做成可以随身打开的练习册：看繁体和粤拼、听老师原音、跟读合成语音，并把已经会的句子记在本机。

当前版本 **0.1.0**。用 Flutter 编写，目标平台是 iOS、Android、macOS、Windows 和 Web。

## 现在能做什么

- 第一次打开时写下名字，用字库读出粤拼。
- 首页列出六课。前三课「互相認識」「民以食為天」「溝通交流」可以学，后三课只占位。
- 词句卡同时给出繁体、标准粤拼和普通话。设置里可以关掉拼音、把拼音放在整句下面，或标在每个词的上方，也可以藏起普通话。
- 课文里出现的词会链到词表，句子中用虚线下划线标出，点开看普通话解释。香港说法和口语变体收在 `assets/glossary/entries.json`。带 `image` 的词条会在卡片上放图。
- 讲义里的空（日期、数字等）可以当场填上，再按填好的句子朗读。
- 每个模块可以整段播放老师录音。单句有时间戳时可以听原音切片；没有切片时只用合成语音。
- 对话可以按字级时间跟播，当前字会跟着高亮。
- 点过「已会」的句子记在本机，下次打开还在。
- 手机用底部导航，平板和桌面用侧栏。

「智能练习」还是占位页，之后才会接上课文范围的对话练习。

## 环境

- Flutter stable，Dart SDK `^3.9.0`（见 `pubspec.yaml`）
- Git LFS。讲义录音（`.m4a`）、讲义 PDF 和 `assets/illustrations/` 里的插图存在 LFS 里。克隆后执行 `git lfs install && git lfs pull`，否则这些文件只是指针，打包出来没有声音和图。
- 本机如果把 Flutter 放在 `~/sdk/flutter`，先把它加进 `PATH`：

```bash
export PATH="$HOME/sdk/flutter/bin:$PATH"
```

## 运行

```bash
flutter pub get
flutter test
flutter run -d macos
```

其他目标：

```bash
flutter run -d chrome
flutter run -d windows
```

要换成后端语音时，加上本地配置（两种二选一，可以叠加）：

```bash
# 推荐：自有语音后端（Worker + R2 缓存），Web 也能用
cp config/tts.example.json config/tts.local.json
# 把 TTS_BASE_URL 换成 wrangler deploy 后的地址
flutter run -d macos --dart-define-from-file=config/tts.local.json
```

```bash
# 备选：MiniMax 直连（仅调试，且不是 Web）
flutter run -d macos --dart-define-from-file=config/minimax.local.json
```

没有粤语语音时，请在系统里下载「中文（香港）」：

- iOS：设置 → 辅助功能 → 朗读内容 → 声音 → 中文
- macOS：系统设置 → 辅助功能 → 朗读内容 → 系统声音
- Android：设置 → 系统 → 语言和输入法 → 文字转语音输出
- Windows：设置 → 时间和语言 → 语音
- Web：使用浏览器或系统里已经安装的粤语语音

没有粤语引擎时会提示，不会改用普通话朗读。

## 发音

单句合成的顺序：

1. **自有语音后端**（配置了 `TTS_BASE_URL` 时，含 Web）。App 把课文汉字 `POST` 给自己的 Cloudflare Worker，Worker 查 R2 缓存，miss 才回源 MiniMax `POST /v1/t2a_v2` 并写回 R2。对话整段播放会用 `POST /v1/tts/batch` 一次预取。语速只分 `slow/normal/fast` 三档（对应 MiniMax `0.5/0.7/1.0`），App 的语速滑杆会量化到最近一档，保证缓存命中。实现见 [workers/tts/](workers/tts/)，缓存键契约见 [workers/tts/CONTRACT.md](workers/tts/CONTRACT.md)。密钥只放在 `wrangler secret` 里，不进 App 包。
2. **MiniMax 直连**（仅调试，且不是 Web）。只把课文汉字送给同步接口 `POST /v1/t2a_v2`，不传粤拼。设置里的「正常」语速按 `0.7` 送给 MiniMax（接口默认 `1.0` 偏快）。对话里 Mary 用 `Cantonese_ProfessionalHost（F)`（左括号是全角），Peter 用 `Cantonese_Articulate_commentator_vv2`，侍應用 `Chinese (Mandarin)_HK_Flight_Attendant`。词句卡和其他句子用默认音色 `Cantonese_GentleLady`。
3. 上面都失败，或都没配置时，退回设备 `zh-HK`。
4. Web 不直连 MiniMax（浏览器跨域），有后端时走后端，否则用设备语音。

本地配置已经写进 `.gitignore`，不要提交密钥或内网地址：

```bash
cp config/tts.example.json config/tts.local.json
cp config/minimax.example.json config/minimax.local.json
# 可合并成一个 json 传给 --dart-define-from-file
flutter run -d macos --dart-define-from-file=config/tts.local.json
```

改密钥或音色后需要重新运行，热重载不会带上新的 `--dart-define`。国内接口默认 `https://api.minimaxi.com`，`language_boost` 为 `Chinese,Yue`。国际站把 `MINIMAX_BASE_URL` 改成 `https://api.minimax.io`（后端侧在 `workers/tts/wrangler.toml` 的 `[vars]` 里改）。

现在的直连只为调试方便，密钥会编进 debug 包。上线用语音后端：由后端保存密钥（`wrangler secret put MINIMAX_API_KEY`），App 只存 `TTS_BASE_URL`。改动点在 `lib/core/audio/backend_tts_client.dart` 和 `lib/main.dart` 里的 `TtsBackendConfig.fromEnvironment()`。

## 目录

```
lib/
  app/                 应用壳、导航、依赖注入
  core/audio/          设备 TTS、MiniMax、原音播放
  core/layout/         手机 / 平板 / 桌面断点
  features/onboarding/ 名字与粤拼
  features/home/       课表
  features/lessons/    课文、进度、填空、跟播
  features/glossary/   词表
  features/practice/   智能练习（占位）
  features/settings/   语速和显示开关
  theme/               颜色和动效
assets/
  lessons/             catalog.json 与各课 JSON
  glossary/            词表
  jyutping/            名字用字库
  audio/               老师录音（打进包）
  original_lesson/     讲义 PDF 和原始录音，只作对照，不打进包
tools/align/           把老师录音对齐到单句时间戳
workers/tts/           语音后端（Worker + R2 缓存，MiniMax 回源）
config/                MiniMax / TTS 后端示例配置
test/                  单元测试和 widget 测试
```

`assets/lessons/catalog.json` 里写了 `asset` 的课才会打开。课文 JSON 的模块用 `kind` 区分练习（`practice`）和对话（`dialogue`）。单句上的 `clip` 记录原音起止（毫秒），可选的 `words` 供跟播高亮。

## 老师录音对齐

单句原音的时间戳由 `tools/align/` 里的脚本生成，不需要手工打点。流程、审听页和写回格式见 [tools/align/README.md](tools/align/README.md)。

`tools/align/out/` 是中间结果，已忽略，不入库。确认过的时间戳写在各课 JSON 里。

## 测试

```bash
flutter test
```

覆盖课文加载、词表、填空、卡拉 OK 高亮、原音切片、语速设置、学习进度、名字粤拼和窄屏布局。

## 不会入库

- `config/minimax.local.json`：本地 MiniMax 密钥
- `config/tts.local.json`：本地语音后端地址
- `build/`、`.dart_tool/`、各平台的 `Pods/` 与 `ephemeral/`：构建产物
- `tools/align/out/`：对齐脚本的审听页和中间 JSON
- Android 签名（`key.properties`、`*.jks`、`*.keystore`）
