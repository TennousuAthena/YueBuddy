class NameSyllable {
  const NameSyllable({required this.character, this.jyutping});

  final String character;
  final String? jyutping;
}

class NameReading {
  const NameReading({required this.name, required this.syllables});

  final String name;
  final List<NameSyllable> syllables;

  bool get isEmpty => syllables.isEmpty;

  bool get hasUnknown => syllables.any((syllable) => syllable.jyutping == null);

  String get jyutping {
    return syllables
        .map((syllable) => syllable.jyutping ?? syllable.character)
        .join(' ');
  }

  String get speakText => name;
}

NameReading readName(String rawName, Map<String, String> readings) {
  final name = rawName.trim();
  final syllables = <NameSyllable>[];
  for (final rune in name.runes) {
    final character = String.fromCharCode(rune);
    if (character.trim().isEmpty) continue;
    syllables.add(
      NameSyllable(character: character, jyutping: readings[character]),
    );
  }
  return NameReading(name: name, syllables: syllables);
}
