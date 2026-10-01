import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'device_tts_service.dart';
import 'minimax_config.dart';
import 'minimax_tts_client.dart';
import 'speech_service.dart';

/// Uses MiniMax when a debug key is configured, otherwise the device voice.
/// A failed MiniMax request falls back to the device voice when that exists.
class CantoneseSpeechService extends SpeechService {
  CantoneseSpeechService({
    required DeviceTtsService device,
    required MinimaxConfig config,
    MinimaxTtsClient? client,
    AudioPlayer? player,
  }) : _device = device,
       _config = config,
       _client = client ?? MinimaxTtsClient(config: config),
       _player = player ?? AudioPlayer();

  final DeviceTtsService _device;
  final MinimaxConfig _config;
  final MinimaxTtsClient _client;
  final AudioPlayer _player;

  bool _ready = false;
  bool _available = false;
  bool _speaking = false;
  bool _usingDevice = false;
  String? _status;
  String? _activeItemId;
  String? _activeSequenceId;
  int _activeSequenceIndex = 0;
  int _activeSequenceTotal = 0;
  final ValueNotifier<int?> _positionMs = ValueNotifier<int?>(null);
  double _rate = 0.42;
  int _token = 0;
  Completer<void>? _playback;

  bool get usesMinimax => !kIsWeb && _config.isConfigured;

  @override
  bool get isReady => _ready;

  @override
  bool get isCantoneseAvailable => _available;

  @override
  bool get isSpeaking => _speaking;

  @override
  String? get statusMessage => _status;

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
          _status = 'MiniMax 发音失败：$error';
          notifyListeners();
          return;
        }
        _status = 'MiniMax 发音失败，已改用设备语音。';
        notifyListeners();
      }
    }

    if (token != _token) return;
    _usingDevice = true;
    await _device.speakSequence(utterances, itemId: itemId);
  }

  @override
  Future<void> playRecordings(List<String> assetPaths, {String? itemId}) async {    final token = ++_token;
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
      _status = '课上录音播放失败：$error';
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
      await _player.play(AssetSource(assetPath));
      await _player.seek(start);
      await playback.future;
      if (token == _token) await _player.stop();
    } catch (error) {
      if (token != _token) return;
      _status = '老师原音播放失败：$error';
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
      for (var i = 0; i < entries.length; i++) {
        if (token != _token) return;
        final entry = entries[i];
        _activeItemId = entry.itemId;
        _activeSequenceIndex = i;
        _positionMs.value = null;
        notifyListeners();
        if (entry.hasTeacherAudio) {
          _usingDevice = false;
          await _playEntry(
            entry.assetPath!,
            entry.start!,
            entry.end!,
            token,
          );
        } else {
          await _speakEntryText(
            entry.fallbackText,
            entry.voiceId,
            token,
          );
        }
      }
    } catch (error) {
      if (token != _token) return;
      _status = '整段播放失败：$error';
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

  /// One teacher slice inside a sequence. Shares the sequence-level
  /// position subscription; adds a stop watcher that completes playback
  /// shortly after [end].
  Future<void> _playEntry(
    String assetPath,
    Duration start,
    Duration end,
    int token,
  ) async {
    final stopAt = end + const Duration(milliseconds: 250);
    final playback = Completer<void>();
    _playback = playback;
    StreamSubscription<void>? doneSub;
    StreamSubscription<Duration>? stopSub;
    try {
      doneSub = _player.onPlayerComplete.listen((_) {
        if (!playback.isCompleted) playback.complete();
      });
      stopSub = _player.onPositionChanged.listen((position) {
        if (position >= stopAt && !playback.isCompleted) {
          playback.complete();
        }
      });
      await _player.play(AssetSource(assetPath));
      await _player.seek(start);
      await playback.future;
      if (token == _token) await _player.stop();
    } finally {
      await stopSub?.cancel();
      await doneSub?.cancel();
      if (identical(_playback, playback)) _playback = null;
    }
    if (token != _token) return;
  }

  /// One TTS fallback line inside a sequence. Position stays unknown.
  Future<void> _speakEntryText(String text, String? voiceId, int token) async {
    final cleaned = sanitizeSpeakText(text);
    if (cleaned.isEmpty) return;
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
          _status = '合成发音失败，且设备没有粤语语音。';
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

  void _syncAvailability() {
    if (usesMinimax) {
      _available = true;
      _status = '已使用 MiniMax 粤语语音，按课文汉字朗读。';
      return;
    }
    _available = _device.isCantoneseAvailable;
    _status = _device.isCantoneseAvailable
        ? '未配置 MiniMax，正在使用设备粤语语音（zh-HK）。'
        : _device.statusMessage;
  }
}
