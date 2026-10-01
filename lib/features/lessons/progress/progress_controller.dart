import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/lesson_models.dart';

class ProgressController extends ChangeNotifier {
  ProgressController({SharedPreferences? preferences})
    : _preferences = preferences;

  static const learnedIdsKey = 'learned_item_ids';

  SharedPreferences? _preferences;
  final Set<String> _learnedIds = {};

  Set<String> get learnedIds => Set.unmodifiable(_learnedIds);

  Future<void> load() async {
    _preferences ??= await SharedPreferences.getInstance();
    _learnedIds
      ..clear()
      ..addAll(_preferences!.getStringList(learnedIdsKey) ?? const []);
    notifyListeners();
  }

  bool isLearned(String itemId) => _learnedIds.contains(itemId);

  Future<void> toggleLearned(String itemId) async {
    if (_learnedIds.contains(itemId)) {
      _learnedIds.remove(itemId);
    } else {
      _learnedIds.add(itemId);
    }
    notifyListeners();
    await _preferences?.setStringList(learnedIdsKey, _learnedIds.toList());
  }

  int learnedCount(Iterable<LessonItem> items) {
    return items.where((item) => _learnedIds.contains(item.id)).length;
  }

  double moduleProgress(LessonModule module) {
    if (module.items.isEmpty) return 0;
    return learnedCount(module.items) / module.items.length;
  }

  double lessonProgress(Lesson lesson) {
    final total = lesson.itemCount;
    if (total == 0) return 0;
    final learned = lesson.modules.fold<int>(
      0,
      (sum, module) => sum + learnedCount(module.items),
    );
    return learned / total;
  }
}
