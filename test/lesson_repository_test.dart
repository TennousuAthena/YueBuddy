import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yue_buddy/features/lessons/data/lesson_repository.dart';
import 'package:yue_buddy/features/lessons/domain/lesson_models.dart';

void main() {
  test('catalog lists six lessons and the first two are available', () {
    final json =
        jsonDecode(File('assets/lessons/catalog.json').readAsStringSync())
            as Map<String, dynamic>;
    final catalog = CourseCatalog.fromJson(json);
    expect(catalog.lessons, hasLength(6));
    expect(catalog.lessons[0].isAvailable, isTrue);
    expect(catalog.lessons[0].title, '互相認識');
    expect(catalog.lessons[1].isAvailable, isTrue);
    expect(catalog.lessons[1].title, '民以食為天');
    expect(
      catalog.lessons.skip(2).every((lesson) => !lesson.isAvailable),
      isTrue,
    );
  });

  test('lesson 1 parses modules, jyutping and corrected forms', () {
    final json =
        jsonDecode(File('assets/lessons/lesson_1.json').readAsStringSync())
            as Map<String, dynamic>;
    final lesson = Lesson.fromJson(json);
    expect(lesson.modules, hasLength(7));
    expect(lesson.modules.map((module) => module.id).toList(), [
      'l1-basics',
      'l1-daily',
      'l1-dialogue-1',
      'l1-contact',
      'l1-campus',
      'l1-datetime',
      'l1-dialogue-2',
    ]);

    final daily = lesson.modules.firstWhere(
      (module) => module.id == 'l1-daily',
    );
    expect(daily.items.any((item) => item.cantonese.contains('唔使喇')), isTrue);
    expect(
      daily.items.any((item) => item.jyutping.contains('daai6 gaa1 hou2')),
      isTrue,
    );

    final dialogue2 = lesson.modules.firstWhere(
      (module) => module.id == 'l1-dialogue-2',
    );
    expect(
      dialogue2.items.any((item) => item.cantonese.contains('我哋')),
      isTrue,
    );
    expect(dialogue2.items.first.speaker, 'Mary');
    expect(
      dialogue2.items
          .where((item) => item.speaker != null)
          .every((item) => item.speaker == 'Mary' || item.speaker == 'Peter'),
      isTrue,
    );
    final dialogue1 = lesson.modules.firstWhere(
      (module) => module.id == 'l1-dialogue-1',
    );
    expect(dialogue1.items.first.speaker, 'Peter');
    expect(dialogue1.items[2].speaker, 'Mary');
    expect(lesson.itemCount, greaterThan(100));
    expect(
      lesson.modules.every(
        (module) =>
            module.recordings.isNotEmpty &&
            module.recordings.every(
              (path) => File('assets/$path').existsSync(),
            ),
      ),
      isTrue,
    );
  });

  test('lesson 2 opens the food lesson and keeps teacher recordings', () {
    final json =
        jsonDecode(File('assets/lessons/lesson_2.json').readAsStringSync())
            as Map<String, dynamic>;
    final lesson = Lesson.fromJson(json);
    expect(lesson.modules.map((module) => module.id).toList(), [
      'l2-eat',
      'l2-daily',
      'l2-breakfast',
      'l2-drinks',
      'l2-tea',
      'l2-meals',
      'l2-dialogue-1',
      'l2-dialogue-2',
      'l2-other',
    ]);
    expect(
      lesson.modules.every(
        (module) => module.recordings.every(
          (path) => File('assets/$path').existsSync(),
        ),
      ),
      isTrue,
    );
    final order = lesson.modules.firstWhere((module) => module.id == 'l2-eat');
    expect(order.items.any((item) => item.cantonese == '茶餐廳'), isTrue);
    final dialogue = lesson.modules.firstWhere(
      (module) => module.id == 'l2-dialogue-2',
    );
    expect(dialogue.items.any((item) => item.cantonese.contains('我哋')), isTrue);
    final restaurant = lesson.modules.firstWhere(
      (module) => module.id == 'l2-dialogue-1',
    );
    expect(restaurant.items.map((item) => item.speaker).toSet(), {
      '侍應',
      'Peter',
      'Mary',
    });
  });

  test('memory repository loads catalog and rejects locked lessons', () async {
    final catalog = CourseCatalog.fromJson(
      jsonDecode(File('assets/lessons/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final lesson = Lesson.fromJson(
      jsonDecode(File('assets/lessons/lesson_1.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final repo = MemoryLessonRepository(
      catalog: catalog,
      lessons: {'l1': lesson},
    );
    expect((await repo.loadCatalog()).lessons, hasLength(6));
    expect((await repo.loadLesson('l1')).title, '互相認識');
    expect(() => repo.loadLesson('l3'), throwsStateError);
  });
}
