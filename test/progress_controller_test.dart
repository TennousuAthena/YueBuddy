import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';
import 'package:yue_buddy/features/lessons/progress/progress_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tracks learned items and module progress', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = ProgressController();
    await progress.load();

    const module = LessonModule(
      id: 'm1',
      title: '日常',
      subtitle: '',
      kind: 'practice',
      items: [
        LessonItem(
          id: 'a',
          type: 'phrase',
          cantonese: '早晨',
          jyutping: 'zou2 san4',
          mandarin: '早上好',
        ),
        LessonItem(
          id: 'b',
          type: 'phrase',
          cantonese: '多謝',
          jyutping: 'do1 ze6',
          mandarin: '谢谢',
        ),
      ],
    );

    expect(progress.moduleProgress(module), 0);
    await progress.toggleLearned('a');
    expect(progress.isLearned('a'), isTrue);
    expect(progress.moduleProgress(module), 0.5);
  });
}
