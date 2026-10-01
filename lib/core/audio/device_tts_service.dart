import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speech_service.dart';
import 'tts_locale.dart';

class DeviceTtsService extends SpeechService {
  DeviceTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;
  bool _available = false;
  bool _speaking = false;
  String? _status;
  String? _activeItemId;
  String? _activeSequenceId;
  int _activeSequenceIndex = 0;
  int _activeSequenceTotal = 0;
  final ValueNotifier<int?> _positionMs = ValueNotifier<int?>(null);
  double _rate = 0.42;

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

  /// Device TTS never reports word positions; karaoke stays sentence-level.
  @override
  ValueListenable<int?> get sequencePositionMs => _positionMs;

  @override
  Future<void> initialize() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    await _tts.setSpeechRate(_rate);

    final languages = await _tts.getLanguages;
    final locale = pickCantoneseLocale(
      languages is Iterable ? languages : const <String>[],
    );

    if (locale == null) {
      _available = false;
      _status = cantoneseUnavailableMessage;
    } else {
      final result = await _tts.setLanguage(locale);
      _available = result == 1 || result == true || result == '1';
      _status = _available ? null : cantoneseUnavailableMessage;
    }

    _tts.setStartHandler(() {
      _speaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
      _activeItemId = null;
      notifyListeners();
    });
    _tts.setCancelHandler(() {
      _speaking = false;
      _activeItemId = null;
      notifyListeners();
    });
    _tts.setErrorHandler((message) {
      _speaking = false;
      _activeItemId = null;
      _status = '朗读失败：$message';
      notifyListeners();
    });

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
    if (!_available) return;
    await stop();
    _activeItemId = itemId;
    notifyListeners();
    for (final utterance in utterances) {
      final cleaned = sanitizeSpeakText(utterance.text);
      if (cleaned.isEmpty) continue;
      _speaking = true;
      notifyListeners();
      await _tts.setSpeechRate(_rate);
      await _tts.speak(cleaned);
    }
    _speaking = false;
    _activeItemId = null;
    notifyListeners();
  }

  @override
  Future<void> playRecordings(
    List<String> assetPaths, {
    String? itemId,
  }) async {}

  /// Device TTS cannot play audio-asset slices; the composite
  /// [CantoneseSpeechService] handles those via its audio player.
  @override
  Future<void> playSegment({
    required String assetPath,
    required Duration start,
    required Duration end,
    String? itemId,
  }) async {}

  /// TTS-only sequence: every entry falls back to its text, with the
  /// active item advancing per line for sentence-level highlighting.
  @override
  Future<void> playSequence(
    List<SequenceEntry> entries, {
    String? itemId,
  }) async {
    if (!_available) return;
    await stop();
    if (entries.isEmpty) return;
    _activeSequenceId = itemId;
    _activeSequenceTotal = entries.length;
    _activeSequenceIndex = 0;
    _speaking = true;
    notifyListeners();
    for (var i = 0; i < entries.length; i++) {
      final cleaned = sanitizeSpeakText(entries[i].fallbackText);
      if (cleaned.isEmpty) continue;
      _activeItemId = entries[i].itemId;
      _activeSequenceIndex = i;
      notifyListeners();
      await _tts.speak(cleaned);
    }
    _speaking = false;
    _activeItemId = null;
    _activeSequenceId = null;
    _activeSequenceIndex = 0;
    _activeSequenceTotal = 0;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _speaking = false;
    _activeItemId = null;
    _activeSequenceId = null;
    _activeSequenceIndex = 0;
    _activeSequenceTotal = 0;
    notifyListeners();
  }

  @override
  void updateSpeechRate(double rate) {
    _rate = rate.clamp(0.2, 0.8);
    _tts.setSpeechRate(_rate);
  }

  @override
  void dispose() {
    _positionMs.dispose();
    super.dispose();
  }
}

String sanitizeSpeakText(String text) {
  return text
      .replaceAll('___', ' ')
      .replaceAll('__', ' ')
      .replaceAll('……', ' ')
      .replaceAll('…', ' ')
      .replaceAll(RegExp(r'_+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
