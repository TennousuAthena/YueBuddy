import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yue_buddy/core/audio/minimax_config.dart';
import 'package:yue_buddy/core/audio/minimax_tts_client.dart';

void main() {
  const config = MinimaxConfig(apiKey: 'test-key');

  test('sends the Cantonese text and no pronunciation table', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MinimaxTtsClient(
      config: config,
      httpClient: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _audioResponse('00ff');
      }),
    );

    final bytes = await client.synthesize(text: '堂食');

    expect(requests, hasLength(1));
    expect(requests.single['text'], '堂食');
    expect(requests.single.containsKey('pronunciation_dict'), isFalse);
    expect(requests.single['voice_setting']['speed'], 1);
    expect(
      requests.single['voice_setting']['voice_id'],
      'Cantonese_GentleLady',
    );
    expect(bytes, Uint8List.fromList([0x00, 0xff]));
    expect(client.config.languageBoost, 'Chinese,Yue');
  });

  test('uses Mary and Peter voices in dialogue', () async {
    expect(minimaxVoiceForSpeaker('Mary'), minimaxMaryVoiceId);
    expect(minimaxVoiceForSpeaker('Peter'), minimaxPeterVoiceId);
    expect(minimaxVoiceForSpeaker('侍應'), minimaxWaiterVoiceId);
    expect(minimaxVoiceForSpeaker('侍应'), minimaxWaiterVoiceId);

    final requests = <Map<String, dynamic>>[];
    final client = MinimaxTtsClient(
      config: config,
      httpClient: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _audioResponse('ab');
      }),
    );

    await client.synthesize(text: '我睇下先。', voiceId: minimaxMaryVoiceId);
    await client.synthesize(
      text: '兩個吖，唔該。',
      voiceId: minimaxVoiceForSpeaker('Peter'),
    );

    expect(requests[0]['voice_setting']['voice_id'], minimaxMaryVoiceId);
    expect(
      requests[1]['voice_setting']['voice_id'],
      'Cantonese_Articulate_commentator_vv2',
    );
    expect(requests[0].containsKey('pronunciation_dict'), isFalse);
  });

  test('maps the normal slider to a slower MiniMax pace', () {
    expect(minimaxSpeedForRate(0.42), closeTo(0.7, 0.001));
    expect(minimaxSpeedForRate(0.2), 0.5);
    expect(minimaxSpeedForRate(0.7), closeTo(1.1667, 0.001));
  });

  test('does not retry when the key is rejected', () async {
    var calls = 0;
    final client = MinimaxTtsClient(
      config: config,
      httpClient: MockClient((request) async {
        calls++;
        return http.Response('unauthorized', 401);
      }),
    );

    await expectLater(
      client.synthesize(text: '早晨！'),
      throwsA(isA<MinimaxTtsException>()),
    );
    expect(calls, 1);
  });
}

http.Response _audioResponse(String audioHex) {
  return http.Response(
    jsonEncode({
      'data': {'audio': audioHex, 'status': 2},
      'base_resp': {'status_code': 0, 'status_msg': 'success'},
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}
