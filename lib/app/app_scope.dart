import 'package:flutter/material.dart';

import '../core/audio/speech_service.dart';
import '../features/glossary/glossary.dart';
import '../features/lessons/data/lesson_repository.dart';
import '../features/lessons/progress/progress_controller.dart';
import '../features/onboarding/jyutping_dictionary.dart';
import '../features/settings/settings_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.progress,
    required this.speech,
    required this.lessons,
    required this.dictionary,
    this.glossary = const Glossary.empty(),
    required super.child,
  });

  final SettingsController settings;
  final ProgressController progress;
  final SpeechService speech;
  final LessonRepository lessons;
  final JyutpingDictionary dictionary;
  final Glossary glossary;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return settings != oldWidget.settings ||
        progress != oldWidget.progress ||
        speech != oldWidget.speech ||
        lessons != oldWidget.lessons ||
        dictionary != oldWidget.dictionary ||
        glossary != oldWidget.glossary;
  }
}
