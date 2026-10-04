import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../theme/app_theme.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('智能练习')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final frame = AppFrame(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            );
            final layout = frame.layoutClass;
            // Short 16:9 and landscape phones: shrink the mark and scroll
            // instead of overflowing.
            final shortHeight = frame.isShort || constraints.maxHeight < 520;
            final iconSize = shortHeight
                ? 72.0
                : layout == LayoutClass.compact
                    ? 112.0
                    : 140.0;
            final horizontal = layout == LayoutClass.compact ? 24.0 : 32.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 36,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: shortHeight ? 8 : 32),
                        Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Icon(
                            Icons.forum_rounded,
                            color: AppColors.blue,
                            size: iconSize * 0.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          '跟助手练一练',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '之后会有一个练习助手，只围绕课上的词句和你对话。现在先把课听熟。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                        SizedBox(height: shortHeight ? 24 : 48),
                        const SizedBox(
                          width: double.infinity,
                          child:
                              FilledButton(onPressed: null, child: Text('即将开放')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
