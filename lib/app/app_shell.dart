import 'package:flutter/material.dart';

import '../core/layout/breakpoints.dart';
import '../theme/app_theme.dart';

/// Centers the app on medium/expanded screens and leaves
/// compact phones full-bleed.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  /// Kept for backwards compatibility (glossary sheet width).
  /// New code should use [AppBreakpoints].
  static const double compactBreakpoint = AppBreakpoints.medium;

  /// Kept for backwards compatibility (glossary sheet width).
  static const double contentWidth = 480;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppBreakpoints.classForWidth(constraints.maxWidth);
        if (layout == LayoutClass.compact) {
          return child;
        }
        final maxWidth = layout == LayoutClass.medium
            ? AppBreakpoints.mediumContentWidth
            : AppBreakpoints.expandedContentWidth;
        return ColoredBox(
          color: const Color(0xFFECECEC),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                minHeight: constraints.maxHeight,
                maxHeight: constraints.maxHeight,
              ),
              // Clip route transitions (SlideTransition paints pages outside
              // the Navigator bounds mid-animation). Without this, pushed /
              // popped pages visibly fly across the gray gutters on wide
              // screens instead of staying inside the centered column.
              child: ClipRect(
                child: ColoredBox(color: AppColors.cream, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}
