import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'device_tts_service.dart';
import 'minimax_config.dart';

class MinimaxTtsException implements Exception {
  MinimaxTtsException(this.message, {required this.canRetryWithPlainText});

  final String message;
  final bool canRetryWithPlainText;

  @override
  String toString() => message;
}

/// MiniMax synchronous speech. The model reads [text] as written.
/// Jyutping stays on the card for display and is not sent as a pronunciation rule.
class MinimaxTtsClient {
  MinimaxTtsClient({required this.config, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final MinimaxConfig config;
  final http.Client _httpClient;

  static const _authStatusCodes = {1004, 1008, 2049};

  Future<Uint8List> synthesize({
    required String text,
    double speed = 1,
    String? voiceId,
  }) async {
    final plain = sanitizeSpeakText(text);
    if (plain.isEmpty) {
      throw MinimaxTtsException('没有可朗读的文本', canRetryWithPlainText: false);
    }
    return _post(plain, speed, voiceId: voiceId);
  }

  Future<Uint8List> _post(String text, double speed, {String? voiceId}) async {
    final selected = (voiceId == null || voiceId.trim().isEmpty)
        ? config.voiceId
        : voiceId.trim();
    final body = <String, Object?>{
      'model': config.model,
      'text': text,
      'stream': false,
      'language_boost': config.languageBoost,
      'voice_setting': {
        'voice_id': selected,
        'speed': speed,
        'vol': 1,
        'pitch': 0,
      },
      'audio_setting': {
        'sample_rate': 32000,
        'bitrate': 128000,
        'format': 'mp3',
        'channel': 1,
      },
    };
    final response = await _httpClient
        .post(
          config.endpoint,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw MinimaxTtsException('MiniMax 密钥无效', canRetryWithPlainText: false);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MinimaxTtsException(
        'MiniMax 请求失败（${response.statusCode}）',
        canRetryWithPlainText: true,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw MinimaxTtsException('MiniMax 返回无法解析', canRetryWithPlainText: true);
    }

    final base = decoded['base_resp'];
    if (base is Map && (base['status_code'] ?? 0) != 0) {
      final code = base['status_code'];
      final retry = code is! int || !_authStatusCodes.contains(code);
      throw MinimaxTtsException(
        'MiniMax：${base['status_msg'] ?? code}',
        canRetryWithPlainText: retry,
      );
    }

    final data = decoded['data'];
    final audio = data is Map ? data['audio'] : null;
    if (audio is! String || audio.isEmpty) {
      throw MinimaxTtsException('MiniMax 没有返回音频', canRetryWithPlainText: true);
    }
    return _decodeHex(audio);
  }
}

Uint8List _decodeHex(String audio) {
  final cleaned = audio.trim();
  if (cleaned.length.isOdd) {
    throw MinimaxTtsException('MiniMax 音频无法解析', canRetryWithPlainText: true);
  }
  final bytes = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final byte = int.tryParse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) {
      throw MinimaxTtsException('MiniMax 音频无法解析', canRetryWithPlainText: true);
    }
    bytes[i] = byte;
  }
  return bytes;
}
