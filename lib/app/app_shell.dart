import 'package:flutter/material.dart';

import '../core/layout/breakpoints.dart';
import '../theme/app_theme.dart';

/// Centers the tablet column. Phones and desktop windows stay full-bleed
/// so 1920×1080, 16:9, and 4:3 use the window instead of a 1080 gutter.
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
        // Desktop (16:9, 4:3, 1920×1080) fills the window. Clip route
        // transitions so a sliding page cannot paint outside the window.
        if (layout.isDesktop) {
          return ClipRect(child: child);
        }
        return ColoredBox(
          color: const Color(0xFFECECEC),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: AppBreakpoints.mediumContentWidth,
                minHeight: constraints.maxHeight,
                maxHeight: constraints.maxHeight,
              ),
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
