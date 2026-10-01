import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yue_buddy/app/app_shell.dart';
import 'package:yue_buddy/core/layout/breakpoints.dart';

import 'widget_test.dart' as helper;

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('breakpoints', () {
    test('classForWidth follows 600/840', () {
      expect(AppBreakpoints.classForWidth(390), LayoutClass.compact);
      expect(AppBreakpoints.classForWidth(599), LayoutClass.compact);
      expect(AppBreakpoints.classForWidth(600), LayoutClass.medium);
      expect(AppBreakpoints.classForWidth(820), LayoutClass.medium);
      expect(AppBreakpoints.classForWidth(840), LayoutClass.expanded);
      expect(AppBreakpoints.classForWidth(1440), LayoutClass.expanded);
    });

    test('master detail only on very wide screens', () {
      expect(AppBreakpoints.isMasterDetailWidth(839), isFalse);
      expect(AppBreakpoints.isMasterDetailWidth(1079), isFalse);
      expect(AppBreakpoints.isMasterDetailWidth(1080), isTrue);
      expect(AppBreakpoints.isMasterDetailWidth(1440), isTrue);
    });

    test('columnsForWidth grows with width', () {
      expect(AppBreakpoints.columnsForWidth(390), 1);
      expect(AppBreakpoints.columnsForWidth(700), 2);
      expect(AppBreakpoints.columnsForWidth(1100, maxColumns: 3), 3);
    });
  });

  group('adaptive navigation', () {
    testWidgets('compact phone uses bottom bar, no rail, single column',
        (tester) async {
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

    testWidgets('medium tablet uses rail and two-column grid',
        (tester) async {
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

      final rail =
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(find.byType(SliverGrid), findsOneWidget);
    });
  });

  group('lesson master-detail', () {
    testWidgets('compact lesson needs module tap to see phrase',
        (tester) async {
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

    testWidgets('expanded lesson shows module content side by side',
        (tester) async {
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
  });

  group('wide transition clipping', () {
    testWidgets('shell clips content to the centered column', (tester) async {
      _setSize(tester, const Size(1440, 900));
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await helper.buildApp());
      await tester.pumpAndSettle();

      final clips = find.descendant(
        of: find.byType(AppShell),
        matching: find.byType(ClipRect),
      );
      expect(clips, findsWidgets);
      // One of them must be the shell column itself: full content width,
      // horizontally centered on screen.
      final rects = <Rect>[
        for (var i = 0; i < clips.evaluate().length; i++)
          tester.getRect(clips.at(i)),
      ];
      expect(
        rects.any(
          (r) =>
              r.width == AppBreakpoints.expandedContentWidth &&
              r.left == (1440 - AppBreakpoints.expandedContentWidth) / 2,
        ),
        isTrue,
      );
    });

    testWidgets('page push mid-transition stays healthy on wide screen',
        (tester) async {
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
