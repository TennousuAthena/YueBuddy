import 'dart:convert';

import 'package:http/http.dart' as http;

import 'device_tts_service.dart';
import 'tts_backend_config.dart';

class BackendTtsException implements Exception {
  BackendTtsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the app's own TTS backend (Cloudflare Worker + R2 cache).
/// Returns playable audio URLs instead of bytes so `audioplayers` can
/// stream via `UrlSource` and edge CDN caching applies. Web works too.
class BackendTtsClient {
  BackendTtsClient({required this.config, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final TtsBackendConfig config;
  final http.Client _httpClient;

  /// Resolves one sentence to a playable URL (cache HIT or lazy MISS).
  Future<BackendTtsSound> resolve({
    required String text,
    required TtsGear gear,
    String? voiceId,
  }) async {
    final plain = sanitizeSpeakText(text);
    if (plain.isEmpty) {
      throw BackendTtsException('没有可朗读的文本');
    }
    final response = await _httpClient
        .post(
          config.endpoint('/v1/tts'),
          headers: {
            'Content-Type': 'application/json',
            // Reserved for future auth (server currently ignores it).
            // 'Authorization': 'Bearer ...',
          },
          body: jsonEncode({
            'text': plain,
            'voiceId': _voiceId(voiceId),
            'gear': gear.name,
          }),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(response);
    final url = decoded['url'];
    if (url is! String || url.isEmpty) {
      throw BackendTtsException('语音后端没有返回音频地址');
    }
    return BackendTtsSound(
      uri: _absolute(url),
      cacheHit: decoded['cache'] == 'HIT',
    );
  }

  /// Resolves a dialogue sequence in one round trip for prefetch.
  Future<List<BackendTtsSound>> resolveBatch({
    required List<BackendTtsRequest> items,
    required TtsGear gear,
  }) async {
    final payload = <Map<String, String>>[];
    for (final item in items) {
      final plain = sanitizeSpeakText(item.text);
      if (plain.isEmpty) continue;
      payload.add({'text': plain, 'voiceId': _voiceId(item.voiceId)});
    }
    if (payload.isEmpty) return const [];
    final response = await _httpClient
        .post(
          config.endpoint('/v1/tts/batch'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'items': payload, 'gear': gear.name}),
        )
        .timeout(const Duration(seconds: 60));
    final decoded = _decode(response);
    final urls = decoded['urls'];
    if (urls is! List) {
      throw BackendTtsException('语音后端没有返回音频地址');
    }
    return [
      for (final url in urls)
        BackendTtsSound(uri: _absolute(url as String), cacheHit: false),
    ];
  }

  String _voiceId(String? voiceId) {
    final trimmed = voiceId?.trim() ?? '';
    return trimmed.isEmpty ? config.defaultVoiceId : trimmed;
  }

  Uri _absolute(String url) {
    final parsed = Uri.parse(url);
    if (parsed.hasScheme) return parsed;
    return config.endpoint(url);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw BackendTtsException('语音后端拒绝访问（${response.statusCode}）');
    }
    if (response.statusCode == 429) {
      throw BackendTtsException('大家都在听，请稍后再试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendTtsException('语音后端请求失败（${response.statusCode}）');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw BackendTtsException('语音后端返回无法解析');
    }
    return decoded;
  }
}

class BackendTtsRequest {
  const BackendTtsRequest({required this.text, this.voiceId});

  final String text;
  final String? voiceId;
}

class BackendTtsSound {
  const BackendTtsSound({required this.uri, required this.cacheHit});

  final Uri uri;
  final bool cacheHit;
}
