import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SpeechRateValidRange Tests', () {
    test('constructor should set values correctly', () {
      final range = SpeechRateValidRange(0.0, 0.5, 0.7, 1.0, TextToSpeechPlatform.ohos);

      expect(range.min, 0.0);
      expect(range.normal, 0.5);
      expect(range.high, 0.7);
      expect(range.max, 1.0);
      expect(range.platform, TextToSpeechPlatform.ohos);
    });
  });

  group('OhosVoiceInfo Tests', () {
    test('fromJson should parse voice info correctly', () {
      final json = {
        'language': 'zh-CN',
        'person': 13,
        'style': 'normal',
        'gender': 'female',
        'description': '聆小珊女声',
        'status': 'INSTALLED',
      };

      final voiceInfo = OhosVoiceInfo.fromJson(json);

      expect(voiceInfo.language, 'zh-CN');
      expect(voiceInfo.person, 13);
      expect(voiceInfo.style, 'normal');
      expect(voiceInfo.gender, 'female');
      expect(voiceInfo.description, '聆小珊女声');
      expect(voiceInfo.status, 'INSTALLED');
      expect(voiceInfo.name, '聆小珊');
    });

    test('toJson should serialize voice info correctly', () {
      final voiceInfo = OhosVoiceInfo(
        language: 'zh-CN',
        person: 13,
        style: 'normal',
        gender: 'female',
        description: '聆小珊女声',
        status: 'INSTALLED',
      );

      final json = voiceInfo.toJson();

      expect(json['language'], 'zh-CN');
      expect(json['person'], 13);
      expect(json['style'], 'normal');
      expect(json['name'], '聆小珊');
      expect(json['gender'], 'female');
      expect(json['description'], '聆小珊女声');
      expect(json['status'], 'INSTALLED');
    });

    test('fromJson with null values should handle gracefully', () {
      final json = <String, dynamic>{};

      final voiceInfo = OhosVoiceInfo.fromJson(json);

      expect(voiceInfo.language, '');
      expect(voiceInfo.person, 0);
      expect(voiceInfo.style, '');
      expect(voiceInfo.gender, '');
      expect(voiceInfo.description, '');
      expect(voiceInfo.status, '');
    });
  });

  group('DownloadVoiceController Tests', () {
    test('constructor should set downloadId correctly', () {
      final controller = DownloadVoiceController(
        downloadId: 'test_id',
        onCancel: (id) {},
      );
      expect(controller.downloadId, 'test_id');
    });

    test('status should return pending initially', () {
      final controller = DownloadVoiceController(
        downloadId: 'test_id',
        onCancel: (id) {},
      );
      expect(controller.status, DownloadStatus.pending);
    });

    test('dispose should close stream without error', () async {
      final controller = DownloadVoiceController(
        downloadId: 'test_id',
        onCancel: (id) {},
      );
      // dispose() closes internal stream controller
      controller.dispose();
      final stream = controller.statusStream;
      await expectLater(stream, emitsDone);
    });

    test('cancel should invoke onCancel callback', () async {
      String? cancelledId;
      final controller = DownloadVoiceController(
        downloadId: 'test_id',
        onCancel: (id) { cancelledId = id; },
      );
      await controller.cancel();
      expect(cancelledId, 'test_id');
    });

    test('statusStream should return broadcast stream', () {
      final controller = DownloadVoiceController(
        downloadId: 'test_id',
        onCancel: (id) {},
      );
      expect(controller.statusStream, isA<Stream<DownloadStatus>>());
    });
  });

  group('DownloadVoiceEvent Tests', () {
    test('constructor should set all fields correctly', () {
      final voiceInfo = OhosVoiceInfo(
        language: 'zh-CN',
        person: 13,
        style: 'normal',
        gender: 'female',
        description: '聆小珊女声',
        status: 'INSTALLED',
      );
      final event = DownloadVoiceEvent(
        type: DownloadEventType.complete,
        downloadId: 'test_dl_1',
        voiceInfo: voiceInfo,
      );
      expect(event.type, DownloadEventType.complete);
      expect(event.downloadId, 'test_dl_1');
      expect(event.voiceInfo, isNotNull);
      expect(event.voiceInfo!.person, 13);
      expect(event.info, isNull);
      expect(event.errorCode, isNull);
    });

    test('constructor should handle error event fields', () {
      final event = DownloadVoiceEvent(
        type: DownloadEventType.error,
        downloadId: 'test_dl_2',
        errorCode: 500,
      );
      expect(event.type, DownloadEventType.error);
      expect(event.downloadId, 'test_dl_2');
      expect(event.errorCode, 500);
      expect(event.voiceInfo, isNull);
    });
  });
}
