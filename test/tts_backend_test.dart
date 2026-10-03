import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yue_buddy/core/audio/backend_tts_client.dart';
import 'package:yue_buddy/core/audio/tts_backend_config.dart';

const _config = TtsBackendConfig(baseUrl: 'https://tts.example.com');

void main() {
  group('gear', () {
    test('quantizes the rate slider to three gears', () {
      expect(ttsGearForRate(0.2), TtsGear.slow);
      expect(ttsGearForRate(0.31), TtsGear.slow);
      expect(ttsGearForRate(0.32), TtsGear.normal);
      expect(ttsGearForRate(0.42), TtsGear.normal);
      expect(ttsGearForRate(0.59), TtsGear.normal);
      expect(ttsGearForRate(0.6), TtsGear.fast);
      expect(ttsGearForRate(0.8), TtsGear.fast);
    });

    test('maps gears to MiniMax speeds', () {
      expect(ttsSpeedForGear(TtsGear.slow), 0.5);
      expect(ttsSpeedForGear(TtsGear.normal), 0.7);
      expect(ttsSpeedForGear(TtsGear.fast), 1.0);
    });
  });

  group('cache key', () {
    test('follows the Worker contract format', () {
      final key = ttsCacheKeyForTest(
        modelVersion: 'mm-speech28hd-v1',
        voiceId: 'Cantonese_GentleLady',
        gear: TtsGear.normal,
        text: '早晨！',
      );
      expect(
        key,
        matches(
          r'^tts/v1/mm-speech28hd-v1/gentle/normal/[0-9a-f]{64}\.mp3$',
        ),
      );
    });

    test('slugs voices to url-safe aliases', () {
      expect(ttsVoiceSlugForTest('Cantonese_GentleLady'), 'gentle');
      expect(
        ttsVoiceSlugForTest('Cantonese_ProfessionalHost（F)'),
        'mary',
      );
      expect(
        ttsVoiceSlugForTest('Cantonese_Articulate_commentator_vv2'),
        'peter',
      );
      expect(
        ttsVoiceSlugForTest('Chinese (Mandarin)_HK_Flight_Attendant'),
        'waiter',
      );
      expect(
        ttsVoiceSlugForTest('Some New Voice'),
        matches(r'^v-[0-9a-f]{12}$'),
      );
    });

    test('gear changes the key, blanks do not', () {
      String hashOf(String text) => ttsCacheKeyForTest(
        modelVersion: 'v',
        voiceId: 'voice',
        gear: TtsGear.normal,
        text: text,
      ).split('/').last;
      expect(hashOf('Hello___world'), hashOf('Hello world'));
      final slow = ttsCacheKeyForTest(
        modelVersion: 'v',
        voiceId: 'voice',
        gear: TtsGear.slow,
        text: '早晨',
      );
      final fast = ttsCacheKeyForTest(
        modelVersion: 'v',
        voiceId: 'voice',
        gear: TtsGear.fast,
        text: '早晨',
      );
      expect(slow, isNot(fast));
    });
  });

  group('config', () {
    test('is disabled without a base url', () {
      expect(
        const TtsBackendConfig(baseUrl: '').isConfigured,
        isFalse,
      );
      expect(_config.isConfigured, isTrue);
    });

    test('joins endpoint paths with or without trailing slash', () {
      expect(
        _config.endpoint('/v1/tts').toString(),
        'https://tts.example.com/v1/tts',
      );
      expect(
        const TtsBackendConfig(
          baseUrl: 'https://tts.example.com/',
        ).endpoint('/v1/tts').toString(),
        'https://tts.example.com/v1/tts',
      );
    });
  });

  group('BackendTtsClient', () {
    test('resolves a relative url against the base url', () async {
      final requests = <Map<String, dynamic>>[];
      final client = BackendTtsClient(
        config: _config,
        httpClient: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({'url': '/a/tts/key.mp3', 'cache': 'HIT'}),
            200,
          );
        }),
      );

      final sound = await client.resolve(
        text: '堂食___',
        gear: TtsGear.normal,
      );

      expect(requests.single['text'], '堂食');
      expect(requests.single['gear'], 'normal');
      expect(requests.single['voiceId'], 'Cantonese_GentleLady');
      expect(sound.uri.toString(), 'https://tts.example.com/a/tts/key.mp3');
      expect(sound.cacheHit, isTrue);
    });

    test('passes absolute urls through and keeps custom voices', () async {
      final client = BackendTtsClient(
        config: _config,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['voiceId'], 'custom-voice');
          return http.Response(
            jsonEncode({
              'url': 'https://cdn.example.com/x.mp3',
              'cache': 'MISS',
            }),
            200,
          );
        }),
      );

      final sound = await client.resolve(
        text: '早晨',
        gear: TtsGear.fast,
        voiceId: 'custom-voice',
      );
      expect(sound.uri.toString(), 'https://cdn.example.com/x.mp3');
      expect(sound.cacheHit, isFalse);
    });

    test('rejects blank text without a request', () async {
      var calls = 0;
      final client = BackendTtsClient(
        config: _config,
        httpClient: MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        client.resolve(text: '   ___  ', gear: TtsGear.normal),
        throwsA(isA<BackendTtsException>()),
      );
      expect(calls, 0);
    });

    test('batch skips blank items and returns urls in order', () async {
      final requests = <Map<String, dynamic>>[];
      final client = BackendTtsClient(
        config: _config,
        httpClient: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'urls': ['/a/1.mp3', '/a/2.mp3'],
            }),
            200,
          );
        }),
      );

      final sounds = await client.resolveBatch(
        items: const [
          BackendTtsRequest(text: '第一句'),
          BackendTtsRequest(text: '___'),
          BackendTtsRequest(text: '第二句', voiceId: 'v2'),
        ],
        gear: TtsGear.slow,
      );

      final items = requests.single['items'] as List;
      expect(items, hasLength(2));
      expect(sounds.map((s) => s.uri.toString()), [
        'https://tts.example.com/a/1.mp3',
        'https://tts.example.com/a/2.mp3',
      ]);
    });

    test('maps rate limiting and server errors', () async {
      Future<void> expectMessage(
        int status,
        String snippet,
      ) async {
        final client = BackendTtsClient(
          config: _config,
          httpClient: MockClient(
            (request) async => http.Response('busy', status),
          ),
        );
        await expectLater(
          client.resolve(text: '早晨', gear: TtsGear.normal),
          throwsA(
            isA<BackendTtsException>().having(
              (e) => e.message,
              'message',
              contains(snippet),
            ),
          ),
        );
      }

      await expectMessage(429, '稍后再试');
      await expectMessage(502, '502');
    });
  });
}
