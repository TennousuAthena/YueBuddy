import 'package:flutter/foundation.dart';

/// One thing to say. Speech reads [text] as written.
/// [voiceId] selects a MiniMax voice for dialogue roles; other lines use the default.
class SpeechUtterance {
  const SpeechUtterance({required this.text, this.voiceId});

  final String text;
  final String? voiceId;
}

/// One entry of a dialogue sequence: teacher recording first, device/TTS
/// [fallbackText] when the slice is missing (or TTS-only backends).
class SequenceEntry {
  const SequenceEntry({
    required this.itemId,
    required this.fallbackText,
    this.voiceId,
    this.assetPath,
    this.start,
    this.end,
  });

  final String itemId;
  final String fallbackText;
  final String? voiceId;
  final String? assetPath;
  final Duration? start;
  final Duration? end;

  bool get hasTeacherAudio =>
      assetPath != null && start != null && end != null && end! > start!;
}

/// Replaceable speech backend. Debug builds may call MiniMax directly;
/// release should go through the app's own backend instead.
abstract class SpeechService extends ChangeNotifier {
  bool get isReady;
  bool get isCantoneseAvailable;
  bool get isSpeaking;
  String? get statusMessage;
  String? get activeItemId;

  Future<void> initialize();
  Future<void> speak(SpeechUtterance utterance, {String? itemId});
  Future<void> speakSequence(
    List<SpeechUtterance> utterances, {
    String? itemId,
  });
  Future<void> playRecordings(List<String> assetPaths, {String? itemId});
  Future<void> playSegment({
    required String assetPath,
    required Duration start,
    required Duration end,
    String? itemId,
  });
  Future<void> stop();
  void updateSpeechRate(double rate);

  /// Plays [entries] in order for dialogue follow-along: teacher slices
  /// where available, TTS fallback otherwise. Implementations update
  /// [activeItemId] per entry so the UI can highlight the current line,
  /// and publish progress below for the progress bar + karaoke.
  Future<void> playSequence(List<SequenceEntry> entries, {String? itemId});

  /// Sequence id passed to the running [playSequence], null when idle.
  String? get activeSequenceId;

  /// 0-based index of the entry currently playing.
  int get activeSequenceIndex;

  /// Total entries of the running sequence (0 when idle).
  int get activeSequenceTotal;

  /// Latest audio-player position in recording-absolute milliseconds, or
  /// null when unknown (TTS entries, idle). Updated outside
  /// [notifyListeners] — karaoke widgets must listen to it directly so
  /// position ticks don't rebuild the whole list.
  ValueListenable<int?> get sequencePositionMs;
}
