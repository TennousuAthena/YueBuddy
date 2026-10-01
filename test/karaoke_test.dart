import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yue_buddy/app/yue_buddy_app.dart';
import 'package:yue_buddy/core/audio/speech_service.dart';
import 'package:yue_buddy/features/glossary/glossary.dart';
import 'package:yue_buddy/features/glossary/glossary_text.dart';
import 'package:yue_buddy/features/lessons/data/lesson_repository.dart';
import 'package:yue_buddy/features/lessons/domain/karaoke.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';
import 'package:yue_buddy/features/lessons/progress/progress_controller.dart';
import 'package:yue_buddy/features/onboarding/jyutping_dictionary.dart';
import 'package:yue_buddy/features/settings/settings_controller.dart';
import 'package:yue_buddy/theme/app_theme.dart';

import 'support/fake_speech_service.dart';
import 'widget_test.dart' as helper;

Lesson _dialogueLesson() {
  return const Lesson(
    id: 'l1',
    number: 1,
    title: '互相認識',
    date: '14/9',
    modules: [
      LessonModule(
        id: 'dg',
        title: '对话',
        subtitle: '',
        kind: 'dialogue',
        recordings: ['audio/dg.m4a'],
        items: [
          LessonItem(
            id: 's1',
            type: 'phrase',
            cantonese: '早晨！',
            jyutping: 'zou2 san4',
            mandarin: '早上好！',
            speaker: 'Peter',
            clip: AudioClip(
              startMs: 100,
              endMs: 900,
              words: WordTiming(
                text: '早晨',
                startsMs: [100, 500],
                endsMs: [400, 800],
              ),
            ),
          ),
          LessonItem(
            id: 's2',
            type: 'phrase',
            cantonese: '你好嗎？',
            jyutping: 'nei5 hou2 maa3',
            mandarin: '你好吗？',
            speaker: 'Mary',
          ),
        ],
      ),
    ],
  );
}

/// First leaf span carrying [color] anywhere in the tree (Flutter wraps
/// Text.rich spans, so tests can't assume a flat layout).
TextSpan? _firstColoredSpan(InlineSpan span, Color color) {
  if (span is TextSpan) {
    if (span.style?.color == color &&
        (span.text?.isNotEmpty ?? false)) {
      return span;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = _firstColoredSpan(child, color);
      if (found != null) return found;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('karaoke mapping', () {
    test('normalize mirrors the python norm()', () {
      expect(normalizeKaraokeText('Hello，我係陳小明！'), 'hello我係陳小明');
      expect(normalizeKaraokeText('早晨！'), '早晨');
      expect(normalizeKaraokeText('___'), '');
      expect(normalizeKaraokeText('BBA今年YEAR'), 'bba今年year');
    });

    test('sungCharCount lights chars by start time', () {
      const timing = WordTiming(
        text: '早晨',
        startsMs: [100, 500],
        endsMs: [400, 800],
      );
      expect(
        sungCharCount(display: '早晨！', timing: timing, positionMs: 0),
        0,
      );
      expect(
        sungCharCount(display: '早晨！', timing: timing, positionMs: 100),
        1,
      );
      expect(
        sungCharCount(display: '早晨！', timing: timing, positionMs: 900),
        2,
      );
    });

    test('sungCharCount returns -1 on text mismatch', () {
      const timing = WordTiming(
        text: '早晨',
        startsMs: [100, 500],
        endsMs: [400, 800],
      );
      expect(
        sungCharCount(display: '晚安！', timing: timing, positionMs: 900),
        -1,
      );
    });

    test('karaokeSplitOffset skips punctuation', () {
      expect(karaokeSplitOffset('早晨！', 0), 0);
      expect(karaokeSplitOffset('早晨！', 1), 1);
      expect(karaokeSplitOffset('早晨！', 2), 2);
      expect(karaokeSplitOffset('早晨！', 9), 3);
    });
  });

  group('word timing model', () {
    test('tryParse accepts the pipeline payload', () {
      final timing = WordTiming.tryParse({
        't': '早晨',
        'w': [100, 400, 500, 800],
      });
      expect(timing, isNotNull);
      expect(timing!.startsMs, [100, 500]);
      expect(timing.endsMs, [400, 800]);
    });

    test('tryParse rejects malformed payloads without throwing', () {
      expect(WordTiming.tryParse(null), isNull);
      expect(WordTiming.tryParse({'t': '早晨', 'w': [100]}), isNull);
      expect(WordTiming.tryParse({'t': '', 'w': []}), isNull);
      expect(WordTiming.tryParse('nope'), isNull);
    });

    test('audio clip round-trips words', () {
      const clip = AudioClip(
        startMs: 100,
        endMs: 900,
        words: WordTiming(
          text: '早晨',
          startsMs: [100, 500],
          endsMs: [400, 800],
        ),
      );
      final restored = AudioClip.fromJson(clip.toJson());
      expect(restored.words!.text, '早晨');
      expect(restored.words!.startsMs, [100, 500]);
    });

    test('audio clip without words still parses', () {
      final clip = AudioClip.fromJson({'startMs': 1, 'endMs': 2});
      expect(clip.words, isNull);
    });
  });

  group('sequence entry', () {
    test('hasTeacherAudio guards incomplete slices', () {
      expect(
        const SequenceEntry(itemId: 'a', fallbackText: 'x').hasTeacherAudio,
        isFalse,
      );
      expect(
        const SequenceEntry(
          itemId: 'a',
          fallbackText: 'x',
          assetPath: 'a.m4a',
          start: Duration(milliseconds: 5),
          end: Duration(milliseconds: 5),
        ).hasTeacherAudio,
        isFalse,
      );
      expect(
        const SequenceEntry(
          itemId: 'a',
          fallbackText: 'x',
          assetPath: 'a.m4a',
          start: Duration(milliseconds: 1),
          end: Duration(milliseconds: 5),
        ).hasTeacherAudio,
        isTrue,
      );
    });
  });

  group('fake sequence', () {
    test('playSequence keeps teacher-first order and progress state',
        () async {
      final speech = FakeSpeechService();
      await speech.playSequence(
        const [
          SequenceEntry(
            itemId: 's1',
            fallbackText: '早晨',
            assetPath: 'audio/dg.m4a',
            start: Duration(milliseconds: 100),
            end: Duration(milliseconds: 900),
          ),
          SequenceEntry(itemId: 's2', fallbackText: '你好嗎'),
        ],
        itemId: 'dg-all',
      );
      expect(speech.sequenceEntries, ['s1', 's2']);
      expect(speech.sequenceAssets, ['audio/dg.m4a']);
      expect(speech.activeSequenceId, 'dg-all');
      expect(speech.activeSequenceIndex, 1);
      expect(speech.activeSequenceTotal, 2);
      expect(speech.activeItemId, 's2');

      await speech.stop();
      expect(speech.activeSequenceId, isNull);
      expect(speech.activeSequenceTotal, 0);
      expect(speech.isSpeaking, isFalse);
    });
  });

  group('karaoke text widget', () {
    testWidgets('recolors the sung prefix, keeps the rest plain',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlossaryText(
              text: '早晨！',
              style: TextStyle(fontSize: 26, color: AppColors.ink),
              glossary: Glossary.empty(),
              sungCount: 1,
            ),
          ),
        ),
      );
      final rich = tester.widget<RichText>(find.byType(RichText));
      final sung = _firstColoredSpan(rich.text, AppColors.orange);
      expect(sung, isNotNull);
      expect(sung!.text, '早');
      // The remainder keeps the base style (no orange).
      expect(
        _firstColoredSpan(rich.text, AppColors.ink),
        isNull,
      );
      expect(rich.text.toPlainText(), '早晨！');
    });

    testWidgets('sungCount 0 renders plain text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlossaryText(
              text: '早晨！',
              style: TextStyle(fontSize: 26, color: AppColors.ink),
              glossary: Glossary.empty(),
            ),
          ),
        ),
      );
      expect(find.text('早晨！', findRichText: true), findsOneWidget);
    });
  });

  group('dialogue follow-along', () {
    testWidgets('play-all queues teacher audio first with TTS fallback',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final speech = FakeSpeechService();
      SharedPreferences.setMockInitialValues({
        SettingsController.displayNameKey: '小明',
      });
      final settings = SettingsController();
      final progress = ProgressController();
      await settings.load();
      await progress.load();
      await tester.pumpWidget(
        YueBuddyApp(
          settings: settings,
          progress: progress,
          speech: speech,
          lessons: MemoryLessonRepository(
            catalog: helper.sampleCatalog(),
            lessons: {'l1': _dialogueLesson()},
          ),
          dictionary: const JyutpingDictionary({}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('对话'));
      await tester.pumpAndSettle();

      // Follow-along replaces whole-file playback on dialogue modules.
      expect(find.text('跟播整段对话'), findsOneWidget);
      expect(find.text('听老师读'), findsNothing);

      await tester.tap(find.text('跟播整段对话'));
      await tester.pumpAndSettle();

      expect(speech.sequenceEntries, ['s1', 's2']);
      expect(speech.sequenceAssets, ['audio/dg.m4a']);
      // Progress UI replaces the button while the sequence runs.
      expect(find.text('正在播放第 2 / 2 句'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      final stop = find.ancestor(
        of: find.byTooltip('停止'),
        matching: find.byType(IconButton),
      );
      expect(stop, findsOneWidget);
      await tester.tap(stop);
      await tester.pumpAndSettle();
      expect(find.text('跟播整段对话'), findsOneWidget);
    });

    testWidgets('follow-along works without device TTS when clips exist',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final speech = FakeSpeechService(cantoneseAvailable: false);
      SharedPreferences.setMockInitialValues({
        SettingsController.displayNameKey: '小明',
      });
      final settings = SettingsController();
      final progress = ProgressController();
      await settings.load();
      await progress.load();
      await tester.pumpWidget(
        YueBuddyApp(
          settings: settings,
          progress: progress,
          speech: speech,
          lessons: MemoryLessonRepository(
            catalog: helper.sampleCatalog(),
            lessons: {'l1': _dialogueLesson()},
          ),
          dictionary: const JyutpingDictionary({}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('对话'));
      await tester.pumpAndSettle();

      // Teacher clips keep the button enabled without Cantonese TTS.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '跟播整段对话'),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
