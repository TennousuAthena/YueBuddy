import 'speech_service.dart';

/// How long to keep the file going after the last slice, so the final
/// syllable is not cut off. Earlier slices hand off at the next start,
/// so this tail never replays the following sentence.
const teacherRunTail = Duration(milliseconds: 180);

/// Exclusive end index of teacher slices that share [entries][start]'s
/// recording, beginning at [start].
int teacherRunEnd(List<SequenceEntry> entries, int start) {
  final asset = entries[start].assetPath;
  var end = start + 1;
  while (end < entries.length) {
    final entry = entries[end];
    if (!entry.hasTeacherAudio || entry.assetPath != asset) break;
    end++;
  }
  return end;
}

/// Clip to highlight at [positionMs] inside the half-open run [start, end).
///
/// A pause between slices keeps the previous line until the next slice
/// actually starts, so the recording can play straight through.
int teacherRunCursor({
  required List<SequenceEntry> entries,
  required int start,
  required int end,
  required int cursor,
  required int positionMs,
}) {
  var next = cursor < start || cursor >= end ? start : cursor;
  while (next + 1 < end &&
      positionMs >= entries[next + 1].start!.inMilliseconds) {
    next++;
  }
  return next;
}

/// True once playback has passed the last slice, including [tail].
bool teacherRunShouldStop({
  required SequenceEntry last,
  required int positionMs,
  Duration tail = teacherRunTail,
}) {
  return positionMs >= last.end!.inMilliseconds + tail.inMilliseconds;
}
