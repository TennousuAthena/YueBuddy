import 'package:flutter/foundation.dart';
import 'package:yue_buddy/core/audio/speech_service.dart';

class FakeSpeechService extends SpeechService {
  FakeSpeechService({this.cantoneseAvailable = true});

  bool cantoneseAvailable;
  final List<String> spoken = [];

  bool _speaking = false;
  String? _activeItemId;
  String? _activeSequenceId;
  int _activeSequenceIndex = 0;
  int _activeSequenceTotal = 0;

  /// Tests drive karaoke by setting this directly.
  final ValueNotifier<int?> positionMs = ValueNotifier<int?>(null);

  @override
  bool get isReady => true;

  @override
  bool get isCantoneseAvailable => cantoneseAvailable;

  @override
  bool get isSpeaking => _speaking;

  @override
  String? get statusMessage => cantoneseAvailable ? null : '这台设备没有粤语语音。';

  @override
  bool get statusIsWarning => !cantoneseAvailable;

  @override
  String? get activeItemId => _activeItemId;

  @override
  String? get activeSequenceId => _activeSequenceId;

  @override
  int get activeSequenceIndex => _activeSequenceIndex;

  @override
  int get activeSequenceTotal => _activeSequenceTotal;

  @override
  ValueListenable<int?> get sequencePositionMs => positionMs;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(SpeechUtterance utterance, {String? itemId}) {
    return speakSequence([utterance], itemId: itemId);
  }

  @override
  Future<void> speakSequence(
    List<SpeechUtterance> utterances, {
    String? itemId,
  }) async {
    if (!cantoneseAvailable) return;
    spoken.addAll(utterances.map((utterance) => utterance.text));
    _activeItemId = itemId;
    _speaking = true;
    notifyListeners();
  }

  @override
  Future<void> playRecordings(List<String> assetPaths, {String? itemId}) async {
    spoken.addAll(assetPaths);
    _activeItemId = itemId;
    _speaking = true;
    notifyListeners();
  }

  final List<String> segmentsPlayed = [];

  @override
  Future<void> playSegment({
    required String assetPath,
    required Duration start,
    required Duration end,
    String? itemId,
  }) async {
    segmentsPlayed.add(
      '$assetPath@${start.inMilliseconds}-${end.inMilliseconds}',
    );
    _activeItemId = itemId;
    _speaking = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    _activeItemId = null;
    _activeSequenceId = null;
    _activeSequenceIndex = 0;
    _activeSequenceTotal = 0;
    positionMs.value = null;
    notifyListeners();
  }

  /// Records entry order synchronously so tests can assert the
  /// teacher-first queue without real audio.
  final List<String> sequenceEntries = [];
  final List<String> sequenceAssets = [];

  @override
  Future<void> playSequence(
    List<SequenceEntry> entries, {
    String? itemId,
  }) async {
    sequenceEntries.addAll(entries.map((entry) => entry.itemId));
    sequenceAssets.addAll([
      for (final entry in entries)
        if (entry.hasTeacherAudio) entry.assetPath!,
    ]);
    _activeSequenceId = itemId;
    _activeSequenceTotal = entries.length;
    _speaking = true;
    for (var i = 0; i < entries.length; i++) {
      _activeItemId = entries[i].itemId;
      _activeSequenceIndex = i;
      notifyListeners();
    }
  }

  @override
  void updateSpeechRate(double rate) {}

  @override
  void dispose() {
    positionMs.dispose();
    super.dispose();
  }
}
