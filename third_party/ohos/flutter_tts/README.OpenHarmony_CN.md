<p align="center">
  <h1 align="center"> <code>flutter_tts</code> </h1>
</p>

本项目基于 [flutter_tts: 4.2.3](https://pub.dev/packages/flutter_tts/versions/4.2.3) 开发。

## 1. 安装与使用

### 1.1 安装方式

进入到工程目录并在 pubspec.yaml 中添加以下依赖：

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  flutter_tts:
    git:
      url: "https://gitcode.com/CPF-Flutter/fluttertpc_flutter_tts"
      # ref: 请根据下方TAG版本对应表选择TAG
      ref: 4.2.3-ohos-1.0.0  
```

执行命令

```bash
flutter pub get
```

<!-- tabs:end -->

> TAG 命名规则：`4.2.3-ohos-1.0.0-beta.1`，不同 TAG 之间的变更详见 CHANGELOG.OpenHarmony.md。

#### TAG 版本对应表

| Flutter 框架版本 | TAG 名称 | 分支名 |
| --- | --- | --- |
| 3.22 | 4.2.3-ohos-1.0.0 | br_3.27 |
| 3.27 | 4.2.3-ohos-1.0.0 | br_3.27 |
| 3.35 | 4.2.3-ohos-1.0.0 | br_3.27 |

### 1.2 使用案例

使用案例详见 [example](./example/lib/main.dart)

完整使用示例：

```dart
import 'package:flutter_tts/flutter_tts.dart';

FlutterTts flutterTts = FlutterTts();

// 设置语言
await flutterTts.setLanguage("zh-CN");

// 播放语音
await flutterTts.speak("Hello World");
```

## 2. 约束与限制

### 2.1 兼容性

在以下版本中已测试通过

1. Flutter: 3.22.0-ohos-1.0.4; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.1.840; ROM: +6.0.0.106 SP3;
2. Flutter: 3.27.5-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 5.1.0.130 SP8;
3. Flutter: 3.35.7-ohos-0.0.1; SDK: 6.0.1(21); IDE: DevEco Studio: 6.0.1.260; ROM: 6.0.0.120 SP6;

### 2.2 权限要求

#### 2.2.1 在 entry 目录下的 module.json5 中添加权限

打开 `entry/src/main/module.json5`，添加：

```yaml
"requestPermissions":
  [
    {
      "name": "ohos.permission.INTERNET",
      "reason": "$string:network_reason",
      "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" },
    },
  ]
```

### 2.3 环境配置

#### 2.3.1 安装 DevEco Studio

从 [HarmonyOS 开发者官网](https://developer.harmonyos.com/) 下载并安装 DevEco Studio。请选择与目标 SDK 版本匹配的 IDE 版本（详见上方兼容性表格）。

#### 2.3.2 配置 SDK 版本

1. 打开 DevEco Studio，进入 **文件 > 设置 > SDK**（Windows）或 **DevEco Studio > 偏好设置 > SDK**（macOS）。
2. 安装与 Flutter 版本匹配的 OpenHarmony SDK（例如 Flutter 3.22/3.27 对应 SDK 5.0.0(12)，Flutter 3.35 对应 SDK 6.0.1(21)）。
3. 确保 SDK 路径已正确配置到系统环境变量中。

#### 2.3.3 编译构建步骤

1. 在 DevEco Studio 中打开项目，或使用命令行：

```bash
cd example/ohos
hvigorw assembleHap
```

2. 运行到设备或模拟器：

```bash
flutter run
```

3. 确保设备已连接并被识别：

```bash
hdc list targets
```

## 3. API

> [!TIP] "ohos Support"列为 yes 表示 ohos 平台支持该属性；no 则表示不支持；partially 表示部分支持。使用方法跨平台一致，效果对标 iOS 或 Android 的效果。

### 3.1 关键行为差异说明

以下行为在 Dart API 与底层 OHOS 实现之间存在差异，OHOS 平台开发时请注意：

| API | Dart 行为 | OHOS 行为 | 说明 |
| --- | --- | --- | --- |
| `setQueueMode` | `0` = QUEUE_FLUSH（清空队列），`1` = QUEUE_ADD（追加） | `0` = 排队（追加），`1` = 抢占（清空队列） | 语义反转：Dart 的 `0` 对应 OHOS 的 `1`，Dart 的 `1` 对应 OHOS 的 `0` |
| `setSpeechRate` | 范围 `0.0` ~ `1.0` | 范围 `0.0` ~ `1.0` | 内部映射为 OHOS 的 `0` ~ `100` |
| `setVolume` | 范围 `0.0` ~ `1.0` | 范围 `0.0` ~ `1.0` | 内部映射为 OHOS 的 `0` ~ `100` |
| `pause` | 暂停播放 | 原生不支持 | 通过 `stop()` 模拟；会触发 `setPauseHandler` 回调 |
| `setVoice` | Android: "name"+"locale" 键 | OHOS: "person" 键必需 | OHOS 使用 person 标识符(0/13/21/8)而非 name/locale 键值对 |

| 接口名                            | 描述                                                                           | 类型     | 输入                                              | 输出 | 鸿蒙支持 |
| ------------------------------- | ------------------------------------------------------------------------------ | -------- | ------------------------------------------------ | ------ | ------------ |
| speak                           | 指定文本转为语音并播放。                                                       | function | {String text , bool? focus}                      | Future | yes          |
| pause                           | 暂停当前语音（OHOS通过stop()模拟，会触发pauseHandler回调）                     | function | /                                                | Future | yes          |
| stop                            | 停止播放并清空队列                                                             | function | /                                                | Future | yes          |
| awaitSpeakCompletion            | 设置是否等待语音播报完成后返回结果                                             | function | {bool awaitCompletion}                           | Future | yes          |
| awaitSynthCompletion            | 设置是否等待合成完成后返回结果                                                 | function | {bool awaitCompletion}                           | Future | yes          |
| synthesizeToFile                | 将指定文本合成为音频文件并保存到本地                                           | function | {String text, String fileName, bool? isFullPath} | Future | yes          |
| setEngine                       | 切换系统已安装的 TTS 引擎                                                      | function | {String engine}                                  | Future | no           |
| setQueueMode                    | 控制新语音任务加入时队列处理策略                                               | function | {int queueMode}                                  | Future | yes          |
| setSilence                      | 在语音播放前插入指定毫秒数的静默期                                  | function | {int timems}                                     | Future | yes          |
| setAudioAttributesForNavigation | 配置音频流类型为导航场景，提高导航语音的播放优先级                             | function | /                                                | /      | yes          |
| setSpeechRate                   | 调整语音播放的速度（快慢）                                                     | function | {double rate}                                    | Future | yes          |
| setVolume                       | 调整语音播放的音量大小                                                         | function | {double volume}                                  | Future | yes          |
| setPitch                        | 调整语音的音调高低（如儿童音、成人音）                                         | function | {double pitch}                                   | Future | yes          |
| setLanguage                     | 切换语音合成的语言（如中文、英文）                                             | function | {String language}                                | Future | yes          |
| setVoice                        | 选择特定的语音包（如”中文女声””英文男声”）进行语音合成                         | function | {Map< String, String > voice}                    | Future | yes          |
| clearVoice                      | 重置为默认语音                                                                 | function | /                                                | Future | yes          |
| getMaxSpeechInputLength         | 查询当前 TTS 引擎支持的最大文本输入长度（单次 speak 方法可传入的 text 最大长度）| function | /                                                | Future | yes          |
| getLanguages                    | 获取所有可用语言列表                                                           | function | /                                                | Future | yes          |
| getVoices                       | 获取所有可用语音列表                                                           | function | /                                                | Future | yes          |
| getDefaultVoice                 | 获取默认语音                                                                   | function | /                                                | Future | yes          |
| getEngines                      | 获取系统中所有已安装的 TTS 引擎列表                                            | function | /                                                | Future | no           |
| getDefaultEngine                | 获取系统当前默认的 TTS 引擎包名                                                | function | /                                                | Future | no           |
| isLanguageAvailable             | 检查指定语言的语音合成是否可用                                                 | function | {String language}                                | Future | yes          |
| isLanguageInstalled             | 检查指定语言的语音包是否已安装。                                               | function | {String language}                                | Future | yes          |
| areLanguagesInstalled           | 批量检查多个语言包是否已安装，返回各语言的安装状态                             | function | {List<String> language}                          | Future | yes          |
| getSpeechRateValidRange         | 查询当前 TTS 引擎支持的语速最小值、默认值和最大值                              | function | /                                                | /      | yes          |
| setStartHandler                 | 设置语音开始播放时的回调函数（触发时机：TTS 开始播放语音时）                   | function | {VoidCallback handler}                           | /      | yes          |
| setCompletionHandler            | 设置语音播放完成时的回调函数（触发时机：当前语音播放结束或合成队列清空时）     | function | {VoidCallback handler}                           | /      | yes          |
| setContinueHandler              | 设置语音继续播放时的回调函数                                                   | function | {VoidCallback handler}                           | /      | yes          |
| setPauseHandler                 | 设置语音暂停时的回调函数                                                       | function | {VoidCallback handler}                           | /      | yes          |
| setCancelHandler                | 设置语音取消时的回调函数                                                       | function | {VoidCallback handler}                           | /      | yes          |
| setErrorHandler                 | 设置合成或播放出错时的回调函数（如不支持的语言、引擎异常等错误）               | function | {ErrorHandler handler}                           | /      | yes          |
| setProgressHandler              | 实时返回当前播放的文本位置信息（当前文本、起始索引、结束索引及当前单词）       | function | {ProgressHandler handler}                        | /      | no           |
| downloadVoice                   | 下载离线语音音色文件到本地（OHOS 专属）                                        | function | {String language, int person, String style}      | Future<DownloadVoiceController> | yes          |
| downloadVoiceEvents            | 提供下载过程的实时事件流监听                                                   | Stream   | /                                                | Stream<DownloadVoiceEvent> | yes          |
| disposeVoice                   | 清理所有下载相关的资源、控制器和事件流                                         | function | /                                                | /      | yes          |

## 4. 遗留问题

## 5. 补充说明

### SpeechRateValidRange

| Property | Type   | Description                          |
|----------|--------|--------------------------------------|
| min      | double | 最小语速 (0.0)                       |
| normal   | double | 正常语速 (0.5)                       |
| high     | double | 高语速 (0.7)，仅 OHOS 支持           |
| max      | double | 最大语速 (1.0)                       |
| platform | TextToSpeechPlatform | 平台标识 (android/ios/ohos)           |

### OhosVoiceInfo

| Property    | Type   | Description                              |
|-------------|--------|------------------------------------------|
| language    | String | 语音语言 (例如 "zh-CN")                  |
| person      | int    | 语音人标识                               |
| style       | String | 语音风格                                 |
| name        | String | 语音名称 (根据 person 自动生成)          |
| gender      | String | 语音性别                                 |
| description | String | 语音描述                                 |
| status      | String | 语音状态 (GA/INSTALLED/EOM)              |
| fromJson    | static | 从 JSON Map 创建 OhosVoiceInfo 实例       |
| toJson      | method | 将实例序列化为 JSON Map                   |

### DownloadVoiceController

| Property    | Type                  | Description                          |
|-------------|-----------------------|--------------------------------------|
| downloadId  | String                | 唯一下载标识符                       |
| status      | DownloadStatus        | 当前下载状态                         |
| statusStream| Stream<DownloadStatus>| 状态变更流                           |

#### 方法说明

| 方法     | 说明                                       | 返回类型 |
|----------|--------------------------------------------|----------|
| cancel() | 取消正在进行的语音下载任务                 | Future<void> |
| dispose()| 释放控制器持有的所有资源                   | void     |

### DownloadVoiceEvent

| Property  | Type              | Description                          |
|-----------|-------------------|--------------------------------------|
| type      | DownloadEventType | 事件类型 (start/progress/complete/cancel/error) |
| downloadId| String            | 关联的下载标识符                     |
| info      | String?           | 额外的事件信息                       |
| voiceInfo | OhosVoiceInfo?    | 完成时的语音信息                     |
| errorCode | int?              | 错误时的错误码                       |

### Enums

| Enum                  | Values                                      |
|-----------------------|---------------------------------------------|
| TextToSpeechPlatform    | android, ios, ohos                        |
| DownloadStatus          | pending, downloading, completed, cancelled, error |
| DownloadEventType       | start, progress, complete, cancel, error  |

> 切换音色: 中文: 聆小珊女性音色, 凌飞哲男性音色 英文: 美国英语劳拉女性音色. 中文音色支持直接播放中英文内容. 英文音色仅支持英文内容.

> 切换语言: 仅支持中英文内容. 系统内置功能，无需额外操作.

> 下载音色: 适用于 OHOS 19 及更高版本。

## 6. 开源协议

本项目基于 [MIT](LICENSE)，请自由地享受和参与开源。
