## 4.2.3-ohos-1.0.0

### flutter_tts Quality Hardening

#### Queue Mode Fixes

* **`handleSpeak` focus parameter no longer overrides queueMode**: Previously, `focus=true` always forced priority mode, causing queue mode to become ineffective. After the fix, `focus` is only used for Android audio focus handling and no longer affects OHOS `queueMode`.
* **Queue mode no longer rejects new speak calls**: Previously, when `awaitSpeakCompletion` was enabled, queue mode rejected subsequent `speak` calls because `speakResult` was occupied. After the fix, only priority mode rejects concurrent requests, while queue mode allows new requests to be queued.
* **Demo improvements**: Corrected `queueMode` comments (`0 = priority mode / 1 = queue mode`), fixed the Switch direction, changed the default value to `1` (queue mode), and removed the incorrect `focus` binding.

#### API and Exception Safety

* **Global `try-catch` added to `onMethodCall`**: Added outer-level exception handling to prevent Dart Futures from remaining unresolved.
* **`speak()` engine initialization waiting and exception propagation**: When the engine is not ready, an error is returned. Exceptions now release resources properly and propagate back to the Flutter layer.
* **Standardized `setEngine` return values**: Changed to use `result.error()` for consistent error reporting.
* **Fixed `downloadVoice` event listener leaks**: All listeners are cancelled in cancel/error callbacks, and a new `removeActiveDownloadResponse` mechanism was added.
* **Fixed `isLanguageInstalled` / `areLanguagesInstalled` semantics**: Real installation status is now checked through the `listVoices` API.

#### Resource and Concurrency Safety

* **Fixed `speakListener` circular references**: Stored as a member variable and explicitly detached during lifecycle cleanup to break reference chains.
* **Hardened `clearAllPendingTimeouts` cleanup**: Replaced `forEach` with `for...of` for safer timeout cleanup.
* **Added lock protection for `synthAudioBuffers`**: Concurrent writes inside the `onData` callback are now protected using `lock.lockAsync()`.
* **Improved call chain integrity**: Added engine initialization and null checks to `synthesizeToFile`, `getVoices`, and `getDefaultVoice`.

#### Coding Standards Alignment

* **Class naming standardization**: Renamed `FlutterttsPlugin` to `FlutterTtsPlugin`.
* **Type safety improvements**: Removed `Any` types and added 47+ type annotations and 36 semicolons.
* **Unified logging format**: Removed invalid `toUpperCase()` usage and standardized logger prefixes with `[FlutterTts]`.
* **Enhanced parameter validation**: Added validation for `setLanguage` (`zh-CN` / `en-US`) and validated the `person` key in `setVoice`.
* **Ability lifecycle binding**: Added `onAttachedToAbility` / `onDetachedFromAbility`.
* **Naming standardization**: Renamed `lock_` to `lock`, and added complete JSDoc comments for Logger methods.

#### Feature Fixes and Test Documentation

* **Fixed `setLanguage` functionality**: The engine is now recreated when changing languages, and the `languageContext` reference issue was fixed.
* **Unit tests**: Added 30 test cases covering core APIs and OHOS data classes.
* **README improvements**: Fixed documentation issues, added documentation for 10 APIs, and introduced a new "OHOS Exclusive Types" section.

### bug fix

* Fixed `speak()` parameter parsing to support both Map objects and string formats.
* Implemented `awaitSpeakCompletion()` for synchronous waiting until speech playback finishes.
* Implemented `awaitSynthCompletion()` for synchronous waiting until file synthesis completes.
* Implemented `pause()` by simulating pause behavior through `stop()`.
* Implemented `synthesizeToFile()` by collecting audio streams through `onData` and writing them into files.
* Implemented `speak.onContinue` callback to distinguish between playback start and playback resume.
* Removed the `style` setting from engine creation parameters to avoid extra prompt sounds caused by broadcast speech styles.
* Added `@kit.CoreFileKit` dependency for file writing operations.

---

## 4.2.3-ohos-1.0.0-beta.1

* TAG: `4.2.3-ohos-1.0.0-beta.1`