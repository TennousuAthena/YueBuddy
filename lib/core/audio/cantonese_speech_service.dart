import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'device_tts_service.dart';
import 'backend_tts_client.dart';
import 'minimax_config.dart';
import 'minimax_tts_client.dart';
import 'speech_service.dart';
import 'teacher_run.dart';
import 'tts_backend_config.dart';

/// Prefers the app's own TTS backend (Worker + R2 cache), then MiniMax
/// direct in debug builds, then the device voice. Backend playback streams
/// URLs so Web works without a MiniMax key in the bundle.
class CantoneseSpeechService extends SpeechService {
  CantoneseSpeechService({
    required DeviceTtsService device,
    required MinimaxConfig config,
    TtsBackendConfig backend = const TtsBackendConfig(baseUrl: ''),
    BackendTtsClient? backendClient,
    MinimaxTtsClient? client,
    AudioPlayer? player,
  }) : _device = device,
       _config = config,
       _backend = backend,
       _backendClient = backendClient ?? BackendTtsClient(config: backend),
       _client = client ?? MinimaxTtsClient(config: config),
       _player = player ?? AudioPlayer() {
    // Frame-by-frame position reads keep a platform call and a text
    // rebuild on every vsync while audio is playing. A short timer is
    // enough for karaoke and leaves the frame budget for scrolling.
    _player.positionUpdater = TimerPositionUpdater(
      getPosition: _player.getCurrentPosition,
      interval: const Duration(milliseconds: 50),
    );
  }

  final DeviceTtsService _device;
  final MinimaxConfig _config;
  final TtsBackendConfig _backend;
  final BackendTtsClient _backendClient;
  final MinimaxTtsClient _client;
  final AudioPlayer _player;

  bool _ready = false;
  bool _available = false;
  bool _speaking = false;
  bool _usingDevice = false;
  bool _onlineEnabled = true;
  String? _status;
  bool _statusWarning = false;
  String? _activeItemId;
  String? _activeSequenceId;
  int _activeSequenceIndex = 0;
  int _activeSequenceTotal = 0;
  final ValueNotifier<int?> _positionMs = ValueNotifier<int?>(null);
  double _rate = 0.42;
  int _token = 0;
  Completer<void>? _playback;

  bool get usesBackend => _onlineEnabled && _backend.isConfigured;

  bool get usesMinimax => _onlineEnabled && !kIsWeb && _config.isConfigured;

  @override
  bool get isReady => _ready;

  @override
  bool get isCantoneseAvailable => _available;

  @override
  bool get isSpeaking => _speaking;

  @override
  String? get statusMessage => _status;

  @override
  bool get statusIsWarning => _statusWarning;

  @override
  String? get activeItemId => _activeItemId;

  @override
  String? get activeSequenceId => _activeSequenceId;

  @override
  int get activeSequenceIndex => _activeSequenceIndex;

  @override
  int get activeSequenceTotal => _activeSequenceTotal;

  @override
  ValueListenable<int?> get sequencePositionMs => _positionMs;

  @override
  Future<void> initialize() async {
    _device.addListener(_onDevice);
    await _device.initialize();
    _syncAvailability();
    _ready = true;
    notifyListeners();
  }

  @override
  Future<void> speak(SpeechUtterance utterance, {String? itemId}) {
    return speakSequence([utterance], itemId: itemId);
  }

  @override
  Future<void> speakSequence(
    List<SpeechUtterance> utterances, {
    String? itemId,
  }) async {
    final token = ++_token;
    await _haltPlayback();
    if (!_available || utterances.isEmpty) return;

    _activeItemId = itemId;
    _speaking = true;
    _usingDevice = false;
    notifyListeners();

    if (usesBackend) {
      try {
        await _speakViaBackend(utterances, token);
        if (token != _token) return;
        _speaking = false;
        _activeItemId = null;
        _syncAvailability();
        notifyListeners();
        return;
      } catch (_) {
        if (token != _token) return;
        // Fall through to MiniMax direct / device below.
      }
    }

    if (usesMinimax) {
      try {
        for (final utterance in utterances) {
          if (token != _token) return;
          final bytes = await _client.synthesize(
            text: utterance.text,
            speed: minimaxSpeedForRate(_rate),
            voiceId: utterance.voiceId,
          );
          if (token != _token) return;
          await _play(bytes, token);
        }
        if (token != _token) return;
        _speaking = false;
        _activeItemId = null;
        _syncAvailability();
        notifyListeners();
        return;
      } catch (error) {
        if (token != _token) return;
        if (!_device.isCantoneseAvailable) {
          _speaking = false;
          _activeItemId = null;
          _setStatus('MiniMax 发音失败：$error', warning: true);
          notifyListeners();
          return;
        }
        _setStatus('MiniMax 发音失败，已改用设备语音。', warning: true);
        notifyListeners();
      }
    }

    if (token != _token) return;
    _usingDevice = true;
    await _device.speakSequence(utterances, itemId: itemId);
  }

  @override
  Future<void> playRecordings(List<String> assetPaths, {String? itemId}) async {
    final token = ++_token;
    await _haltPlayback();
    if (assetPaths.isEmpty) return;

    _activeItemId = itemId;
    _speaking = true;
    _usingDevice = false;
    notifyListeners();
    try {
      for (final path in assetPaths) {
        if (token != _token) return;
        await _playSource(AssetSource(path), token);
      }
    } catch (error) {
      if (token != _token) return;
      _setStatus('课上录音播放失败：$error', warning: true);
    }
    if (token != _token) return;
    _speaking = false;
    _activeItemId = null;
    notifyListeners();
  }

  /// Plays one timestamped slice of a teacher recording. Works without
  /// device TTS: seeks to [start] and stops shortly after [end].
  @override
  Future<void> playSegment({
    required String assetPath,
    required Duration start,
    required Duration end,
    String? itemId,
  }) async {
    final token = ++_token;
    await _haltPlayback();
    if (end <= start) return;

    _activeItemId = itemId;
    _speaking = true;
    _usingDevice = false;
    notifyListeners();

    final stopAt = end + const Duration(milliseconds: 250);
    final playback = Completer<void>();
    _playback = playback;
    StreamSubscription<void>? doneSub;
    StreamSubscription<Duration>? posSub;
    try {
      doneSub = _player.onPlayerComplete.listen((_) {
        if (!playback.isCompleted) playback.complete();
      });
      posSub = _player.onPositionChanged.listen((position) {
        if (position >= stopAt && !playback.isCompleted) {
          playback.complete();
        }
      });
      await _player.play(AssetSource(assetPath), position: start);
      await playback.future;
      if (token == _token) await _player.stop();
    } catch (error) {
      if (token != _token) return;
      _setStatus('老师原音播放失败：$error', warning: true);
    } finally {
      await posSub?.cancel();
      await doneSub?.cancel();
      if (identical(_playback, playback)) _playback = null;
    }
    if (token != _token) return;
    _speaking = false;
    _activeItemId = null;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _token++;
    _usingDevice = false;
    await _haltPlayback();
    _speaking = false;
    _activeItemId = null;
    _clearSequence();
    notifyListeners();
  }

  @override
  void updateSpeechRate(double rate) {
    _rate = rate.clamp(0.2, 0.8);
    _device.updateSpeechRate(_rate);
  }

  /// Toggles network TTS (backend + MiniMax direct). When disabled the
  /// service only uses the system voice and never touches the network.
  void setOnlineTtsEnabled(bool value) {
    if (_onlineEnabled == value) return;
    _onlineEnabled = value;
    _syncAvailability();
    notifyListeners();
  }

  /// Dialogue follow-along: teacher slices where available, TTS fallback
  /// otherwise. Updates [activeItemId] per entry and publishes the player
  /// position for karaoke; TTS entries report unknown position.
  @override
  Future<void> playSequence(
    List<SequenceEntry> entries, {
    String? itemId,
  }) async {
    final token = ++_token;
    await _haltPlayback();
    if (entries.isEmpty) return;

    _activeSequenceId = itemId;
    _activeSequenceTotal = entries.length;
    _activeSequenceIndex = 0;
    _speaking = true;
    _usingDevice = false;
    _positionMs.value = null;
    notifyListeners();

    StreamSubscription<Duration>? posSub;
    try {
      posSub = _player.onPositionChanged.listen(
        (position) => _positionMs.value = position.inMilliseconds,
      );
      // Prefetch all TTS fallback lines in one backend round trip so the
      // first MISS warms the whole dialogue while teacher slices play.
      final prefetched = await _prefetchSequenceTts(entries, token);
      for (var i = 0; i < entries.length;) {
        if (token != _token) return;
        final entry = entries[i];
        if (entry.hasTeacherAudio) {
          _usingDevice = false;
          i = await _playTeacherRun(entries, i, token);
          continue;
        }
        _activeItemId = entry.itemId;
        _activeSequenceIndex = i;
        _positionMs.value = null;
        notifyListeners();
        if (prefetched.containsKey(i)) {
          if (token != _token) return;
          await _playUrl(prefetched[i]!, token);
        } else {
          await _speakEntryText(entry.fallbackText, entry.voiceId, token);
        }
        i++;
      }
    } catch (error) {
      if (token != _token) return;
      _setStatus('整段播放失败：$error', warning: true);
    } finally {
      await posSub?.cancel();
    }
    if (token != _token) return;
    _speaking = false;
    _activeItemId = null;
    _clearSequence();
    _syncAvailability();
    notifyListeners();
  }

  @override
  void dispose() {
    _device.removeListener(_onDevice);
    _player.dispose();
    _positionMs.dispose();
    super.dispose();
  }

  Future<void> _play(Uint8List bytes, int token) {
    return _playSource(BytesSource(bytes, mimeType: 'audio/mpeg'), token);
  }

  Future<void> _playUrl(Uri uri, int token) {
    return _playSource(UrlSource(uri.toString()), token);
  }

  /// Backend playback with one-round-trip prefetch: resolves every
  /// utterance to a cached/streaming URL first, then plays in order.
  Future<void> _speakViaBackend(
    List<SpeechUtterance> utterances,
    int token,
  ) async {
    final gear = ttsGearForRate(_rate);
    final sounds = await _backendClient.resolveBatch(
      items: [
        for (final utterance in utterances)
          BackendTtsRequest(text: utterance.text, voiceId: utterance.voiceId),
      ],
      gear: gear,
    );
    var soundIndex = 0;
    for (final utterance in utterances) {
      if (token != _token) return;
      if (sanitizeSpeakText(utterance.text).isEmpty) continue;
      if (soundIndex >= sounds.length) return;
      await _playUrl(sounds[soundIndex].uri, token);
      soundIndex++;
    }
  }

  /// Prefetches TTS fallback entries of a dialogue sequence keyed by
  /// entry index. Empty map = prefetch skipped/failed; callers fall back
  /// to per-entry [_speakEntryText].
  Future<Map<int, Uri>> _prefetchSequenceTts(
    List<SequenceEntry> entries,
    int token,
  ) async {
    if (!usesBackend) return const {};
    final indices = <int>[];
    final items = <BackendTtsRequest>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.hasTeacherAudio) continue;
      if (sanitizeSpeakText(entry.fallbackText).isEmpty) continue;
      indices.add(i);
      items.add(
        BackendTtsRequest(text: entry.fallbackText, voiceId: entry.voiceId),
      );
    }
    if (items.isEmpty) return const {};
    try {
      final sounds = await _backendClient.resolveBatch(
        items: items,
        gear: ttsGearForRate(_rate),
      );
      if (token != _token) return const {};
      final result = <int, Uri>{};
      for (var j = 0; j < indices.length && j < sounds.length; j++) {
        result[indices[j]] = sounds[j].uri;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Plays one recording straight through a run of slices.
  ///
  /// Stopping and calling play()+seek() per sentence restarts the file
  /// from the beginning for a moment, then jumps. The old end padding
  /// also spoke the first part of the next line before that restart, so
  /// each hand-off stuttered and repeated. The highlight moves when the
  /// playhead crosses the next slice; the decoder stays on the same file.
  /// Returns the exclusive end index of the run.
  Future<int> _playTeacherRun(
    List<SequenceEntry> entries,
    int start,
    int token,
  ) async {
    final end = teacherRunEnd(entries, start);
    var cursor = start;
    _activeItemId = entries[cursor].itemId;
    _activeSequenceIndex = cursor;
    notifyListeners();

    final playback = Completer<void>();
    _playback = playback;
    StreamSubscription<void>? doneSub;
    StreamSubscription<Duration>? stopSub;
    try {
      doneSub = _player.onPlayerComplete.listen((_) {
        if (!playback.isCompleted) playback.complete();
      });
      stopSub = _player.onPositionChanged.listen((position) {
        if (token != _token || playback.isCompleted) return;
        final ms = position.inMilliseconds;
        final next = teacherRunCursor(
          entries: entries,
          start: start,
          end: end,
          cursor: cursor,
          positionMs: ms,
        );
        if (next != cursor) {
          cursor = next;
          _activeItemId = entries[cursor].itemId;
          _activeSequenceIndex = cursor;
          notifyListeners();
        }
        if (teacherRunShouldStop(last: entries[end - 1], positionMs: ms)) {
          playback.complete();
        }
      });
      await _player.play(
        AssetSource(entries[start].assetPath!),
        position: entries[start].start,
      );
      await playback.future;
      if (token == _token) await _player.stop();
    } finally {
      await stopSub?.cancel();
      await doneSub?.cancel();
      if (identical(_playback, playback)) _playback = null;
    }
    return end;
  }

  /// One TTS fallback line inside a sequence. Position stays unknown.
  Future<void> _speakEntryText(String text, String? voiceId, int token) async {
    final cleaned = sanitizeSpeakText(text);
    if (cleaned.isEmpty) return;
    if (usesBackend) {
      try {
        final sound = await _backendClient.resolve(
          text: cleaned,
          gear: ttsGearForRate(_rate),
          voiceId: voiceId,
        );
        if (token != _token) return;
        await _playUrl(sound.uri, token);
        return;
      } catch (_) {
        if (token != _token) return;
        // Fall through to MiniMax direct / device below.
      }
    }
    if (usesMinimax) {
      try {
        final bytes = await _client.synthesize(
          text: cleaned,
          speed: minimaxSpeedForRate(_rate),
          voiceId: voiceId,
        );
        if (token != _token) return;
        await _play(bytes, token);
        return;
      } catch (_) {
        if (token != _token) return;
        if (!_device.isCantoneseAvailable) {
          _setStatus('合成发音失败，且设备没有粤语语音。', warning: true);
          notifyListeners();
          return;
        }
      }
    }
    if (token != _token) return;
    _usingDevice = true;
    await _device.speak(SpeechUtterance(text: cleaned), itemId: _activeItemId);
  }

  void _clearSequence() {
    _activeSequenceId = null;
    _activeSequenceIndex = 0;
    _activeSequenceTotal = 0;
    _positionMs.value = null;
  }

  Future<void> _playSource(Source source, int token) async {
    final playback = Completer<void>();
    _playback = playback;
    final subscription = _player.onPlayerComplete.listen((_) {
      if (!playback.isCompleted) playback.complete();
    });
    try {
      await _player.play(source);
      await playback.future;
    } finally {
      await subscription.cancel();
      if (identical(_playback, playback)) _playback = null;
    }
    if (token != _token) return;
  }

  Future<void> _haltPlayback() async {
    final playback = _playback;
    if (playback != null && !playback.isCompleted) playback.complete();
    await _player.stop();
    await _device.stop();
  }

  void _onDevice() {
    if (!_usingDevice) return;
    _speaking = _device.isSpeaking;
    _activeItemId = _device.activeItemId;
    notifyListeners();
  }

  void _setStatus(String? message, {required bool warning}) {
    _status = message;
    _statusWarning = warning && message != null;
  }

  void _syncAvailability() {
    if (!_onlineEnabled) {
      _available = _device.isCantoneseAvailable;
      _setStatus(
        _device.isCantoneseAvailable
            ? '已切换为系统离线语音（zh-HK），不使用网络。'
            : _device.statusMessage,
        warning: !_available,
      );
      return;
    }
    if (usesBackend) {
      _available = true;
      _setStatus('已连接语音后端，按课文汉字朗读。', warning: false);
      return;
    }
    if (usesMinimax) {
      _available = true;
      _setStatus('已使用 MiniMax 粤语语音，按课文汉字朗读。', warning: false);
      return;
    }
    _available = _device.isCantoneseAvailable;
    _setStatus(
      _device.isCantoneseAvailable
          ? '未配置在线语音，正在使用设备粤语语音（zh-HK）。'
          : _device.statusMessage,
      warning: true,
    );
  }
}
