/// One ruby column: Cantonese [text] with the Jyutping [reading] above it.
///
/// [start] and [end] are UTF-16 offsets into the original sentence, so
/// glossary matches and blanks can be found again after grouping.
class RubyPiece {
  const RubyPiece({
    required this.text,
    required this.reading,
    required this.start,
    required this.end,
  });

  final String text;
  final String reading;
  final int start;
  final int end;
}

/// A span that must stay one column, with a known reading.
///
/// Blanks use this. A filled month `10` is one syllable `sap6`, which a
/// digit-by-digit walk would split wrong.
class RubyAnchor {
  const RubyAnchor({required this.start, required this.end, this.reading = ''});

  final int start;
  final int end;
  final String reading;
}

/// Inclusive-exclusive range of characters that share one ruby label.
/// Glossary matches are the usual source: 唔該 is one word, not two.
class RubySpan {
  const RubySpan({required this.start, required this.end});

  final int start;
  final int end;
}

final _han = RegExp(r'\p{Script=Han}', unicode: true);
final _wordChar = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
final _syllable = RegExp(r'^[A-Za-z]+[1-6]$');
final _tokenPattern = RegExp(
  r"[A-Za-z]+[1-6]|[\p{L}\p{N}]+|_{2,}|[^\s]",
  unicode: true,
);

List<String> _tokenize(String jyutping) {
  return [
    for (final match in _tokenPattern.allMatches(jyutping)) match.group(0)!,
  ];
}

bool _isSyllable(String token) => _syllable.hasMatch(token);

bool _isPunctToken(String token) {
  if (_isSyllable(token) || token.startsWith('_')) return false;
  return !RegExp(r'^[\p{L}\p{N}]+$', unicode: true).hasMatch(token);
}

bool _isHan(String char) => _han.hasMatch(char);

bool _isWordChar(String char) => !_isHan(char) && _wordChar.hasMatch(char);

String _shownReading(String reading) {
  return _tokenize(reading).where(_isSyllable).join(' ');
}

/// Splits [text] into words with a Jyutping label on each.
///
/// One syllable per Han character. A Latin run takes the matching token
/// (`Weekend`, `K`) and hides it when it only repeats the word. A digit
/// run takes one syllable per digit (`7-11` → `chat1 sap6 jat1`).
/// Punctuation sticks to the previous word and is not a syllable.
/// [anchors] are consumed as a single column. [groups] join the columns
/// inside each range into one word.
List<RubyPiece> layoutRuby({
  required String text,
  required String jyutping,
  List<RubyAnchor> anchors = const [],
  List<RubySpan> groups = const [],
}) {
  if (text.isEmpty) return const [];
  final tokens = _tokenize(jyutping);
  final atoms = <_Atom>[];
  final sorted = [...anchors]..sort((a, b) => a.start.compareTo(b.start));
  var cursor = 0;
  var ti = 0;
  for (final anchor in sorted) {
    if (anchor.end <= anchor.start) continue;
    if (anchor.start < cursor || anchor.end > text.length) continue;
    if (anchor.start > cursor) {
      ti = _alignSlice(
        slice: text.substring(cursor, anchor.start),
        base: cursor,
        tokens: tokens,
        tokenIndex: ti,
        atoms: atoms,
      );
    }
    ti = _consumeExpected(tokens, ti, _tokenize(anchor.reading));
    atoms.add(
      _Atom(
        text: text.substring(anchor.start, anchor.end),
        reading: _shownReading(anchor.reading),
        start: anchor.start,
        end: anchor.end,
        anchor: true,
      ),
    );
    cursor = anchor.end;
  }
  if (cursor < text.length) {
    ti = _alignSlice(
      slice: text.substring(cursor),
      base: cursor,
      tokens: tokens,
      tokenIndex: ti,
      atoms: atoms,
    );
  }
  _appendLeftover(atoms, tokens, ti);
  return _group(atoms, groups);
}

int _consumeExpected(List<String> tokens, int ti, List<String> expected) {
  var i = ti;
  for (final want in expected) {
    while (i < tokens.length && _isPunctToken(tokens[i])) {
      i++;
    }
    if (i < tokens.length && tokens[i].toLowerCase() == want.toLowerCase()) {
      i++;
      continue;
    }
    return ti;
  }
  return i;
}

int _alignSlice({
  required String slice,
  required int base,
  required List<String> tokens,
  required int tokenIndex,
  required List<_Atom> atoms,
}) {
  var i = 0;
  var ti = tokenIndex;
  while (i < slice.length) {
    final next = _advance(slice, i);
    final char = slice.substring(i, next);
    if (_isHan(char)) {
      var reading = '';
      if (ti < tokens.length && _isSyllable(tokens[ti])) {
        reading = tokens[ti];
        ti++;
      }
      atoms.add(
        _Atom(text: char, reading: reading, start: base + i, end: base + next),
      );
      i = next;
      continue;
    }
    if (char == '_') {
      var end = next;
      while (end < slice.length && slice.startsWith('_', end)) {
        end++;
      }
      final run = slice.substring(i, end);
      if (ti < tokens.length && tokens[ti] == run) ti++;
      atoms.add(
        _Atom(text: run, reading: '', start: base + i, end: base + end),
      );
      i = end;
      continue;
    }
    if (_isWordChar(char)) {
      var end = next;
      while (end < slice.length) {
        final step = _advance(slice, end);
        final current = slice.substring(end, step);
        if (_isWordChar(current)) {
          end = step;
          continue;
        }
        if (current == '-' && step < slice.length) {
          final afterEnd = _advance(slice, step);
          final after = slice.substring(step, afterEnd);
          if (_isWordChar(after)) {
            end = step;
            continue;
          }
        }
        break;
      }
      final run = slice.substring(i, end);
      final taken = _takeRunReading(run, tokens, ti);
      atoms.add(
        _Atom(text: run, reading: taken.$1, start: base + i, end: base + end),
      );
      ti = taken.$2;
      i = end;
      continue;
    }
    if (ti < tokens.length && _isPunctToken(tokens[ti])) ti++;
    atoms.add(
      _Atom(
        text: char,
        reading: '',
        start: base + i,
        end: base + next,
        punct: true,
      ),
    );
    i = next;
  }
  return ti;
}

/// UTF-16 index of the next code point. Astral characters (𨋢) are two units.
int _advance(String text, int index) {
  final unit = text.codeUnitAt(index);
  final surrogate = unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length;
  return index + (surrogate ? 2 : 1);
}

(String, int) _takeRunReading(String run, List<String> tokens, int ti) {
  if (ti >= tokens.length) return ('', ti);
  if (tokens[ti].toLowerCase() == run.toLowerCase()) {
    final token = tokens[ti];
    return (_isSyllable(token) ? token : '', ti + 1);
  }
  final digits = RegExp(r'\d').allMatches(run).length;
  if (digits > 0 &&
      ti + digits <= tokens.length &&
      List.generate(digits, (k) => tokens[ti + k]).every(_isSyllable)) {
    return (tokens.sublist(ti, ti + digits).join(' '), ti + digits);
  }
  if (_isSyllable(tokens[ti])) return (tokens[ti], ti + 1);
  return ('', ti);
}

void _appendLeftover(List<_Atom> atoms, List<String> tokens, int ti) {
  final rest = tokens.sublist(ti).where(_isSyllable).join(' ');
  if (rest.isEmpty) return;
  for (var i = atoms.length - 1; i >= 0; i--) {
    if (atoms[i].punct) continue;
    final atom = atoms[i];
    atoms[i] = atom.copy(
      reading: atom.reading.isEmpty ? rest : '${atom.reading} $rest',
    );
    return;
  }
}

List<RubyPiece> _group(List<_Atom> atoms, List<RubySpan> groups) {
  final sorted = [...groups]..sort((a, b) => a.start.compareTo(b.start));
  final out = <RubyPiece>[];
  var i = 0;
  while (i < atoms.length) {
    final atom = atoms[i];
    if (atom.punct) {
      out.add(atom.toPiece());
      i++;
      continue;
    }
    RubySpan? group;
    if (!atom.anchor) {
      for (final candidate in sorted) {
        if (candidate.start <= atom.start && atom.start < candidate.end) {
          group = candidate;
          break;
        }
      }
    }
    final merged = <_Atom>[atom];
    i++;
    if (group != null) {
      while (i < atoms.length &&
          !atoms[i].anchor &&
          atoms[i].start < group.end) {
        merged.add(atoms[i]);
        i++;
      }
    }
    var piece = _join(merged);
    while (i < atoms.length && atoms[i].punct) {
      piece = RubyPiece(
        text: piece.text + atoms[i].text,
        reading: piece.reading,
        start: piece.start,
        end: atoms[i].end,
      );
      i++;
    }
    out.add(piece);
  }
  return out;
}

RubyPiece _join(List<_Atom> atoms) {
  return RubyPiece(
    text: atoms.map((atom) => atom.text).join(),
    reading: atoms
        .map((atom) => atom.reading)
        .where((reading) => reading.isNotEmpty)
        .join(' '),
    start: atoms.first.start,
    end: atoms.last.end,
  );
}

class _Atom {
  const _Atom({
    required this.text,
    required this.reading,
    required this.start,
    required this.end,
    this.punct = false,
    this.anchor = false,
  });

  final String text;
  final String reading;
  final int start;
  final int end;
  final bool punct;
  final bool anchor;

  _Atom copy({String? reading}) {
    return _Atom(
      text: text,
      reading: reading ?? this.reading,
      start: start,
      end: end,
      punct: punct,
      anchor: anchor,
    );
  }

  RubyPiece toPiece() {
    return RubyPiece(text: text, reading: reading, start: start, end: end);
  }
}
