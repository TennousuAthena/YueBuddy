import 'package:flutter_test/flutter_test.dart';
import 'package:yue_buddy/core/audio/device_tts_service.dart';
import 'package:yue_buddy/core/audio/tts_locale.dart';

void main() {
  group('pickCantoneseLocale', () {
    test('prefers zh-HK over Mandarin locales', () {
      expect(
        pickCantoneseLocale(const ['zh-CN', 'en-US', 'zh-HK', 'zh-TW']),
        'zh-HK',
      );
    });

    test('accepts underscore and yue variants', () {
      expect(pickCantoneseLocale(const ['zh_HK']), 'zh_HK');
      expect(pickCantoneseLocale(const ['yue-HK']), 'yue-HK');
      expect(pickCantoneseLocale(const ['yue']), 'yue');
    });

    test('does not fall back to Mandarin', () {
      expect(pickCantoneseLocale(const ['zh-CN', 'zh-TW', 'en-US']), isNull);
    });
  });

  test('sanitizeSpeakText strips blanks for TTS', () {
    expect(sanitizeSpeakText('大家好！我係___。'), '大家好！我係 。');
    expect(sanitizeSpeakText('我住喺……'), '我住喺');
  });
}
