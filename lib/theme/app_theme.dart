import 'package:flutter/material.dart';

class AppColors {
  static const Color green = Color(0xFF58CC02);
  static const Color greenDark = Color(0xFF46A302);
  static const Color blue = Color(0xFF1CB0F6);
  static const Color orange = Color(0xFFFF9600);
  static const Color red = Color(0xFFFF4B4B);
  static const Color purple = Color(0xFFCE82FF);
  static const Color ink = Color(0xFF3C3C3C);
  static const Color muted = Color(0xFF777777);
  static const Color line = Color(0xFFE5E5E5);
  static const Color cream = Color(0xFFF7F7F7);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.light,
      primary: AppColors.green,
      onPrimary: Colors.white,
      secondary: AppColors.blue,
      surface: Colors.white,
      error: AppColors.red,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.line, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.green
              : const Color(0xFFD4D4D4);
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.green.withValues(alpha: 0.16),
        selectedIconTheme: const IconThemeData(color: AppColors.greenDark),
        selectedLabelTextStyle: const TextStyle(
          color: AppColors.greenDark,
          fontWeight: FontWeight.w900,
        ),
        unselectedIconTheme: const IconThemeData(color: AppColors.muted),
        unselectedLabelTextStyle: const TextStyle(
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.green,
        thumbColor: AppColors.green,
        inactiveTrackColor: AppColors.line,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class Motion {
  static bool reduced(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }

  static Duration short(BuildContext context) {
    return reduced(context) ? Duration.zero : const Duration(milliseconds: 220);
  }

  static Duration medium(BuildContext context) {
    return reduced(context) ? Duration.zero : const Duration(milliseconds: 360);
  }

  static Duration stagger(BuildContext context, int index, {int ms = 45}) {
    if (reduced(context)) return Duration.zero;
    return Duration(milliseconds: (ms * index).clamp(0, 360));
  }
}
