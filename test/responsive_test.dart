import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yue_buddy/app/app_scope.dart';
import 'package:yue_buddy/app/app_shell.dart';
import 'package:yue_buddy/core/layout/breakpoints.dart';
import 'package:yue_buddy/features/lessons/data/lesson_repository.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';
import 'package:yue_buddy/features/lessons/presentation/module_screen.dart';
import 'package:yue_buddy/features/lessons/progress/progress_controller.dart';
import 'package:yue_buddy/features/onboarding/jyutping_dictionary.dart';
import 'package:yue_buddy/features/settings/settings_controller.dart';

import 'support/fake_speech_service.dart';
import 'widget_test.dart' as helper;

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('breakpoints', () {
    test('classForWidth follows 600/840/1600', () {
      expect(AppBreakpoints.classForWidth(390), LayoutClass.compact);
      expect(AppBreakpoints.classForWidth(599), LayoutClass.compact);
      expect(AppBreakpoints.classForWidth(600), LayoutClass.medium);
      expect(AppBreakpoints.classForWidth(820), LayoutClass.medium);
      expect(AppBreakpoints.classForWidth(840), LayoutClass.expanded);
      expect(AppBreakpoints.classForWidth(1440), LayoutClass.expanded);
      expect(AppBreakpoints.classForWidth(1599), LayoutClass.expanded);
      expect(AppBreakpoints.classForWidth(1600), LayoutClass.large);
      expect(AppBreakpoints.classForWidth(1920), LayoutClass.large);
    });

    test('master detail starts at 1100, so 1024 stays one pane', () {
      expect(AppBreakpoints.isMasterDetailWidth(839), isFalse);
      expect(AppBreakpoints.isMasterDetailWidth(1024), isFalse);
      expect(AppBreakpoints.isMasterDetailWidth(1099), isFalse);
      expect(AppBreakpoints.isMasterDetailWidth(1100), isTrue);
      expect(AppBreakpoints.isMasterDetailWidth(1280), isTrue);
      expect(AppBreakpoints.isMasterDetailWidth(1440), isTrue);
    });

    test('columnsForWidth grows with width', () {
      expect(AppBreakpoints.columnsForWidth(390), 1);
      expect(AppBreakpoints.columnsForWidth(700), 2);
      expect(AppBreakpoints.columnsForWidth(1100, maxColumns: 3), 3);
    });
  });

  group('adaptive navigation', () {
    testWidgets('compact phone uses bottom bar, no rail, single column', (
      tester,
    ) async {
      _setSize(tester, const Size(390, 844));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('学习'), findsOneWidget);
      expect(find.text('智能练习'), findsOneWidget);
      // Single-column home keeps ListView, no SliverGrid.
      expect(find.byType(SliverGrid), findsNothing);
      expect(find.text('互相認識'), findsOneWidget);
    });

    testWidgets('medium tablet uses rail and two-column grid', (tester) async {
      _setSize(tester, const Size(820, 1180));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.text('互相認識'), findsOneWidget);
    });

    testWidgets('expanded pc uses extended rail', (tester) async {
      _setSize(tester, const Size(1440, 900));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(find.byType(SliverGrid), findsOneWidget);
    });
  });

  group('lesson master-detail', () {
    testWidgets('compact lesson needs module tap to see phrase', (
      tester,
    ) async {
      _setSize(tester, const Size(390, 844));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      expect(find.text('日常用語'), findsOneWidget);
      // Phrase detail is on the pushed ModuleScreen, not visible yet.
      expect(find.text('早晨！'), findsNothing);

      await tester.tap(find.text('日常用語'));
      await tester.pumpAndSettle();
      expect(find.text('早晨！'), findsOneWidget);
    });

    testWidgets('expanded lesson shows module content side by side', (
      tester,
    ) async {
      _setSize(tester, const Size(1440, 900));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      // Master-detail: module list on the left, phrase on the right
      // without a second push. The module title appears twice
      // (list card + embedded detail header).
      expect(find.text('日常用語'), findsWidgets);
      expect(find.text('早晨！'), findsOneWidget);
    });

    testWidgets('wide vocab cards show the picture and the word', (
      tester,
    ) async {
      _setSize(tester, const Size(900, 640));
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        SettingsController.displayNameKey: '小明',
      });
      final settings = SettingsController();
      final progress = ProgressController();
      await settings.load();
      await progress.load();
      const module = LessonModule(
        id: 'l3-ask',
        title: '問路',
        subtitle: '地鐵、轉彎、搭𨋢',
        kind: 'practice',
        items: [
          LessonItem(
            id: 'mall',
            type: 'vocab',
            cantonese: '商場',
            jyutping: 'soeng1 coeng4',
            mandarin: '商场',
            image: 'assets/illustrations/irasutoya/l3-a-14.png',
          ),
          LessonItem(
            id: 'lift',
            type: 'vocab',
            cantonese: '搭扶手電梯',
            jyutping: 'daap3 fu4 sau2 din6 tai1',
            mandarin: '搭手扶电梯',
            image: 'assets/illustrations/irasutoya/l3-a-12.png',
          ),
        ],
      );

      await tester.pumpWidget(
        AppScope(
          settings: settings,
          progress: progress,
          speech: FakeSpeechService(),
          lessons: MemoryLessonRepository(
            catalog: const CourseCatalog(lessons: []),
            lessons: const {},
          ),
          dictionary: const JyutpingDictionary({}),
          child: const MaterialApp(home: ModuleScreen(module: module)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      expect(find.text('商場'), findsOneWidget);
      expect(find.text('soeng1 coeng4'), findsOneWidget);
      expect(find.text('搭扶手電梯'), findsOneWidget);
    });
  });

  group('aspect frames', () {
    test('1920x1080 is a large 16:9 canvas', () {
      const frame = AppFrame(width: 1920, height: 1080);
      expect(frame.isSixteenNine, isTrue);
      expect(frame.isLarge, isTrue);
      expect(frame.homeColumns, 3);
      expect(frame.useMasterDetail, isTrue);
      expect(frame.dialogueMaxWidth, 960);
      expect(frame.settingsMaxWidth, 1200);
      expect(frame.sidebarWidth, 380);
      expect(frame.vocabMaxColumns, 3);
      expect(frame.illustrationHeight, 120);
      expect(frame.isShort, isFalse);
    });

    test('1600x900 is 16:9 and still large at the window', () {
      const frame = AppFrame(width: 1600, height: 900);
      expect(frame.isSixteenNine, isTrue);
      expect(frame.isLarge, isTrue);
      expect(frame.homeColumns, 3);
      expect(frame.useMasterDetail, isTrue);
      expect(frame.isShort, isFalse);
    });

    test('1280x720 is a short 16:9', () {
      const frame = AppFrame(width: 1280, height: 720);
      expect(frame.isSixteenNine, isTrue);
      expect(frame.isShort, isTrue);
      expect(frame.isLarge, isFalse);
      expect(frame.homeColumns, 3);
      expect(frame.useMasterDetail, isTrue);
      expect(frame.illustrationHeight, 100);
      expect(frame.settingsMaxWidth, 1040);
      expect(frame.dialogueMaxWidth, 960);
    });

    test('1440x1080 is a tall 4:3', () {
      const frame = AppFrame(width: 1440, height: 1080);
      expect(frame.isFourThree, isTrue);
      expect(frame.homeColumns, 3);
      expect(frame.useMasterDetail, isTrue);
      expect(frame.vocabMaxColumns, 2);
      expect(frame.dialogueMaxWidth, 800);
      expect(frame.settingsMaxWidth, 800);
      expect(frame.illustrationHeight, 140);
    });

    test('1024x768 is a short 4:3 without master-detail', () {
      const frame = AppFrame(width: 1024, height: 768);
      expect(frame.isFourThree, isTrue);
      expect(frame.isShort, isTrue);
      expect(frame.homeColumns, 2);
      expect(frame.useMasterDetail, isFalse);
      expect(frame.onboardingWide, isFalse);
      expect(frame.illustrationHeight, 100);
    });
  });

  group('wide transition clipping', () {
    testWidgets('desktop windows fill the screen instead of a 1080 column', (
      tester,
    ) async {
      _setSize(tester, const Size(1440, 900));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, 0);
      final clips = find.descendant(
        of: find.byType(AppShell),
        matching: find.byType(ClipRect),
      );
      expect(clips, findsWidgets);
      final rects = <Rect>[
        for (var i = 0; i < clips.evaluate().length; i++)
          tester.getRect(clips.at(i)),
      ];
      expect(rects.any((r) => r.width == 1440 && r.left == 0), isTrue);
      expect(
        rects.any((r) => r.width == AppBreakpoints.expandedContentWidth),
        isFalse,
      );
    });

    testWidgets('medium tablet stays in a centered 720 column', (tester) async {
      _setSize(tester, const Size(820, 1180));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, (820 - AppBreakpoints.mediumContentWidth) / 2);
    });
  });

  group('target canvases', () {
    Future<void> openHome(WidgetTester tester, Size size) async {
      _setSize(tester, size);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();
    }

    int homeColumnCount(WidgetTester tester) {
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return delegate.crossAxisCount;
    }

    testWidgets('1920x1080 fills the window with three home columns', (
      tester,
    ) async {
      await openHome(tester, const Size(1920, 1080));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, 0);
      final railWidget = tester.widget<NavigationRail>(
        find.byType(NavigationRail),
      );
      expect(railWidget.extended, isTrue);
      expect(homeColumnCount(tester), 3);

      final tile = tester.getTopLeft(find.text('互相認識'));
      expect(tile.dx, greaterThan(rail.right + 80));

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('早晨！'), findsOneWidget);
    });

    testWidgets('16:9 1600x900 keeps the rail and master-detail', (
      tester,
    ) async {
      await openHome(tester, const Size(1600, 900));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      expect(homeColumnCount(tester), 3);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      expect(find.text('早晨！'), findsOneWidget);
    });

    testWidgets('short 16:9 1280x720 does not overflow', (tester) async {
      await openHome(tester, const Size(1280, 720));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      expect(homeColumnCount(tester), 3);

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      expect(find.text('早晨！'), findsOneWidget);
    });

    testWidgets('4:3 1440x1080 uses master-detail', (tester) async {
      await openHome(tester, const Size(1440, 1080));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      expect(homeColumnCount(tester), 3);
      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.left, 0);

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      expect(find.text('早晨！'), findsOneWidget);
    });

    testWidgets('4:3 1024x768 uses two columns and a pushed module', (
      tester,
    ) async {
      await openHome(tester, const Size(1024, 768));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(homeColumnCount(tester), 2);

      await tester.tap(find.text('互相認識'));
      await tester.pumpAndSettle();
      expect(find.text('日常用語'), findsOneWidget);
      expect(find.text('早晨！'), findsNothing);

      await tester.tap(find.text('日常用語'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('OVERFLOWED'), findsNothing);
      expect(find.text('早晨！'), findsOneWidget);
    });
  });

  group('wide transition clipping', () {
    testWidgets('page push mid-transition stays healthy on wide screen', (
      tester,
    ) async {
      _setSize(tester, const Size(820, 1180));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('互相認識'));
      // Freeze mid slide-transition: entering page paints offset outside
      // the Navigator bounds; ClipRect must contain it without errors.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(find.text('日常用語'), findsOneWidget);
    });
  });
}
