/// Debug-only MiniMax connection. Values come from
/// `--dart-define-from-file=config/minimax.local.json`.
///
/// Do not ship this key in a release build. The app should later call the
/// owner's own speech backend, which holds the key. See README.
class MinimaxConfig {
  const MinimaxConfig({
    required this.apiKey,
    this.baseUrl = 'https://api.minimaxi.com',
    this.model = 'speech-2.8-hd',
    this.voiceId = 'Cantonese_GentleLady',
    this.languageBoost = 'Chinese,Yue',
  });

  factory MinimaxConfig.fromEnvironment() {
    return const MinimaxConfig(
      apiKey: String.fromEnvironment('MINIMAX_API_KEY'),
      baseUrl: String.fromEnvironment(
        'MINIMAX_BASE_URL',
        defaultValue: 'https://api.minimaxi.com',
      ),
      model: String.fromEnvironment(
        'MINIMAX_MODEL',
        defaultValue: 'speech-2.8-hd',
      ),
      voiceId: String.fromEnvironment(
        'MINIMAX_VOICE_ID',
        defaultValue: 'Cantonese_GentleLady',
      ),
      languageBoost: String.fromEnvironment(
        'MINIMAX_LANGUAGE_BOOST',
        defaultValue: 'Chinese,Yue',
      ),
    );
  }

  final String apiKey;
  final String baseUrl;
  final String model;
  final String voiceId;
  final String languageBoost;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  Uri get endpoint {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root/v1/t2a_v2');
  }
}

/// Fullwidth "（" is part of the MiniMax voice id. An ASCII "(" is rejected,
/// and the app then falls back to the device voice.
const minimaxMaryVoiceId = 'Cantonese_ProfessionalHost\uFF08F)';
const minimaxPeterVoiceId = 'Cantonese_Articulate_commentator_vv2';
const minimaxWaiterVoiceId = 'Chinese (Mandarin)_HK_Flight_Attendant';

/// Dialogue voice. Mary and Peter have their own voices. 侍應 uses
/// [minimaxWaiterVoiceId]. Lines without a speaker keep [MinimaxConfig.voiceId].
String? minimaxVoiceForSpeaker(String? speaker) {
  switch (speaker?.trim().toLowerCase()) {
    case 'mary':
      return minimaxMaryVoiceId;
    case 'peter':
      return minimaxPeterVoiceId;
    case '侍應':
    case '侍应':
      return minimaxWaiterVoiceId;
    default:
      return null;
  }
}

/// MiniMax speed at the in-app "正常" slider (0.42).
///
/// 1.0 is MiniMax's conversational pace, which runs Cantonese syllables
/// together. Review speech starts slower so each syllable stays distinct.
const minimaxReviewSpeed = 0.7;

/// Maps the in-app rate slider onto MiniMax speed (allowed range 0.5–2).
double minimaxSpeedForRate(double rate) {
  return (rate / 0.42 * minimaxReviewSpeed).clamp(0.5, 2.0);
}
