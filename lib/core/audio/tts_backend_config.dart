import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'device_tts_service.dart';

/// Server-side TTS backend (Cloudflare Worker + R2 cache).
/// Values come from `--dart-define-from-file=config/tts.local.json`.
/// When [baseUrl] is empty the app skips the backend entirely.
class TtsBackendConfig {
  const TtsBackendConfig({
    required this.baseUrl,
    this.defaultVoiceId = 'Cantonese_GentleLady',
  });

  factory TtsBackendConfig.fromEnvironment() {
    return const TtsBackendConfig(
      baseUrl: String.fromEnvironment('TTS_BASE_URL'),
      defaultVoiceId: String.fromEnvironment(
        'TTS_DEFAULT_VOICE_ID',
        defaultValue: 'Cantonese_GentleLady',
      ),
    );
  }

  final String baseUrl;
  final String defaultVoiceId;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Uri endpoint(String path) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path');
  }
}

/// Cache gear. Only these three speeds exist on the wire so the R2
/// key space stays small; see workers/tts/CONTRACT.md.
enum TtsGear { slow, normal, fast }

extension TtsGearName on TtsGear {
  String get name {
    switch (this) {
      case TtsGear.slow:
        return 'slow';
      case TtsGear.normal:
        return 'normal';
      case TtsGear.fast:
        return 'fast';
    }
  }
}

/// MiniMax speed per gear. `normal` keeps the review pace (0.7).
double ttsSpeedForGear(TtsGear gear) {
  switch (gear) {
    case TtsGear.slow:
      return 0.5;
    case TtsGear.normal:
      return 0.7;
    case TtsGear.fast:
      return 1.0;
  }
}

/// Quantizes the in-app rate slider (0.2–0.8, 0.42 = 正常) to the
/// nearest gear boundary. Midpoints: slow|normal at 0.32, normal|fast at 0.6.
TtsGear ttsGearForRate(double rate) {
  if (rate < 0.32) return TtsGear.slow;
  if (rate < 0.6) return TtsGear.normal;
  return TtsGear.fast;
}

TtsGear ttsGearForSpeedValue(double speed) {
  const gears = TtsGear.values;
  var best = gears.first;
  var bestDistance = (ttsSpeedForGear(best) - speed).abs();
  for (final gear in gears.skip(1)) {
    final distance = (ttsSpeedForGear(gear) - speed).abs();
    if (distance < bestDistance) {
      best = gear;
      bestDistance = distance;
    }
  }
  return best;
}

/// Test-only mirror of the Worker key format:
/// `tts/v1/{modelVersion}/{voiceSlug}/{gear}/{sha256(normalize(text))}.mp3`
String ttsCacheKeyForTest({
  required String modelVersion,
  required String voiceId,
  required TtsGear gear,
  required String text,
}) {
  final normalized = sanitizeSpeakText(text);
  final hash = sha256.convert(utf8.encode(normalized)).toString();
  return 'tts/v1/$modelVersion/${ttsVoiceSlugForTest(voiceId)}/${gear.name}/$hash.mp3';
}

/// Test-only mirror of the Worker voice slug (see CONTRACT.md).
String ttsVoiceSlugForTest(String voiceId) {
  const known = {
    'Cantonese_GentleLady': 'gentle',
    'Cantonese_ProfessionalHost（F)': 'mary',
    'Cantonese_Articulate_commentator_vv2': 'peter',
    'Chinese (Mandarin)_HK_Flight_Attendant': 'waiter',
  };
  final slug = known[voiceId];
  if (slug != null) return slug;
  return 'v-${sha256.convert(utf8.encode(voiceId)).toString().substring(0, 12)}';
}
