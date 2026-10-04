import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yue_buddy/app/yue_buddy_app.dart';
import 'package:yue_buddy/features/lessons/data/lesson_repository.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';
import 'package:yue_buddy/features/lessons/progress/progress_controller.dart';
import 'package:yue_buddy/features/onboarding/jyutping_dictionary.dart';
import 'package:yue_buddy/features/settings/about_section.dart';
import 'package:yue_buddy/features/settings/settings_controller.dart';

import 'support/fake_speech_service.dart';

CourseCatalog sampleCatalog() {
  return const CourseCatalog(
    lessons: [
      LessonSummary(
        id: 'l1',
        number: 1,
        title: '互相認識',
        date: '14/9',
        asset: 'memory:l1',
      ),
      LessonSummary(id: 'l2', number: 2, title: '民以食為天', date: '21/9'),
      LessonSummary(id: 'l3', number: 3, title: '溝通交流', date: '28/9'),
      LessonSummary(id: 'l4', number: 4, title: '運動休閒', date: '5/10'),
      LessonSummary(id: 'l5', number: 5, title: '身心健康', date: '12/10'),
      LessonSummary(id: 'l6', number: 6, title: '人生規劃', date: '26/10'),
    ],
  );
}

Lesson sampleLesson() {
  return const Lesson(
    id: 'l1',
    number: 1,
    title: '互相認識',
    date: '14/9',
    modules: [
      LessonModule(
        id: 'l1-daily',
        title: '日常用語',
        subtitle: '打招呼',
        kind: 'practice',
        items: [
          LessonItem(
            id: 'hello',
            type: 'phrase',
            cantonese: '早晨！',
            jyutping: 'zou2 san4',
            mandarin: '早上好！',
          ),
        ],
      ),
    ],
  );
}

Future<YueBuddyApp> buildApp({
  bool cantoneseAvailable = true,
  Lesson? lesson,
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
    speech: FakeSpeechService(cantoneseAvailable: cantoneseAvailable),
    lessons: MemoryLessonRepository(
      catalog: sampleCatalog(),
      lessons: {'l1': lesson ?? sampleLesson()},
    ),
    dictionary: const JyutpingDictionary({'小': 'siu2', '明': 'ming4'}),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home shows six lessons and opens lesson one', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    expect(find.text('互相認識'), findsOneWidget);
    expect(find.text('民以食為天'), findsOneWidget);
    expect(find.text('溝通交流'), findsOneWidget);
    expect(find.text('運動休閒'), findsOneWidget);
    expect(find.text('身心健康'), findsOneWidget);
    expect(find.text('人生規劃'), findsOneWidget);

    await tester.tap(find.text('互相認識'));
    await tester.pumpAndSettle();
    expect(find.text('日常用語'), findsOneWidget);
  });

  testWidgets('locked lesson shows upcoming snackbar', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('民以食為天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('即将开放'), findsWidgets);
  });

  testWidgets('hides jyutping and mandarin from settings', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('互相認識'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常用語'));
    await tester.pumpAndSettle();
    expect(find.text('早晨！'), findsOneWidget);
    expect(find.text('zou2 san4'), findsNothing);
    expect(find.text('早上好！'), findsNothing);
  });

  testWidgets('ruby layout puts jyutping above each word', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标在词上'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('互相認識'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常用語'));
    await tester.pumpAndSettle();

    expect(find.text('早晨！'), findsNothing);
    expect(find.text('zou2 san4'), findsNothing);
    expect(find.text('早'), findsOneWidget);
    expect(find.text('晨！'), findsOneWidget);
    expect(find.text('zou2'), findsOneWidget);
    expect(find.text('san4'), findsOneWidget);
    expect(find.text('早上好！'), findsOneWidget);
  });

  testWidgets('speak button records cantonese playback', (tester) async {
    SharedPreferences.setMockInitialValues({
      SettingsController.displayNameKey: '小明',
    });
    final settings = SettingsController();
    final progress = ProgressController();
    final speech = FakeSpeechService();
    await settings.load();
    await progress.load();
    await tester.pumpWidget(
      YueBuddyApp(
        settings: settings,
        progress: progress,
        speech: speech,
        lessons: MemoryLessonRepository(
          catalog: sampleCatalog(),
          lessons: {'l1': sampleLesson()},
        ),
        dictionary: const JyutpingDictionary({'小': 'siu2', '明': 'ming4'}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('互相認識'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常用語'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.volume_up_rounded));
    await tester.pump();
    expect(speech.spoken, ['早晨！']);
  });

  testWidgets('disables speak when cantonese is missing', (tester) async {
    await tester.pumpWidget(await buildApp(cantoneseAvailable: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有粤语语音'), findsWidgets);
    await tester.tap(find.text('互相認識'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常用語'));
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.volume_up_rounded),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('onboarding shows a cantonese reading then enters review', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    final progress = ProgressController();
    await settings.load();
    await progress.load();
    await tester.pumpWidget(
      YueBuddyApp(
        settings: settings,
        progress: progress,
        speech: FakeSpeechService(),
        lessons: MemoryLessonRepository(
          catalog: sampleCatalog(),
          lessons: {'l1': sampleLesson()},
        ),
        dictionary: const JyutpingDictionary({
          '陈': 'can4',
          '小': 'siu2',
          '明': 'ming4',
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('先认识一下'), findsOneWidget);
    expect(find.text('名字和籍贯会写进课程，之后也能改。'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '陈小明');
    await tester.tap(find.text('上海人'));
    await tester.pump();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('can4 siu2 ming4'), findsOneWidget);

    await tester.tap(find.text('开始复习'));
    await tester.pumpAndSettle();
    expect(settings.origin, '上海人');
    expect(find.text('互相認識'), findsOneWidget);
    expect(find.text('智能练习'), findsOneWidget);
  });

  testWidgets('settings greeting lets the learner rename themselves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('你好'), findsOneWidget);
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('siu2 ming4'), findsOneWidget);

    await tester.tap(find.text('修改名字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '明明');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('你好'), findsOneWidget);
    expect(find.text('明明'), findsOneWidget);
    expect(find.text('ming4 ming4'), findsOneWidget);
    expect(find.text('小明'), findsNothing);
  });

  testWidgets('about lists the repository and illustration credit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutSection), findsNothing);
    expect(
      find.text('https://github.com/TennousuAthena/YueBuddy'),
      findsNothing,
    );
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutSection), findsOneWidget);
    expect(
      find.text('https://github.com/TennousuAthena/YueBuddy'),
      findsWidgets,
    );
    expect(find.textContaining('いらすとや'), findsWidgets);
    expect(find.textContaining('BSD 3-Clause License'), findsWidgets);
    expect(find.textContaining('MIT License'), findsWidgets);
  });
}
