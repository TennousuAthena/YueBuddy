import 'dart:convert';

import 'package:flutter/services.dart';

import '../lessons/domain/lesson_models.dart';

class GlossaryEntry {
  const GlossaryEntry({
    required this.id,
    required this.term,
    required this.mandarin,
    this.jyutping,
  });

  final String id;
  final String term;
  final String mandarin;
  final String? jyutping;

  factory GlossaryEntry.fromJson(Map<String, dynamic> json) {
    final jyutping = json['jyutping'] as String?;
    return GlossaryEntry(
      id: json['id'] as String,
      term: json['term'] as String,
      mandarin: json['mandarin'] as String,
      jyutping: jyutping == null || jyutping.trim().isEmpty ? null : jyutping,
    );
  }

  /// One explanation can list extra spellings, such as 而家 / 宜家.
  static List<GlossaryEntry> expandJson(Map<String, dynamic> json) {
    final entry = GlossaryEntry.fromJson(json);
    final aliases = json['aliases'];
    if (aliases is! List) return [entry];
    final extra = <GlossaryEntry>[];
    for (final alias in aliases) {
      if (alias is! String) continue;
      final term = alias.trim();
      if (term.isEmpty || term == entry.term) continue;
      extra.add(
        GlossaryEntry(
          id: '${entry.id}__$term',
          term: term,
          mandarin: entry.mandarin,
          jyutping: entry.jyutping,
        ),
      );
    }
    return [entry, ...extra];
  }
}

class GlossaryMatch {
  const GlossaryMatch({required this.start, required this.entry});

  final int start;
  final GlossaryEntry entry;

  int get end => start + entry.term.length;
}

/// Cantonese terms explained in Mandarin. Longer terms win when they overlap.
///
/// [entries.json] keeps Hong Kong usage, spoken variants, and words that only
/// show up inside sentences. [entriesFromCourse] adds lesson vocabulary on top,
/// and the hand-written entry wins when both define the same term.
class Glossary {
  const Glossary._(this.entries, this._byLength);

  const Glossary.empty() : entries = const [], _byLength = const [];

  factory Glossary(List<GlossaryEntry> entries) {
    final seen = <String>{};
    final unique = <GlossaryEntry>[];
    for (final entry in entries) {
      if (entry.term.isEmpty || !seen.add(entry.term)) continue;
      unique.add(entry);
    }
    final byLength = [...unique]
      ..sort((a, b) {
        final bySize = b.term.length.compareTo(a.term.length);
        if (bySize != 0) return bySize;
        return a.term.compareTo(b.term);
      });
    return Glossary._(List.unmodifiable(unique), List.unmodifiable(byLength));
  }

  factory Glossary.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'] as List<dynamic>? ?? const [];
    return Glossary([
      for (final item in raw)
        ...GlossaryEntry.expandJson(item as Map<String, dynamic>),
    ]);
  }

  static Future<Glossary> loadAsset({
    String asset = 'assets/glossary/entries.json',
    AssetBundle? bundle,
    Iterable<Lesson> course = const [],
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(asset);
    final curated = Glossary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return Glossary([...curated.entries, ...entriesFromCourse(course)]);
  }

  /// Vocabulary and short expressions from lesson files.
  ///
  /// Tone, initial, and final drills are left out, so a single example
  /// character does not underline every sentence. Full dialogue lines are
  /// left out too; words inside them come from the curated list or from
  /// shorter lesson entries.
  static List<GlossaryEntry> entriesFromCourse(Iterable<Lesson> lessons) {
    final entries = <GlossaryEntry>[];
    for (final lesson in lessons) {
      for (final module in lesson.modules) {
        for (final item in module.items) {
          entries.addAll(_entriesFromItem(item));
        }
      }
    }
    return entries;
  }

  final List<GlossaryEntry> entries;
  final List<GlossaryEntry> _byLength;

  List<GlossaryMatch> findMatches(String text) {
    if (text.isEmpty || _byLength.isEmpty) return const [];
    final matches = <GlossaryMatch>[];
    var index = 0;
    while (index < text.length) {
      GlossaryEntry? hit;
      for (final entry in _byLength) {
        if (text.startsWith(entry.term, index)) {
          hit = entry;
          break;
        }
      }
      if (hit == null) {
        index++;
        continue;
      }
      matches.add(GlossaryMatch(start: index, entry: hit));
      index += hit.term.length;
    }
    return matches;
  }
}

const _drillSections = {'聲調', '聲母', '韻母', '發音對比', '數字訣', '其他口訣'};

final _sentenceBreak = RegExp('[。？?，、]|___|__|……|…');

bool _isDrillGloss(String mandarin) {
  return mandarin.contains('声母') ||
      mandarin.contains('韵母') ||
      mandarin.contains('聲母') ||
      mandarin.contains('韻母') ||
      mandarin.contains('短音') ||
      mandarin.contains('闭口韵') ||
      mandarin.contains('閉口韻') ||
      mandarin.contains('常对应') ||
      mandarin.contains('常對應') ||
      RegExp('第[一二三四五六七八九]声').hasMatch(mandarin);
}

String _gloss(LessonItem item) {
  final mandarin = item.mandarin.trim();
  final note = item.note?.trim();
  if (note == null || note.isEmpty || mandarin.contains(note)) return mandarin;
  return '$mandarin。$note';
}

bool _skipSurface(
  String term,
  String mandarin, {
  required bool keepShortNumber,
}) {
  if (term.isEmpty) return true;
  if (term.length == 1 && mandarin.trim() == term) return true;
  if (!keepShortNumber &&
      term.length == 1 &&
      RegExp(r'^[0-9]+$').hasMatch(mandarin.trim())) {
    return true;
  }
  return false;
}

List<GlossaryEntry> _entriesFromItem(LessonItem item) {
  if (item.type != 'vocab' && item.type != 'phrase') return const [];
  if (_drillSections.contains(item.section) || _isDrillGloss(item.mandarin)) {
    return const [];
  }
  final spokenNumber =
      item.cantonese.contains('／') || item.cantonese.contains('/');
  final surfaces = item.type == 'vocab'
      ? _vocabSurfaces(item.cantonese, item.jyutping)
      : _phraseSurfaces(item.cantonese, item.jyutping);
  final gloss = _gloss(item);
  final entries = <GlossaryEntry>[];
  for (var i = 0; i < surfaces.length; i++) {
    final surface = surfaces[i];
    if (_skipSurface(
      surface.term,
      item.mandarin,
      keepShortNumber: spokenNumber,
    )) {
      continue;
    }
    entries.add(
      GlossaryEntry(
        id: i == 0 ? item.id : '${item.id}-$i',
        term: surface.term,
        mandarin: gloss,
        jyutping: surface.jyutping,
      ),
    );
  }
  return entries;
}

class _Surface {
  const _Surface(this.term, this.jyutping);

  final String term;
  final String? jyutping;
}

List<_Surface> _phraseSurfaces(String cantonese, String jyutping) {
  if (_sentenceBreak.hasMatch(cantonese)) return const [];
  final term = cantonese.replaceAll(RegExp(r'[！!]+$'), '').trim();
  if (term.isEmpty || term.length > 12 || _sentenceBreak.hasMatch(term)) {
    return const [];
  }
  return [_Surface(term, _clean(jyutping))];
}

List<_Surface> _vocabSurfaces(String cantonese, String jyutping) {
  final surfaces = <_Surface>[];
  for (final surface in _slashSurfaces(cantonese, jyutping)) {
    surfaces.addAll(_parenSurfaces(surface.term, surface.jyutping));
  }
  return surfaces;
}

List<String> _splitSlash(String text) {
  return text
      .split(RegExp(r'[/／]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

/// `今個／呢個禮拜` shares the ending 禮拜. Only treat it that way when every
/// alternative ends on the same character, so `冰室／茶餐廳` stays two shops.
List<_Surface> _slashSurfaces(String cantonese, String jyutping) {
  final parts = _splitSlash(cantonese);
  final readings = _splitSlash(jyutping);
  if (parts.length < 2) {
    return [
      _Surface(
        parts.isEmpty ? cantonese.trim() : parts.single,
        _clean(jyutping),
      ),
    ];
  }
  final heads = parts.sublist(0, parts.length - 1);
  final last = parts.last;
  final headLength = heads.first.length;
  final marker = heads.first[headLength - 1];
  final shared =
      heads.every(
        (head) => head.length == headLength && head[headLength - 1] == marker,
      ) &&
      last.length > headLength &&
      last[headLength - 1] == marker;
  if (!shared) {
    return [
      for (var i = 0; i < parts.length; i++)
        _Surface(parts[i], i < readings.length ? readings[i] : null),
    ];
  }
  final suffix = last.substring(headLength);
  final terms = [...heads.map((head) => '$head$suffix'), last];
  final readingsForTerms = _sharedReadings(readings, suffix.length);
  return [
    for (var i = 0; i < terms.length; i++)
      _Surface(
        terms[i],
        readingsForTerms != null && i < readingsForTerms.length
            ? readingsForTerms[i]
            : null,
      ),
  ];
}

List<String>? _sharedReadings(List<String> readings, int suffixChars) {
  if (readings.length < 2 || suffixChars <= 0) return null;
  final syllables = [
    for (final reading in readings)
      reading.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList(),
  ];
  final last = syllables.last;
  if (last.length <= suffixChars) return null;
  final suffix = last.sublist(last.length - suffixChars).join(' ');
  final lastHead = last.sublist(0, last.length - suffixChars).join(' ');
  return [
    for (var i = 0; i < syllables.length - 1; i++)
      '${syllables[i].join(' ')} $suffix',
    '$lastHead $suffix'.trim(),
  ];
}

final _parens = RegExp(r'[（(]([^）)]+)[）)]');

List<_Surface> _parenSurfaces(String term, String? jyutping) {
  final aliases = <String>[];
  final aliasReadings = <String>[];
  final main = term.replaceAllMapped(_parens, (match) {
    aliases.add(match.group(1)!.trim());
    return '';
  }).trim();
  var mainReading = jyutping;
  if (jyutping != null) {
    mainReading = jyutping
        .replaceAllMapped(_parens, (match) {
          aliasReadings.add(match.group(1)!.trim());
          return '';
        })
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
  final surfaces = <_Surface>[];
  if (main.isNotEmpty) surfaces.add(_Surface(main, _clean(mainReading)));
  for (var i = 0; i < aliases.length; i++) {
    if (aliases[i].isEmpty) continue;
    surfaces.add(
      _Surface(
        aliases[i],
        i < aliasReadings.length ? _clean(aliasReadings[i]) : null,
      ),
    );
  }
  return surfaces;
}

String? _clean(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
