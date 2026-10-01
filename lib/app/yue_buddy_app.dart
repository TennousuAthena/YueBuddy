import 'package:flutter/material.dart';

import '../core/audio/speech_service.dart';
import '../features/glossary/glossary.dart';
import '../features/lessons/data/lesson_repository.dart';
import '../features/lessons/progress/progress_controller.dart';
import '../features/onboarding/jyutping_dictionary.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/settings/settings_controller.dart';
import '../theme/app_theme.dart';
import 'app_scope.dart';
import 'app_shell.dart';
import 'main_shell.dart';

class YueBuddyApp extends StatelessWidget {
  const YueBuddyApp({
    super.key,
    required this.settings,
    required this.progress,
    required this.speech,
    required this.lessons,
    required this.dictionary,
    this.glossary = const Glossary.empty(),
  });

  final SettingsController settings;
  final ProgressController progress;
  final SpeechService speech;
  final LessonRepository lessons;
  final JyutpingDictionary dictionary;
  final Glossary glossary;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      progress: progress,
      speech: speech,
      lessons: lessons,
      dictionary: dictionary,
      glossary: glossary,
      child: MaterialApp(
        title: '粤语伴 YueBuddy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (context, child) =>
            AppShell(child: child ?? const SizedBox.shrink()),
        home: const _AppHome(),
      ),
    );
  }
}

class _AppHome extends StatelessWidget {
  const _AppHome();

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        if (!settings.hasName) return const OnboardingScreen();
        return const MainShell();
      },
    );
  }
}
