import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yue_buddy/app/app_scope.dart';
import 'package:yue_buddy/app/yue_buddy_app.dart';
import 'package:yue_buddy/features/lessons/data/lesson_repository.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';
import 'package:yue_buddy/features/lessons/presentation/module_screen.dart';
import 'package:yue_buddy/features/lessons/progress/progress_controller.dart';
import 'package:yue_buddy/features/onboarding/jyutping_dictionary.dart';
import 'package:yue_buddy/features/settings/settings_controller.dart';

import 'support/fake_speech_service.dart';
import 'widget_test.dart' as helper;

Lesson _clippedLesson() {
  return const Lesson(
    id: 'l1',
    number: 1,
    title: '互相認識',
    date: '14/9',
    modules: [
      LessonModule(
        id: 'l1-dialogue-1',
        title: '打招呼',
        subtitle: '初次見面',
        kind: 'dialogue',
        recordings: ['audio/l1/dialogue-1.m4a'],
        items: [
          LessonItem(
            id: 'hello',
            type: 'phrase',
            cantonese: '早晨！',
            jyutping: 'zou2 san4',
            mandarin: '早上好！',
            speaker: 'Peter',
            clip: AudioClip(startMs: 460, endMs: 2000),
          ),
          LessonItem(
            id: 'bye',
            type: 'phrase',
            cantonese: '再見！',
            jyutping: 'zoi3 gin3',
            mandarin: '再见！',
            speaker: 'Mary',
          ),
        ],
      ),
    ],
  );
}

Future<YueBuddyApp> _buildClippedApp({
  bool cantoneseAvailable = true,
  required FakeSpeechService speech,
}) async {
  SharedPreferences.setMockInitialValues({
    SettingsController.displayNameKey: '小明',
  });
  final settings = SettingsController();
  final progress = ProgressController();
  await settings.load();
  await progress.load();
  return YueBuddyApp(
    settings: settings,
    progress: progress,
    speech: speech,
    lessons: MemoryLessonRepository(
      catalog: helper.sampleCatalog(),
      lessons: {'l1': _clippedLesson()},
    ),
    dictionary: const JyutpingDictionary({'小': 'siu2', '明': 'ming4'}),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioClip model', () {
    test('parses inline clip json with defaults', () {
      final item = LessonItem.fromJson({
        'id': 'x',
        'cantonese': '早晨',
        'jyutping': 'zou2 san4',
        'mandarin': '早上好',
        'clip': {'startMs': 460, 'endMs': 2000},
      });
      expect(item.hasTeacherClip, isTrue);
      expect(item.clip!.startMs, 460);
      expect(item.clip!.endMs, 2000);
      expect(item.clip!.recording, 0);
      expect(item.clip!.isValid, isTrue);
    });

    test('parses multi-recording index and round-trips', () {
      const clip = AudioClip(startMs: 100, endMs: 900, recording: 1);
      final revived = AudioClip.fromJson(clip.toJson());
      expect(revived.recording, 1);
      expect(revived.start, const Duration(milliseconds: 100));
      expect(revived.length, const Duration(milliseconds: 800));
    });

    test('rejects invalid clips for teacher audio lookup', () {
      const module = LessonModule(
        id: 'm',
        title: 't',
        subtitle: 's',
        kind: 'practice',
        recordings: ['audio/l1/daily.m4a'],
        items: [
          LessonItem(
            id: 'bad-range',
            type: 'phrase',
            cantonese: 'a',
            jyutping: 'a',
            mandarin: 'a',
            clip: AudioClip(startMs: 900, endMs: 100),
          ),
          LessonItem(
            id: 'bad-rec',
            type: 'phrase',
            cantonese: 'b',
            jyutping: 'b',
            mandarin: 'b',
            clip: AudioClip(startMs: 100, endMs: 900, recording: 5),
          ),
          LessonItem(
            id: 'no-clip',
            type: 'phrase',
            cantonese: 'c',
            jyutping: 'c',
            mandarin: 'c',
          ),
        ],
      );
      for (final item in module.items) {
        expect(module.teacherAudioFor(item), isNull);
      }
    });

    test('resolves recording file for valid clip', () {
      const module = LessonModule(
        id: 'm',
        title: 't',
        subtitle: 's',
        kind: 'practice',
        recordings: ['audio/l1/daily.m4a'],
        items: [
          LessonItem(
            id: 'ok',
            type: 'phrase',
            cantonese: 'a',
            jyutping: 'a',
            mandarin: 'a',
            clip: AudioClip(startMs: 460, endMs: 2000),
          ),
        ],
      );
      expect(
        module.teacherAudioFor(module.items.single),
        'audio/l1/daily.m4a',
      );
    });
  });

  group('teacher clip playback', () {
    testWidgets('tapping 原音 plays the timestamped slice', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final speech = FakeSpeechService();
      await tester.pumpWidget(await _buildClippedApp(speech: speech));
      await tester.pumpAndSettle();

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打招呼'));
      await tester.pumpAndSettle();

      // Two cards, each with a teacher 原音 button.
      expect(find.widgetWithText(FilledButton, '原音'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FilledButton, '原音').first);
      await tester.pump();
      expect(speech.segmentsPlayed, [
        'audio/l1/dialogue-1.m4a@460-2000',
      ]);
      expect(speech.activeItemId, 'hello');
    });

    testWidgets('原音 works without device cantonese voice', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final speech = FakeSpeechService(cantoneseAvailable: false);
      await tester.pumpWidget(await _buildClippedApp(
        cantoneseAvailable: false,
        speech: speech,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打招呼'));
      await tester.pumpAndSettle();

      // TTS buttons disabled, teacher buttons still enabled.
      final ttsButtons = tester.widgetList<IconButton>(
        find.widgetWithIcon(IconButton, Icons.volume_up_rounded),
      );
      expect(ttsButtons, isNotEmpty);
      for (final button in ttsButtons) {
        expect(button.onPressed, isNull);
      }
      final teacherButtons = tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, '原音'),
      );
      expect(teacherButtons.length, 2);
      expect(teacherButtons.first.onPressed, isNotNull);
      // The card without a timestamp has its teacher button disabled.
      expect(teacherButtons.last.onPressed, isNull);
    });

    testWidgets('embedded module screen also offers teacher clips',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsController();
      final progress = ProgressController();
      final speech = FakeSpeechService();
      await settings.load();
      await progress.load();
      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            settings: settings,
            progress: progress,
            speech: speech,
            lessons: MemoryLessonRepository(
              catalog: helper.sampleCatalog(),
              lessons: {'l1': _clippedLesson()},
            ),
            dictionary:
                const JyutpingDictionary({'小': 'siu2', '明': 'ming4'}),
            child: ModuleScreen(
              module: _clippedLesson().modules.single,
              embedded: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '原音').first);
      await tester.pump();
      expect(speech.segmentsPlayed, [
        'audio/l1/dialogue-1.m4a@460-2000',
      ]);
    });
  });
}
