import '../../onboarding/name_reading.dart';
import 'lesson_models.dart';

/// Blanks in lesson text are runs of 2+ underscores (`__`, `___`).
final RegExp blankPattern = RegExp(r'_{2,}');

const _digitReadings = <String, String>{
  '0': 'ling4',
  '1': 'jat1',
  '2': 'ji6',
  '3': 'saam1',
  '4': 'sei3',
  '5': 'ng5',
  '6': 'luk6',
  '7': 'cat1',
  '8': 'baat3',
  '9': 'gau2',
};

const _weekdayChars = '一二三四五六日';

/// Cantonese number words for 1-31 (months, days of month).
String cantoneseNumber(int n) {
  const digits = [
    'jat1',
    'ji6',
    'saam1',
    'sei3',
    'ng5',
    'luk6',
    'cat1',
    'baat3',
    'gau2',
    'sap6',
  ];
  if (n >= 1 && n <= 10) return digits[n - 1];
  if (n < 20) return 'sap6 ${digits[n - 11]}';
  if (n == 20) return 'ji6 sap6';
  if (n < 30) return 'jaa6 ${digits[n - 21]}';
  if (n == 30) return 'saa1 sap6';
  if (n == 31) return 'saa1 sap6 jat1';
  return '$n';
}

String weekdayChar(DateTime date) => _weekdayChars[date.weekday - 1];

/// One blank with its effective value and position in the display text.
class FilledBlank {
  const FilledBlank({
    required this.index,
    required this.kind,
    required this.value,
    required this.hasOverride,
    required this.start,
    required this.end,
    required this.reading,
  });

  final int index;
  final BlankKind kind;
  final String value;
  final bool hasOverride;
  final int start;
  final int end;

  /// Jyutping for this span. Unfilled blanks keep the underscore run so
  /// ruby layout can skip it as one unit. A filled "10" is `sap6`.
  final String reading;
}

/// A lesson sentence with blanks resolved to display/TTS strings.
class LessonFill {
  const LessonFill({
    required this.displayCantonese,
    required this.displayMandarin,
    required this.displayJyutping,
    required this.speakText,
    required this.blanks,
  });

  final String displayCantonese;
  final String displayMandarin;
  final String displayJyutping;
  final String speakText;
  final List<FilledBlank> blanks;

  bool get hasBlanks => blanks.isNotEmpty;
}

/// Resolves an item's blanks: stored user values win, otherwise computed
/// defaults (onboarding name, today's date in the user's timezone).
/// Unfilled blanks keep their original underscores.
LessonFill resolveLessonFill({
  required LessonItem item,
  required String displayName,
  required DateTime now,
  required Map<String, String> nameReadings,
  required String? Function(int index) stored,
}) {
  final specs = item.fill;
  final matches = blankPattern
      .allMatches(item.cantonese)
      .toList(growable: false);
  final count = matches.length < specs.length ? matches.length : specs.length;

  String defaultFor(BlankKind kind) {
    return switch (kind) {
      BlankKind.name => displayName.trim(),
      BlankKind.phone => '',
      BlankKind.month => '${now.month}',
      BlankKind.day => '${now.day}',
      BlankKind.weekday => weekdayChar(now),
      BlankKind.other => '',
    };
  }

  String jyutpingFor(BlankKind kind, String value) {
    if (value.isEmpty) return '';
    switch (kind) {
      case BlankKind.name:
        return readName(value, nameReadings).jyutping;
      case BlankKind.phone:
        return [
          for (final rune in value.runes)
            _digitReadings[String.fromCharCode(rune)] ??
                String.fromCharCode(rune),
        ].join(' ');
      case BlankKind.month:
      case BlankKind.day:
        final number = int.tryParse(value);
        return number == null ? value : cantoneseNumber(number);
      case BlankKind.weekday:
      case BlankKind.other:
        return nameReadings[value] ?? value;
    }
  }

  final values = <String>[];
  final readings = <String>[];
  final overrides = <bool>[];
  for (var i = 0; i < count; i++) {
    final override = stored(i);
    values.add(override ?? defaultFor(specs[i].kind));
    readings.add(jyutpingFor(specs[i].kind, values[i]));
    overrides.add(override != null);
  }

  String fillLine(String line) {
    final lineMatches = blankPattern.allMatches(line).toList(growable: false);
    final buffer = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < lineMatches.length && i < values.length; i++) {
      final match = lineMatches[i];
      buffer.write(line.substring(cursor, match.start));
      buffer.write(values[i].isEmpty ? match.group(0) : values[i]);
      cursor = match.end;
    }
    buffer.write(line.substring(cursor));
    return buffer.toString();
  }

  String fillJyutpingLine(String line) {
    final lineMatches = blankPattern.allMatches(line).toList(growable: false);
    final buffer = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < lineMatches.length && i < readings.length; i++) {
      final match = lineMatches[i];
      buffer.write(line.substring(cursor, match.start));
      buffer.write(readings[i].isEmpty ? match.group(0) : readings[i]);
      cursor = match.end;
    }
    buffer.write(line.substring(cursor));
    return buffer.toString();
  }

  final displayCantonese = fillLine(item.cantonese);
  final blanks = <FilledBlank>[];
  {
    // Rebuild the display text while tracking offsets: blank positions
    // for tappable spans.
    final buffer = StringBuffer();
    var cursor = 0;
    var delta = 0;
    for (var i = 0; i < matches.length && i < values.length; i++) {
      final match = matches[i];
      buffer.write(item.cantonese.substring(cursor, match.start));
      final shown = values[i].isEmpty ? match.group(0)! : values[i];
      final start = match.start + delta;
      buffer.write(shown);
      delta += shown.length - (match.end - match.start);
      blanks.add(
        FilledBlank(
          index: i,
          kind: specs[i].kind,
          value: values[i],
          hasOverride: overrides[i],
          start: start,
          end: start + shown.length,
          reading: values[i].isEmpty ? shown : readings[i],
        ),
      );
      cursor = match.end;
    }
    buffer.write(item.cantonese.substring(cursor));
    assert(buffer.toString() == displayCantonese);
  }

  return LessonFill(
    displayCantonese: displayCantonese,
    displayMandarin: fillLine(item.mandarin),
    displayJyutping: fillJyutpingLine(item.jyutping),
    speakText: displayCantonese,
    blanks: List.unmodifiable(blanks),
  );
}
