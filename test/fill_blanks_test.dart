import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yue_buddy/app/app_scope.dart';
import 'package:yue_buddy/features/glossary/glossary.dart';
import 'package:yue_buddy/features/lessons/data/lesson_repository.dart';
import 'package:yue_buddy/features/lessons/domain/fill_blanks.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';
import 'package:yue_buddy/features/lessons/presentation/widgets/fill_sheet.dart';
import 'package:yue_buddy/features/lessons/presentation/widgets/phrase_card.dart';
import 'package:yue_buddy/features/lessons/progress/progress_controller.dart';
import 'package:yue_buddy/features/onboarding/jyutping_dictionary.dart';
import 'package:yue_buddy/features/settings/settings_controller.dart';

import 'support/fake_speech_service.dart';

const _nameItem = LessonItem(
  id: 'l1-d-01',
  type: 'phrase',
  cantonese: '大家好！我係___。',
  jyutping: 'daai6 gaa1 hou2! ngo5 hai6 ___',
  mandarin: '大家好！我是___。',
  fill: [BlankSpec(kind: BlankKind.name)],
);

const _dateItem = LessonItem(
  id: 'l1-dt-02',
  type: 'phrase',
  cantonese: '今日係__月__號，星期__。',
  jyutping: 'gam1 jat6 hai6 __ jyut6 __ hou6, sing1 kei4 __.',
  mandarin: '今天是__月__日，星期__。',
  fill: [
    BlankSpec(kind: BlankKind.month),
    BlankSpec(kind: BlankKind.day),
    BlankSpec(kind: BlankKind.weekday),
  ],
);

LessonFill _resolve(
  LessonItem item, {
  String displayName = '',
  String origin = '',
  DateTime? now,
  Map<String, String> readings = const {},
  Map<int, String> overrides = const {},
}) {
  return resolveLessonFill(
    item: item,
    displayName: displayName,
    origin: origin,
    now: now ?? DateTime(2026, 10, 1),
    nameReadings: readings,
    stored: overrides.get,
  );
}

extension on Map<int, String> {
  String? get(int index) => this[index];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('blank kinds', () {
    test('parse falls back to other', () {
      expect(BlankKind.parse('name'), BlankKind.name);
      expect(BlankKind.parse('weekday'), BlankKind.weekday);
      expect(BlankKind.parse('origin'), BlankKind.origin);
      expect(BlankKind.parse('nope'), BlankKind.other);
      expect(BlankKind.parse(null), BlankKind.other);
    });

    test('cantonese numbers 1-31', () {
      expect(cantoneseNumber(1), 'jat1');
      expect(cantoneseNumber(9), 'gau2');
      expect(cantoneseNumber(10), 'sap6');
      expect(cantoneseNumber(11), 'sap6 jat1');
      expect(cantoneseNumber(20), 'ji6 sap6');
      expect(cantoneseNumber(21), 'jaa6 jat1');
      expect(cantoneseNumber(30), 'saa1 sap6');
      expect(cantoneseNumber(31), 'saa1 sap6 jat1');
    });
  });

  group('resolve name blank', () {
    test('defaults to the onboarding name', () {
      final fill = _resolve(
        _nameItem,
        displayName: '陈小明',
        readings: const {'陈': 'can4', '小': 'siu2', '明': 'ming4'},
      );
      expect(fill.displayCantonese, '大家好！我係陈小明。');
      expect(fill.displayMandarin, '大家好！我是陈小明。');
      expect(
        fill.displayJyutping,
        'daai6 gaa1 hou2! ngo5 hai6 can4 siu2 ming4',
      );
      expect(fill.speakText, '大家好！我係陈小明。');
      expect(fill.blanks.length, 1);
      expect(fill.blanks.single.hasOverride, isFalse);
      expect(fill.blanks.single.reading, 'can4 siu2 ming4');
    });

    test('stored value wins, empty keeps underscores', () {
      final filled = _resolve(_nameItem, overrides: const {0: '阿強'});
      expect(filled.displayCantonese, '大家好！我係阿強。');
      expect(filled.blanks.single.hasOverride, isTrue);

      final empty = _resolve(_nameItem);
      expect(empty.displayCantonese, '大家好！我係___。');
      expect(empty.blanks.single.value, isEmpty);
      expect(empty.blanks.single.reading, '___');
    });
  });

  group('resolve date blanks', () {
    test('defaults to today, weekday independent', () {
      final fill = _resolve(
        _dateItem,
        readings: const {'四': 'sei3', '日': 'jat6'},
      );
      // 2026-10-01 is a Thursday.
      expect(fill.displayCantonese, '今日係10月1號，星期四。');
      expect(fill.displayMandarin, '今天是10月1日，星期四。');
      expect(
        fill.displayJyutping,
        'gam1 jat6 hai6 sap6 jyut6 jat1 hou6, sing1 kei4 sei3.',
      );
      expect(fill.blanks.length, 3);
      expect(fill.blanks.map((blank) => blank.reading), [
        'sap6',
        'jat1',
        'sei3',
      ]);
    });

    test('weekday override does not touch the date', () {
      final fill = _resolve(_dateItem, overrides: const {2: '日'});
      expect(fill.displayCantonese, '今日係10月1號，星期日。');
      expect(fill.blanks[2].hasOverride, isTrue);
      expect(fill.blanks[0].hasOverride, isFalse);
    });
  });

  group('origin blank', () {
    const item = LessonItem(
      id: 'origin',
      type: 'dialogue',
      cantonese: '我係___。',
      jyutping: 'ngo5 hai6 ___',
      mandarin: '我是___。',
      fill: [
        BlankSpec(
          kind: BlankKind.origin,
          fallback: '北京人',
          options: ['北京人', '上海人'],
        ),
      ],
    );

    const readings = {
      '北': 'bak1',
      '京': 'ging1',
      '人': 'jan4',
      '上': 'soeng6',
      '海': 'hoi2',
    };

    test('lesson place stays until the learner picks another', () {
      final fill = _resolve(item, readings: readings);
      expect(fill.displayCantonese, '我係北京人。');
      expect(fill.displayMandarin, '我是北京人。');
      expect(fill.displayJyutping, 'ngo5 hai6 bak1 ging1 jan4');
      expect(fill.blanks.single.hasOverride, isFalse);

      final changed = _resolve(item, readings: readings, origin: '上海人');
      expect(changed.displayCantonese, '我係上海人。');
      expect(changed.displayJyutping, 'ngo5 hai6 soeng6 hoi2 jan4');
      expect(changed.blanks.single.hasOverride, isTrue);
    });

    test('json keeps fallback and options', () {
      final spec = BlankSpec.fromJson({
        'kind': 'origin',
        'fallback': '北京人',
        'options': ['北京人', '上海人'],
      });
      expect(spec.kind, BlankKind.origin);
      expect(spec.fallback, '北京人');
      expect(spec.options, ['北京人', '上海人']);
    });
  });

  group('settings blank storage', () {
    test('round-trips values, empty resets', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController();
      await settings.load();
      expect(settings.blankValue('l1-d-01', 0), isNull);

      await settings.setBlankValue('l1-d-01', 0, '阿強');
      expect(settings.blankValue('l1-d-01', 0), '阿強');

      await settings.setBlankValue('l1-d-01', 0, '  ');
      expect(settings.blankValue('l1-d-01', 0), isNull);
    });
  });

  group('fill sheet', () {
    testWidgets('name blank opens sheet and saves', (tester) async {
      SharedPreferences.setMockInitialValues({
        SettingsController.displayNameKey: '陈小明',
      });
      final settings = SettingsController();
      final progress = ProgressController();
      await settings.load();
      await progress.load();
      LessonFill currentFill() => resolveLessonFill(
        item: _nameItem,
        displayName: settings.displayName,
        now: DateTime(2026, 10, 1),
        nameReadings: const {},
        stored: (index) => settings.blankValue(_nameItem.id, index),
      );

      Future<void> pumpCard() {
        return tester.pumpWidget(
          AppScope(
            settings: settings,
            progress: progress,
            speech: FakeSpeechService(),
            lessons: MemoryLessonRepository(
              catalog: const CourseCatalog(lessons: []),
              lessons: const {},
            ),
            dictionary: const JyutpingDictionary({}),
            glossary: const Glossary.empty(),
            child: MaterialApp(
              home: Scaffold(
                body: PhraseCard(
                  item: _nameItem,
                  index: 0,
                  showJyutping: false,
                  showMandarin: false,
                  speaking: false,
                  canSpeak: false,
                  onPlay: () {},
                  fill: currentFill(),
                  onBlankTap: (blank) => showFillSheet(
                    context: tester.element(find.byType(PhraseCard)),
                    item: _nameItem,
                    blank: blank,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await pumpCard();
      await tester.pumpAndSettle();

      // Name default from onboarding is already in the sentence.
      expect(find.text('大家好！我係陈小明。', findRichText: true), findsOneWidget);

      // Tap the name (the blank, ~7th char) to open the editor.
      final line = find.text('大家好！我係陈小明。', findRichText: true);
      final rect = tester.getRect(line);
      await tester.tapAt(Offset(rect.left + 200, rect.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('你的名字'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '阿強');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(settings.blankValue('l1-d-01', 0), '阿強');
      // The real module screen recomputes fill on settings change.
      await pumpCard();
      await tester.pumpAndSettle();
      expect(find.text('大家好！我係阿強。', findRichText: true), findsOneWidget);
    });

    testWidgets('origin blank offers choices and free text', (tester) async {
      const item = LessonItem(
        id: 'l1-dg1-06',
        type: 'dialogue',
        cantonese: '我係___。',
        jyutping: 'ngo5 hai6 ___',
        mandarin: '我是___。',
        fill: [
          BlankSpec(
            kind: BlankKind.origin,
            fallback: '北京人',
            options: ['北京人', '上海人', '廣州人'],
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController();
      final progress = ProgressController();
      await settings.load();
      await progress.load();

      Future<void> pumpCard() {
        final fill = resolveLessonFill(
          item: item,
          displayName: '',
          now: DateTime(2026, 10, 1),
          nameReadings: const {},
          stored: (index) => settings.blankValue(item.id, index),
        );
        return tester.pumpWidget(
          AppScope(
            settings: settings,
            progress: progress,
            speech: FakeSpeechService(),
            lessons: MemoryLessonRepository(
              catalog: const CourseCatalog(lessons: []),
              lessons: const {},
            ),
            dictionary: const JyutpingDictionary({}),
            glossary: const Glossary.empty(),
            child: MaterialApp(
              home: Scaffold(
                body: PhraseCard(
                  item: item,
                  index: 0,
                  showJyutping: false,
                  showMandarin: false,
                  speaking: false,
                  canSpeak: false,
                  onPlay: () {},
                  fill: fill,
                  onBlankTap: (blank) => showFillSheet(
                    context: tester.element(find.byType(PhraseCard)),
                    item: item,
                    blank: blank,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await pumpCard();
      await tester.pumpAndSettle();
      final fill = resolveLessonFill(
        item: item,
        displayName: '',
        now: DateTime(2026, 10, 1),
        nameReadings: const {},
        stored: (index) => settings.blankValue(item.id, index),
      );
      showFillSheet(
        context: tester.element(find.byType(PhraseCard)),
        item: item,
        blank: fill.blanks.single,
      );
      await tester.pumpAndSettle();

      expect(find.text('你来自哪里'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('上海人'));
      await tester.pumpAndSettle();
      expect(settings.origin, '上海人');
    });
  });
}
