<p align="center">
  <h1 align="center"> <code>flutter_tts</code> </h1>
</p>

This project is developed based on [flutter_tts: 4.2.3](https://pub.dev/packages/flutter_tts/versions/4.2.3).

## 1. Installation and Usage

### 1.1 Installation Method

Navigate to the project directory and add the following dependency to `pubspec.yaml`:

<!-- tabs:start -->

#### pubspec.yaml

```yaml
dependencies:
  flutter_tts:
    git:
      url: "https://gitcode.com/CPF-Flutter/fluttertpc_flutter_tts"
      # ref: Please select the TAG to the TAG Version Mapping
      ref: 4.2.3-ohos-1.0.0  
```

Run the command

```bash
flutter pub get
```

<!-- tabs:end -->

> TAG naming rule: `4.2.3-ohos-1.0.0-beta.2`. See CHANGELOG.OpenHarmony.md for details.

#### TAG Version Table

| Flutter Version | TAG | Branch | SDK Version |
| --- | --- | --- | --- | --- | --- |
| 3.22 | 4.2.3-ohos-1.0.0 | br_3.27 |
| 3.27 | 4.2.3-ohos-1.0.0 | br_3.27 |
| 3.35 | 4.2.3-ohos-1.0.0 | br_3.27 |

### 1.2 Usage Examples

For usage examples, see [example](./example/lib/main.dart)

Complete usage example:

```dart
import 'package:flutter_tts/flutter_tts.dart';

FlutterTts flutterTts = FlutterTts();

// Set language
await flutterTts.setLanguage("zh-CN");

// Play speech
await flutterTts.speak("Hello World");
```

## 2. Constraints and Limitations

### 2.1 Compatibility

Tested and passed in the following versions:

1. Flutter: 3.22.0-ohos-1.0.4; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.1.840; ROM: +6.0.0.106 SP3;
2. Flutter: 3.27.5-ohos-0.0.1; SDK: 5.0.0(12); IDE: DevEco Studio: 5.1.0.828; ROM: 5.1.0.130 SP8;
3. Flutter: 3.35.7-ohos-0.0.1; SDK: 6.0.1(21); IDE: DevEco Studio: 6.0.1.260; ROM: 6.0.0.120 SP6;

### 2.2 Permission Requirements

#### 2.2.1 Add permissions in `module.json5` under the `entry` directory

Open `entry/src/main/module.json5` and add:

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

### 2.3 Environment Configuration

#### 2.3.1 Install DevEco Studio

Download and install DevEco Studio from the [HarmonyOS Developer Website](https://developer.harmonyos.com/). Select the version that matches your target SDK (see compatibility table above).

#### 2.3.2 Configure SDK Version

1. Open DevEco Studio and go to **File > Settings > SDK** (Windows) or **DevEco Studio > Preferences > SDK** (macOS).
2. Install the OpenHarmony SDK version that matches your Flutter version (e.g., SDK 5.0.0(12) for Flutter 3.22/3.27, SDK 6.0.1(21) for Flutter 3.35).
3. Ensure the SDK path is correctly set in your system environment variables.

#### 2.3.3 Build Steps

1. Open the project in DevEco Studio or use the command line:

```bash
cd example/ohos
hvigorw assembleHap
```

2. To run on a device or emulator:

```bash
flutter run
```

3. Ensure your device is connected and recognized:

```bash
hdc list targets
```

## 3. API

> [!TIP] The "ohos Support" column with "yes" indicates that the attribute is supported on the ohos platform; "no" indicates no support; "partially" indicates partial support. The usage method is consistent across platforms, and the effect is comparable to that on iOS or Android.

### 3.1 Key Behavioral Differences

The following behaviors differ between the Dart API and the underlying OHOS implementation. Please take these into account when developing for the OHOS platform:

| API | Dart Behavior | OHOS Behavior | Notes |
| --- | --- | --- | --- |
| `setQueueMode` | `0` = QUEUE_FLUSH (clear queue), `1` = QUEUE_ADD (append) | `0` = queue (append), `1` = preempt (clear queue) | Semantic reversal: Dart `0` corresponds to OHOS `1`, and Dart `1` corresponds to OHOS `0` |
| `setSpeechRate` | Range `0.0` ~ `1.0` | Range `0.0` ~ `1.0` | Internally mapped to OHOS `0` ~ `100` |
| `setVolume` | Range `0.0` ~ `1.0` | Range `0.0` ~ `1.0` | Internally mapped to OHOS `0` ~ `100` |
| `pause` | Pauses playback | Not supported natively | Simulated via `stop()`; triggers `setPauseHandler` callback |
| `setVoice` | Android: "name"+"locale" keys | OHOS: "person" key required | OHOS uses person identifier (0/13/21/8) instead of name/locale pair |

| Name                            | Description                                                                                                                                                | Type     | Input                                            | Output | ohos Support |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------ | ------ | ------------ |
| speak                           | Converts the specified text to speech and plays it.                                                                                                        | function | {String text , bool? focus}                    | Future | yes          |
| pause                           | Pauses the current speech (OHOS simulates via stop(); triggers pauseHandler callback).                                                                      | function | /                                                | Future | yes          |
| stop                            | Stops playback and clears the queue.                                                                                                                       | function | /                                                | Future | yes          |
| synthesizeToFile                | Synthesizes the specified text into an audio file and saves it locally.                                                                                    | function | {String text, String fileName, bool? isFullPath} | Future | yes          |
| setEngine                       | Switches the installed TTS engine in the system.                                                                                                           | function | {String engine}                                  | Future | no           |
| setQueueMode                    | Controls the queue processing strategy when a new speech task is added.                                                                                    | function | {int queueMode}                                  | Future | yes          |
| setSilence                      | Inserts a silence period of the specified milliseconds before speech playback.                                                                             | function | {int timems}                                     | Future | yes          |
| setAudioAttributesForNavigation | Configures the audio stream type for navigation scenarios to increase the playback priority of navigation speech.                                          | function | /                                                | /      | yes          |
| setSpeechRate                   | Adjusts the speech playback speed (faster or slower).                                                                                                      | function | {double rate}                                    | Future | yes          |
| setVolume                       | Adjusts the speech playback volume.                                                                                                                        | function | {double volume}                                  | Future | yes          |
| setPitch                        | Adjusts the speech pitch (e.g., child voice, adult voice).                                                                                                 | function | {double pitch}                                   | Future | yes          |
| setLanguage                     | Switches the language for speech synthesis (e.g., Chinese, English).                                                                                       | function | {String language}                                | Future | yes          |
| setVoice                        | Selects a specific voice package (e.g., "Chinese female voice", "English male voice") for speech synthesis.                                                | function | {Map< String, String > voice}                    | Future | yes          |
| getMaxSpeechInputLength         | Queries the maximum text input length supported by the current TTS engine (the maximum length of text that can be passed to the speak method at one time). | function | /                                                | Future | yes          |
| getEngines                      | Gets the list of all installed TTS engines in the system.                                                                                                  | function | /                                                | Future | no           |
| getDefaultEngine                | Gets the package name of the current default TTS engine in the system.                                                                                     | function | /                                                | Future | no           |
| isLanguageInstalled             | Checks whether the voice package for the specified language is installed.                                                                                  | function | {String language}                                | Future | yes          |
| areLanguagesInstalled           | Batch checks whether multiple language packages are installed and returns the installation status of each language.                                        | function | {List<String> language}                          | Future | yes          |
| getSpeechRateValidRange         | Queries the minimum, default, and maximum speech rates supported by the current TTS engine.                                                                | function | /                                                | Future | yes          |
| awaitSpeakCompletion            | Sets whether to wait for speak completion before returning.                                                                                                | function | {bool awaitCompletion}                             | Future | yes          |
| awaitSynthCompletion            | Sets whether to wait for synthesizeToFile completion before returning.                                                                                     | function | {bool awaitCompletion}                             | Future | yes          |
| clearVoice                      | Resets the voice to the default voice.                                                                                                                     | function | /                                                | Future | yes          |
| getLanguages                    | Gets the list of available languages.                                                                                                                      | function | /                                                | Future | yes          |
| getVoices                       | Gets the list of available voices.                                                                                                                        | function | /                                                | Future | yes          |
| getDefaultVoice                 | Gets the default voice information.                                                                                                                        | function | /                                                | Future | yes          |
| isLanguageAvailable             | Checks whether the specified language is available.                                                                                                        | function | {String language}                                | /      | yes          |
| setStartHandler                 | Sets the callback function when speech starts playing (triggered when TTS starts playing speech).                                                          | function | {VoidCallback handler}                           | /      | yes          |
| setCompletionHandler            | Sets the callback function when speech playback is completed (triggered when the current speech playback ends or the synthesis queue is cleared).          | function | {VoidCallback handler}                           | /      | yes          |
| setErrorHandler                 | Sets the callback function when an error occurs during synthesis or playback (e.g., unsupported language, engine exception, etc.).                         | function | {ErrorHandler handler}                           | /      | yes          |
| setProgressHandler              | Returns real-time position information of the currently playing text (current text, start index, end index, and current word).                             | function | {ProgressHandler handler}                        | /      | no           |
| setContinueHandler              | Sets the callback function when speech continues playing.                                                                                                  | function | {VoidCallback handler}                           | /      | yes          |
| setPauseHandler                 | Sets the callback function when speech is paused.                                                                                                           | function | {VoidCallback handler}                           | /      | yes          |
| setCancelHandler                | Sets the callback function when speech is cancelled.                                                                                                       | function | {VoidCallback handler}                           | /      | yes          |
| downloadVoice                   | Downloads offline voice files to the local device (exclusive to OHOS).                                                                                     | function | {String language, int person, String style}      | Future<DownloadVoiceController> | yes          |
| downloadVoiceEvents             | Provides real-time event stream during the download process.                                                                                               | Stream   | /                                                | Stream<DownloadVoiceEvent> | yes          |
| disposeVoice                    | Clears all download-related resources, controllers, and event streams.                                                                                     | function | /                                                | /      | yes          |

## 4. Outstanding Issues

## 5. OHOS Exclusive Types

### SpeechRateValidRange

| Property | Type   | Description                          |
|----------|--------|--------------------------------------|
| min      | double | Minimum speech rate (0.0)            |
| normal   | double | Normal speech rate (0.5)             |
| high     | double | High speech rate (0.7), OHOS only    |
| max      | double | Maximum speech rate (1.0)            |
| platform | TextToSpeechPlatform | Platform identifier (android/ios/ohos) |

### OhosVoiceInfo

| Property    | Type   | Description                              |
|-------------|--------|------------------------------------------|
| language    | String | Voice language (e.g., "zh-CN")         |
| person      | int    | Voice person identifier                  |
| style       | String | Voice style                              |
| name        | String | Voice name (auto-generated from person)  |
| gender      | String | Voice gender                             |
| description | String | Voice description                        |
| status      | String | Voice status (GA/INSTALLED/EOM)        |
| fromJson    | static | Creates an OhosVoiceInfo from a JSON Map |
| toJson      | method | Serializes the instance to a JSON Map     |

### DownloadVoiceController

| Property    | Type                  | Description                          |
|-------------|-----------------------|--------------------------------------|
| downloadId  | String                | Unique download identifier           |
| status      | DownloadStatus        | Current download status              |
| statusStream| Stream<DownloadStatus>| Status change stream                 |

#### Methods

| Method   | Description                              | Return Type |
|----------|------------------------------------------|-------------|
| cancel() | Cancels the ongoing voice download task  | Future<void> |
| dispose()| Releases all resources held by the controller | void    |

### DownloadVoiceEvent

| Property  | Type              | Description                          |
|-----------|-------------------|--------------------------------------|
| type      | DownloadEventType | Event type (start/progress/complete/cancel/error) |
| downloadId| String            | Associated download identifier       |
| info      | String?           | Additional event info                |
| voiceInfo | OhosVoiceInfo?    | Voice info on complete               |
| errorCode | int?              | Error code on error                  |

### Enums

| Enum                  | Values                                      |
|-----------------------|---------------------------------------------|
| TextToSpeechPlatform    | android, ios, ohos                        |
| DownloadStatus          | pending, downloading, completed, cancelled, error |
| DownloadEventType       | start, progress, complete, cancel, error  |

## 6. Others

> Switching voice: Chinese: Ling Xiaoshan (female voice), Ling Feizhe (male voice); English: Laura (female voice, American English). Chinese voices can directly play both Chinese and English content. English voices only support playing English content.

> Switching language: Only Chinese and English content are supported. It is directly built into the system, no additional operations are required.

> Downloading voice: Voice download is only supported on OpenHarmony SDK 19 and above.

## 7. Open Source License

This project is based on [MIT](LICENSE). Please freely enjoy and participate in open source.
