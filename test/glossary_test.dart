import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yue_buddy/features/glossary/glossary.dart';
import 'package:yue_buddy/features/glossary/glossary_text.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';

void main() {
  test('longer terms win and each word is marked once', () {
    final glossary = Glossary([
      const GlossaryEntry(id: 'tea', term: '茶', mandarin: '茶'),
      const GlossaryEntry(id: 'cafe', term: '茶餐廳', mandarin: '茶餐厅'),
      const GlossaryEntry(id: 'dine', term: '堂食', mandarin: '在店里吃'),
    ]);

    final matches = glossary.findMatches('去茶餐廳堂食');
    expect(matches.map((match) => match.entry.term).toList(), ['茶餐廳', '堂食']);
    expect(matches.map((match) => match.start).toList(), [1, 4]);
  });

  test('course vocabulary is merged and spoken variants stay tappable', () {
    final glossary = _mergedGlossary();
    expect(glossary.findMatches('凍檸茶少甜少冰').map((m) => m.entry.term), [
      '凍檸茶',
      '少甜',
      '少冰',
    ]);
    expect(glossary.findMatches('宜家去邊度').map((m) => m.entry.term), [
      '宜家',
      '邊度',
    ]);
    expect(glossary.findMatches('边度').map((m) => m.entry.term), ['边度']);
    expect(glossary.findMatches('你食先').map((m) => m.entry.term), ['你食先']);
    expect(glossary.entries.any((entry) => entry.term == '走青'), isTrue);
    expect(glossary.entries.any((entry) => entry.term == '豆腐火腩飯'), isTrue);
    expect(glossary.entries.any((entry) => entry.term == '芬'), isFalse);
    expect(
      glossary.entries.firstWhere((entry) => entry.term == '行街').mandarin,
      contains('不是逛街'),
    );
    expect(
      glossary.entries.firstWhere((entry) => entry.term == '唔該').mandarin,
      contains('麻烦你'),
    );
  });

  test('lesson files contribute words without copying phonics drills', () {
    final course = Glossary.entriesFromCourse([
      _loadLesson('lesson_1.json'),
      _loadLesson('lesson_2.json'),
      _loadLesson('lesson_3.json'),
    ]);
    expect(course.every((entry) => entry.term.length <= 12), isTrue);
    expect(course.any((entry) => entry.term == '芬'), isFalse);
    expect(course.any((entry) => entry.term == '巴'), isFalse);
    expect(course.any((entry) => entry.term == '一'), isFalse);
    expect(course.any((entry) => entry.term.contains('陳小明')), isFalse);
    expect(course.any((entry) => entry.term.contains('___')), isFalse);
    expect(course.any((entry) => entry.term == '衫'), isTrue);
    expect(course.any((entry) => entry.term == '菠蘿油'), isTrue);
    expect(
      course.firstWhere((entry) => entry.term == '吹水').jyutping,
      'ceoi1 seoi2',
    );
    expect(
      course.firstWhere((entry) => entry.term == '轉左').jyutping,
      'zyun3 zo2',
    );
    expect(course.any((entry) => entry.term == '街'), isFalse);
    expect(
      course.firstWhere((entry) => entry.term == '今個禮拜').jyutping,
      'gam1 go3 lai5 baai3',
    );
    expect(
      course.firstWhere((entry) => entry.term == '呢個月').jyutping,
      'ni1 go3 jyut6',
    );
    expect(
      course.firstWhere((entry) => entry.term == '中大').jyutping,
      'zung1 daai6',
    );
    expect(
      course.firstWhere((entry) => entry.term == '地鐵').jyutping,
      'dei6 tit3',
    );
    expect(course.firstWhere((entry) => entry.term == '廿').jyutping, 'jaa6');
  });

  test('slash alternatives stay separate words', () {
    const lesson = Lesson(
      id: 'x',
      number: 1,
      title: 't',
      date: 'd',
      modules: [
        LessonModule(
          id: 'm',
          title: 't',
          subtitle: '',
          kind: 'practice',
          items: [
            LessonItem(
              id: 'shops',
              type: 'vocab',
              cantonese: '冰室／茶餐廳',
              jyutping: 'bing1 sat1 / caa4 caan1 teng1',
              mandarin: '两种店',
            ),
          ],
        ),
      ],
    );
    expect(
      Glossary.entriesFromCourse([lesson]).map((entry) => entry.term).toList(),
      ['冰室', '茶餐廳'],
    );
  });

  test('vocabulary cards can carry an image path', () {
    final item = LessonItem.fromJson({
      'id': 'toast',
      'type': 'vocab',
      'cantonese': '多士',
      'jyutping': 'do1 si6',
      'mandarin': '吐司',
      'image': 'assets/glossary/toast.png',
    });
    expect(item.showsImage, isTrue);

    final phrase = LessonItem.fromJson({
      'id': 'hello',
      'type': 'phrase',
      'cantonese': '早晨',
      'jyutping': 'zou2 san4',
      'mandarin': '早上好',
      'image': 'assets/glossary/toast.png',
    });
    expect(phrase.showsImage, isFalse);
  });

  testWidgets('tapping a marked word shows the mandarin note', (tester) async {
    final glossary = Glossary(const [
      GlossaryEntry(id: 'dine', term: '堂食', mandarin: '在店里吃，不外带'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlossaryText(
            text: '堂食',
            glossary: glossary,
            style: const TextStyle(fontSize: 26),
          ),
        ),
      ),
    );

    await tester.tap(find.text('堂食'));
    await tester.pumpAndSettle();
    expect(find.text('在店里吃，不外带'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

Lesson _loadLesson(String name) {
  return Lesson.fromJson(
    jsonDecode(File('assets/lessons/$name').readAsStringSync())
        as Map<String, dynamic>,
  );
}

Glossary _mergedGlossary() {
  final curated = Glossary.fromJson(
    jsonDecode(File('assets/glossary/entries.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  return Glossary([
    ...curated.entries,
    ...Glossary.entriesFromCourse([
      _loadLesson('lesson_1.json'),
      _loadLesson('lesson_2.json'),
      _loadLesson('lesson_3.json'),
    ]),
  ]);
}
