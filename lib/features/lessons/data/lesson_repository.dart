import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/lesson_models.dart';

abstract class LessonRepository {
  Future<CourseCatalog> loadCatalog();
  Future<Lesson> loadLesson(String id);
}

class AssetLessonRepository implements LessonRepository {
  AssetLessonRepository({
    AssetBundle? bundle,
    this.catalogAsset = 'assets/lessons/catalog.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String catalogAsset;
  CourseCatalog? _catalog;
  final Map<String, Lesson> _lessons = {};

  @override
  Future<CourseCatalog> loadCatalog() async {
    if (_catalog != null) return _catalog!;
    final raw = await _bundle.loadString(catalogAsset);
    _catalog = CourseCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _catalog!;
  }

  @override
  Future<Lesson> loadLesson(String id) async {
    final cached = _lessons[id];
    if (cached != null) return cached;
    final catalog = await loadCatalog();
    final summary = catalog.lessons.firstWhere(
      (lesson) => lesson.id == id,
      orElse: () => throw StateError('Lesson $id is not in the catalog'),
    );
    if (!summary.isAvailable) {
      throw StateError('Lesson $id is not available yet');
    }
    final raw = await _bundle.loadString(summary.asset!);
    final lesson = Lesson.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _lessons[id] = lesson;
    return lesson;
  }
}

class MemoryLessonRepository implements LessonRepository {
  MemoryLessonRepository({
    required CourseCatalog catalog,
    required Map<String, Lesson> lessons,
  }) : _catalog = catalog,
       _lessons = lessons;

  final CourseCatalog _catalog;
  final Map<String, Lesson> _lessons;

  @override
  Future<CourseCatalog> loadCatalog() async => _catalog;

  @override
  Future<Lesson> loadLesson(String id) async {
    final lesson = _lessons[id];
    if (lesson == null) {
      throw StateError('Lesson $id is not available yet');
    }
    return lesson;
  }
}
