import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({SharedPreferences? preferences})
    : _preferences = preferences;

  static const speechRateKey = 'speech_rate';
  static const showJyutpingKey = 'show_jyutping';
  static const showMandarinKey = 'show_mandarin';
  static const displayNameKey = 'display_name';

  SharedPreferences? _preferences;
  double _speechRate = 0.42;
  bool _showJyutping = true;
  bool _showMandarin = true;
  String _displayName = '';
  bool _loaded = false;

  double get speechRate => _speechRate;
  bool get showJyutping => _showJyutping;
  bool get showMandarin => _showMandarin;
  String get displayName => _displayName;
  bool get hasName => _displayName.trim().isNotEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _preferences ??= await SharedPreferences.getInstance();
    _speechRate = _preferences!.getDouble(speechRateKey) ?? 0.42;
    _showJyutping = _preferences!.getBool(showJyutpingKey) ?? true;
    _showMandarin = _preferences!.getBool(showMandarinKey) ?? true;
    _displayName = _preferences!.getString(displayNameKey) ?? '';
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value.clamp(0.2, 0.8);
    notifyListeners();
    await _preferences?.setDouble(speechRateKey, _speechRate);
  }

  Future<void> setShowJyutping(bool value) async {
    _showJyutping = value;
    notifyListeners();
    await _preferences?.setBool(showJyutpingKey, value);
  }

  Future<void> setShowMandarin(bool value) async {
    _showMandarin = value;
    notifyListeners();
    await _preferences?.setBool(showMandarinKey, value);
  }

  Future<void> setDisplayName(String value) async {
    _displayName = value.trim();
    notifyListeners();
    await _preferences?.setString(displayNameKey, _displayName);
  }

  /// User-filled values for lesson blanks (`fill` metadata), keyed by
  /// item + blank index. Empty string resets to the computed default.
  static String blankKey(String itemId, int index) => 'blank_${itemId}_$index';

  String? blankValue(String itemId, int index) {
    final value = _preferences?.getString(blankKey(itemId, index));
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> setBlankValue(
    String itemId,
    int index,
    String value,
  ) async {
    final key = blankKey(itemId, index);
    if (value.trim().isEmpty) {
      await _preferences?.remove(key);
    } else {
      await _preferences?.setString(key, value.trim());
    }
    notifyListeners();
  }
}
