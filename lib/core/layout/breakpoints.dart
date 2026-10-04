import 'package:flutter/material.dart';

/// Responsive breakpoints aligned with Material 3 window size classes.
enum LayoutClass { compact, medium, expanded, large }

/// Window shape the pages adapt to, independent of the width class.
enum AspectProfile { fourThree, standard, sixteenNine }

extension LayoutClassFlags on LayoutClass {
  /// Desktop rail and multi-column pages. [LayoutClass.large] counts.
  bool get isDesktop =>
      this == LayoutClass.expanded || this == LayoutClass.large;
}

class AppBreakpoints {
  const AppBreakpoints._();

  /// < 600: phones (portrait).
  static const double medium = 600;

  /// 600–839: tablets portrait / phones landscape.
  /// >= 840: tablets landscape / desktop.
  static const double expanded = 840;

  /// >= 1600 of usable page width: 1920×1080 after the navigation rail.
  static const double large = 1600;

  /// Lesson routes cover the navigation rail, so this is the window width.
  /// 1280×720 and 1440×1080 split; 1024×768 stays a single pane.
  static const double masterDetail = 1100;

  static const double mediumContentWidth = 720;

  /// Legacy centered column. Desktop windows now use the full width.
  static const double expandedContentWidth = 1080;

  static const double homeTileMaxWidth = 460;
  static const double gridSpacing = 12;

  /// 16:9 and wider, including 1920×1080, 1600×900 and 1280×720.
  static const double sixteenNine = 1.6;

  /// 4:3 and squarer, including 1024×768, 1440×1080 and 1600×1200.
  static const double fourThree = 1.4;

  /// Below this height, tighten vertical rhythm (small 16:9 windows).
  static const double shortHeight = 800;

  static LayoutClass classForWidth(double width) {
    if (width >= large) return LayoutClass.large;
    if (width >= expanded) return LayoutClass.expanded;
    if (width >= medium) return LayoutClass.medium;
    return LayoutClass.compact;
  }

  static bool isMasterDetailWidth(double width) => width >= masterDetail;

  static AspectProfile aspectProfileFor(double width, double height) {
    if (height <= 0) return AspectProfile.standard;
    final aspect = width / height;
    if (aspect >= sixteenNine) return AspectProfile.sixteenNine;
    if (aspect <= fourThree) return AspectProfile.fourThree;
    return AspectProfile.standard;
  }

  /// Number of grid columns for card lists. Keeps tiles >= [minTileWidth].
  static int columnsForWidth(
    double width, {
    double minTileWidth = 340,
    int maxColumns = 3,
  }) {
    if (width < medium) return 1;
    final columns = (width / minTileWidth).floor().clamp(1, maxColumns);
    return columns;
  }
}

/// Width, height, and aspect for the space a page is laying out.
class AppFrame {
  const AppFrame({required this.width, required this.height});

  final double width;
  final double height;

  factory AppFrame.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AppFrame(width: size.width, height: size.height);
  }

  double get aspect => height <= 0 ? 1 : width / height;

  LayoutClass get layoutClass => AppBreakpoints.classForWidth(width);

  AspectProfile get aspectProfile =>
      AppBreakpoints.aspectProfileFor(width, height);

  bool get isSixteenNine => aspectProfile == AspectProfile.sixteenNine;

  bool get isFourThree => aspectProfile == AspectProfile.fourThree;

  bool get isLarge => layoutClass == LayoutClass.large;

  bool get isShort => height < AppBreakpoints.shortHeight;

  bool get useMasterDetail => AppBreakpoints.isMasterDetailWidth(width);

  /// Side-by-side name form only when the canvas is both wide and tall.
  bool get onboardingWide => width >= 1080 && height >= 700;

  int get homeColumns {
    if (layoutClass == LayoutClass.compact) return 1;
    if (isFourThree && width < 1100) return 2;
    if (layoutClass == LayoutClass.medium) return 2;
    return 3;
  }

  /// Caps the home course grid so a tile stays near [AppBreakpoints.homeTileMaxWidth].
  double get homeGridMaxWidth {
    final columns = homeColumns;
    if (columns <= 1) return double.infinity;
    return columns * AppBreakpoints.homeTileMaxWidth +
        (columns - 1) * AppBreakpoints.gridSpacing;
  }

  double get pagePadding {
    return switch (layoutClass) {
      LayoutClass.compact => isShort ? 16.0 : 20.0,
      LayoutClass.medium => isShort ? 20.0 : 24.0,
      LayoutClass.expanded || LayoutClass.large => isShort ? 24.0 : 32.0,
    };
  }

  double get topInset => isShort ? 4.0 : 8.0;

  double get bottomInset => isShort ? 20.0 : 32.0;

  /// Lesson list pane. Grows with the page, stays between 300 and 380.
  double get sidebarWidth => (width * 0.28).clamp(300.0, 380.0);

  /// Vocab cards: 16:9 and 1920 use up to three columns, 4:3 up to two.
  int get vocabMaxColumns => isFourThree ? 2 : 3;

  /// Readable line length for dialogue and single-column modules.
  double get dialogueMaxWidth {
    if (isFourThree) return 800;
    if (isSixteenNine) return 960;
    return 880;
  }

  /// Settings and about column. 4:3 ~800, 16:9 ~1040, 1920 ~1200.
  double get settingsMaxWidth {
    if (layoutClass == LayoutClass.compact) return width;
    if (layoutClass == LayoutClass.medium) {
      return AppBreakpoints.mediumContentWidth;
    }
    if (isLarge) return 1200;
    if (isFourThree) return 800;
    if (isSixteenNine) return 1040;
    return 960;
  }

  double get illustrationHeight {
    if (isShort) return 100;
    if (isSixteenNine) return 120;
    return 140;
  }
}

extension LayoutClassX on BuildContext {
  LayoutClass get layoutClass {
    final width = MediaQuery.sizeOf(this).width;
    return AppBreakpoints.classForWidth(width);
  }

  AppFrame get appFrame {
    final size = MediaQuery.sizeOf(this);
    return AppFrame(width: size.width, height: size.height);
  }

  bool get isCompact =>
      AppBreakpoints.classForWidth(MediaQuery.sizeOf(this).width) ==
      LayoutClass.compact;

  bool get isExpanded =>
      AppBreakpoints.classForWidth(MediaQuery.sizeOf(this).width).isDesktop;
}
