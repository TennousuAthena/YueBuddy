import 'lesson_models.dart';

/// Mirrors the python `norm()` used by `tools/align/extract_words.py`:
/// drop everything except unicode letters/digits, then lowercase.
/// The word-timing payload ([WordTiming.text]) is stored in this form, so
/// the app can align timings without knowing the alias table.
String normalizeKaraokeText(String text) {
  return text
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')
      .toLowerCase();
}

/// How many normalized characters of [display] have started singing at
/// [positionMs] (recording-absolute, same clock as [WordTiming]).
///
/// Returns -1 when [timing] doesn't match [display] — the caller falls
/// back to sentence-level highlighting.
int sungCharCount({
  required String display,
  required WordTiming timing,
  required int positionMs,
}) {
  if (!timing.isValid || normalizeKaraokeText(display) != timing.text) {
    return -1;
  }
  var count = 0;
  while (count < timing.length &&
      timing.startsMs[count] <= positionMs) {
    count++;
  }
  return count;
}

/// UTF-16 offset in [text] after the first [sungCount] normalized
/// characters. Glossary spans are split here so sung text can be
/// recolored while keeping vocabulary taps working.
///
/// Assumes BMP text (true for lesson Cantonese/latin/digits); astral
/// characters still resolve to a safe in-string offset.
int karaokeSplitOffset(String text, int sungCount) {
  if (sungCount <= 0) return 0;
  final keep = RegExp(r'[\p{L}\p{N}]', unicode: true);
  var kept = 0;
  var offset = 0;
  for (final rune in text.runes) {
    if (kept >= sungCount) break;
    final char = String.fromCharCode(rune);
    if (keep.hasMatch(char)) kept++;
    offset += char.length;
  }
  return offset.clamp(0, text.length);
}
