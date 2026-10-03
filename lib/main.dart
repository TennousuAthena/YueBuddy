import 'package:flutter/material.dart';

import 'app/yue_buddy_app.dart';
import 'core/audio/cantonese_speech_service.dart';
import 'core/audio/device_tts_service.dart';
import 'core/audio/minimax_config.dart';
import 'core/audio/tts_backend_config.dart';
import 'features/glossary/glossary.dart';
import 'features/lessons/data/lesson_repository.dart';
import 'features/lessons/domain/lesson_models.dart';
import 'features/lessons/progress/progress_controller.dart';
import 'features/onboarding/jyutping_dictionary.dart';
import 'features/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsController();
  final progress = ProgressController();
  final speech = CantoneseSpeechService(
    device: DeviceTtsService(),
    config: MinimaxConfig.fromEnvironment(),
    backend: TtsBackendConfig.fromEnvironment(),
  );
  final lessons = AssetLessonRepository();
  final dictionary = await JyutpingDictionary.loadAsset();
  final catalog = await lessons.loadCatalog();
  final course = <Lesson>[];
  for (final summary in catalog.lessons) {
    if (!summary.isAvailable) continue;
    course.add(await lessons.loadLesson(summary.id));
  }
  final glossary = await Glossary.loadAsset(course: course);

  await Future.wait([settings.load(), progress.load(), speech.initialize()]);
  speech.updateSpeechRate(settings.speechRate);
  speech.setOnlineTtsEnabled(settings.useOnlineTts);
  settings.addListener(() {
    speech.updateSpeechRate(settings.speechRate);
    speech.setOnlineTtsEnabled(settings.useOnlineTts);
  });

  runApp(
    YueBuddyApp(
      settings: settings,
      progress: progress,
      speech: speech,
      lessons: lessons,
      dictionary: dictionary,
      glossary: glossary,
    ),
  );
}
