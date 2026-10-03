import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';

/// Picture on a vocab card or at the top of a module.
class LessonIllustration extends StatelessWidget {
  const LessonIllustration({super.key, required this.asset, this.height = 160});

  final String asset;
  final double height;

  bool get _fromIrasutoya => asset.contains('/irasutoya/');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: const Color(0xFFF6F3EA),
            child: Image.asset(
              asset,
              height: height,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  SizedBox(height: height),
            ),
          ),
        ),
        if (_fromIrasutoya)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '插画：いらすとや',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
          ),
      ],
    );
  }
}
