import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yue_buddy/features/glossary/glossary.dart';
import 'package:yue_buddy/features/lessons/domain/ruby_jyutping.dart';
import 'package:yue_buddy/features/lessons/presentation/widgets/ruby_line.dart';

void main() {
  List<(String, String)> pairs(String text, String jyutping) {
    return [
      for (final piece in layoutRuby(text: text, jyutping: jyutping))
        (piece.text, piece.reading),
    ];
  }

  test('punctuation sticks to the previous character', () {
    expect(pairs('唔該，我想問', 'm4 goi1, ngo5 soeng2 man6'), [
      ('唔', 'm4'),
      ('該，', 'goi1'),
      ('我', 'ngo5'),
      ('想', 'soeng2'),
      ('問', 'man6'),
    ]);
    expect(pairs('早晨！', 'zou2 san4'), [('早', 'zou2'), ('晨！', 'san4')]);
  });

  test('glossary span is one word and keeps the following comma', () {
    final pieces = layoutRuby(
      text: '唔該，我想問',
      jyutping: 'm4 goi1, ngo5 soeng2 man6',
      groups: const [RubySpan(start: 0, end: 2)],
    );
    expect(
      [for (final piece in pieces) (piece.text, piece.reading)],
      [('唔該，', 'm4 goi1'), ('我', 'ngo5'), ('想', 'soeng2'), ('問', 'man6')],
    );
  });

  test('slash, english, and 7-11 keep their own columns', () {
    expect(pairs('轉左／轉右', 'zyun3 zo2 / zyun3 jau6'), [
      ('轉', 'zyun3'),
      ('左／', 'zo2'),
      ('轉', 'zyun3'),
      ('右', 'jau6'),
    ]);
    expect(pairs('今個Weekend有咩做', 'gam1 go3 Weekend jau5 me1 zou6'), [
      ('今', 'gam1'),
      ('個', 'go3'),
      ('Weekend', ''),
      ('有', 'jau5'),
      ('咩', 'me1'),
      ('做', 'zou6'),
    ]);
    expect(pairs('唱K', 'coeng3 K'), [('唱', 'coeng3'), ('K', '')]);
    expect(pairs('有冇7-11呀？', 'jau5 mou5 chat1 sap6 jat1 aa3'), [
      ('有', 'jau5'),
      ('冇', 'mou5'),
      ('7-11', 'chat1 sap6 jat1'),
      ('呀？', 'aa3'),
    ]);
  });

  test('a filled 10 stays one syllable when anchored', () {
    final pieces = layoutRuby(
      text: '今日係10月1號，星期四。',
      jyutping: 'gam1 jat6 hai6 sap6 jyut6 jat1 hou6, sing1 kei4 sei3.',
      anchors: const [
        RubyAnchor(start: 3, end: 5, reading: 'sap6'),
        RubyAnchor(start: 6, end: 7, reading: 'jat1'),
        RubyAnchor(start: 11, end: 12, reading: 'sei3'),
      ],
    );
    expect(
      [for (final piece in pieces) (piece.text, piece.reading)],
      [
        ('今', 'gam1'),
        ('日', 'jat6'),
        ('係', 'hai6'),
        ('10', 'sap6'),
        ('月', 'jyut6'),
        ('1', 'jat1'),
        ('號，', 'hou6'),
        ('星', 'sing1'),
        ('期', 'kei4'),
        ('四。', 'sei3'),
      ],
    );
  });

  test('an unfilled blank is one column', () {
    final pieces = layoutRuby(
      text: '大家好！我係___。',
      jyutping: 'daai6 gaa1 hou2! ngo5 hai6 ___',
      anchors: const [RubyAnchor(start: 6, end: 9, reading: '___')],
    );
    expect(
      [for (final piece in pieces) (piece.text, piece.reading)],
      [
        ('大', 'daai6'),
        ('家', 'gaa1'),
        ('好！', 'hou2'),
        ('我', 'ngo5'),
        ('係', 'hai6'),
        ('___。', ''),
      ],
    );
  });

  test('an astral character takes one syllable', () {
    expect(pairs('搭𨋢', 'daap3 lip1'), [('搭', 'daap3'), ('𨋢', 'lip1')]);
  });

  testWidgets('a glossary word renders as one ruby column', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RubyLine(
            text: '唔該，我想問',
            jyutping: 'm4 goi1, ngo5 soeng2 man6',
            glossary: Glossary(const [
              GlossaryEntry(id: 'm4-goi1', term: '唔該', mandarin: '请问'),
            ]),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );

    expect(find.text('m4 goi1'), findsOneWidget);
    expect(find.text('唔該，'), findsOneWidget);
    expect(find.text('ngo5'), findsOneWidget);
    final first = tester.getTopLeft(find.text('m4 goi1'));
    final second = tester.getTopLeft(find.text('ngo5'));
    expect((first.dy - second.dy).abs(), lessThan(1));
    expect(second.dx, greaterThan(first.dx));
  });
}
