import 'package:flutter/foundation.dart';

/// True on the HarmonyOS Flutter embedder.
///
/// Official Flutter has no `TargetPlatform.ohos`. Comparing the enum name
/// still compiles there, and is only true when the HarmonyOS SDK is running.
bool get isHarmonyOs => !kIsWeb && defaultTargetPlatform.name == 'ohos';
