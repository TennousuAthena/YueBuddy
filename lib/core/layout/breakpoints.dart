import 'package:flutter/material.dart';

/// Responsive breakpoints aligned with Material 3 window size classes.
enum LayoutClass { compact, medium, expanded }

class AppBreakpoints {
  const AppBreakpoints._();

  /// < 600: phones (portrait).
  static const double medium = 600;

  /// 600–839: tablets portrait / phones landscape.
  /// >= 840: tablets landscape / desktop.
  static const double expanded = 840;

  /// >= 1080: show master-detail two panes inside the content area.
  static const double masterDetail = 1080;

  static const double mediumContentWidth = 720;
  static const double expandedContentWidth = 1080;

  static LayoutClass classForWidth(double width) {
    if (width >= expanded) return LayoutClass.expanded;
    if (width >= medium) return LayoutClass.medium;
    return LayoutClass.compact;
  }

  static bool isMasterDetailWidth(double width) => width >= masterDetail;

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

extension LayoutClassX on BuildContext {
  LayoutClass get layoutClass {
    final width = MediaQuery.sizeOf(this).width;
    return AppBreakpoints.classForWidth(width);
  }

  bool get isCompact =>
      AppBreakpoints.classForWidth(MediaQuery.sizeOf(this).width) ==
      LayoutClass.compact;
  bool get isExpanded =>
      AppBreakpoints.classForWidth(MediaQuery.sizeOf(this).width) ==
      LayoutClass.expanded;
}
