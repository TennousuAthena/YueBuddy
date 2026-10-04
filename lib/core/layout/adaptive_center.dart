import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Centers [child] and constrains its width per breakpoint.
///
/// - compact (<600): full width, horizontal padding 20.
/// - medium (600-839): max 720, horizontal padding 24.
/// - expanded and large (>=840): full width, matching [AppShell].
class AdaptiveCenter extends StatelessWidget {
  const AdaptiveCenter({
    super.key,
    required this.child,
    this.maxWidthOverride,
    this.paddingOverride,
  });

  final Widget child;
  final double? maxWidthOverride;
  final EdgeInsetsGeometry? paddingOverride;

  static double maxWidthFor(BuildContext context) {
    final layout = context.layoutClass;
    return switch (layout) {
      LayoutClass.compact => double.infinity,
      LayoutClass.medium => AppBreakpoints.mediumContentWidth,
      LayoutClass.expanded || LayoutClass.large => double.infinity,
    };
  }

  static EdgeInsets pagePaddingFor(BuildContext context) {
    final layout = context.layoutClass;
    return switch (layout) {
      LayoutClass.compact => const EdgeInsets.symmetric(horizontal: 20),
      LayoutClass.medium => const EdgeInsets.symmetric(horizontal: 24),
      LayoutClass.expanded || LayoutClass.large =>
        const EdgeInsets.symmetric(horizontal: 32),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppBreakpoints.classForWidth(constraints.maxWidth);
        final maxWidth =
            maxWidthOverride ??
            switch (layout) {
              LayoutClass.compact => double.infinity,
              LayoutClass.medium => AppBreakpoints.mediumContentWidth,
              LayoutClass.expanded || LayoutClass.large => double.infinity,
            };
        final padding =
            paddingOverride ??
            switch (layout) {
              LayoutClass.compact => const EdgeInsets.symmetric(horizontal: 20),
              LayoutClass.medium => const EdgeInsets.symmetric(horizontal: 24),
              LayoutClass.expanded || LayoutClass.large =>
                const EdgeInsets.symmetric(horizontal: 32),
            };
        if (layout == LayoutClass.compact) {
          return Padding(padding: padding, child: child);
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: padding, child: child),
          ),
        );
      },
    );
  }
}

/// Sliver/grid helper that maps available width to a cross-axis count.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minTileWidth = 340,
    this.maxColumns = 3,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double minTileWidth;
  final int maxColumns;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = AppBreakpoints.columnsForWidth(
          constraints.maxWidth,
          minTileWidth: minTileWidth,
          maxColumns: maxColumns,
        );
        if (columns <= 1) {
          return Column(
            children: [
              for (var i = 0; i < itemCount; i++) itemBuilder(context, i),
            ],
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            // Cards are wider than tall; keep a stable ratio so tiles
            // don't stretch on very wide screens.
            mainAxisExtent: 104,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
