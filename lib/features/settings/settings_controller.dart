import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where speech audio comes from. `online` prefers the app backend
/// (Worker + R2) then debug MiniMax, both needing network. `device`
/// never touches the network and only uses the system zh-HK voice.
enum SpeechSource { online, device }

/// How Jyutping sits on a phrase card. [line] is the sentence under the
/// Cantonese. [ruby] puts each word's reading above that word.
enum JyutpingLayout { line, ruby }

/// Whether phrase cards show Jyutping, and where it sits.
enum PinyinDisplay { hidden, line, ruby }

class SettingsController extends ChangeNotifier {
  SettingsController({SharedPreferences? preferences})
    : _preferences = preferences;

  static const speechRateKey = 'speech_rate';
  static const showJyutpingKey = 'show_jyutping';
  static const showMandarinKey = 'show_mandarin';
  static const displayNameKey = 'display_name';
  static const speechSourceKey = 'speech_source';
  static const jyutpingLayoutKey = 'jyutping_layout';

  SharedPreferences? _preferences;
  double _speechRate = 0.42;
  bool _showJyutping = true;
  bool _showMandarin = true;
  String _displayName = '';
  SpeechSource _speechSource = SpeechSource.online;
  JyutpingLayout _jyutpingLayout = JyutpingLayout.line;
  bool _loaded = false;

  double get speechRate => _speechRate;
  bool get showJyutping => _showJyutping;
  bool get showMandarin => _showMandarin;
  String get displayName => _displayName;
  SpeechSource get speechSource => _speechSource;
  JyutpingLayout get jyutpingLayout => _jyutpingLayout;

  /// Visibility and placement of Jyutping, as one settings choice.
  PinyinDisplay get pinyinDisplay {
    if (!_showJyutping) return PinyinDisplay.hidden;
    return _jyutpingLayout == JyutpingLayout.ruby
        ? PinyinDisplay.ruby
        : PinyinDisplay.line;
  }

  bool get useOnlineTts => _speechSource == SpeechSource.online;
  bool get hasName => _displayName.trim().isNotEmpty;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _preferences ??= await SharedPreferences.getInstance();
    _speechRate = _preferences!.getDouble(speechRateKey) ?? 0.42;
    _showJyutping = _preferences!.getBool(showJyutpingKey) ?? true;
    _showMandarin = _preferences!.getBool(showMandarinKey) ?? true;
    _displayName = _preferences!.getString(displayNameKey) ?? '';
    _speechSource = speechSourceFromString(
      _preferences!.getString(speechSourceKey),
    );
    _jyutpingLayout = jyutpingLayoutFromString(
      _preferences!.getString(jyutpingLayoutKey),
    );
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

  Future<void> setSpeechSource(SpeechSource value) async {
    _speechSource = value;
    notifyListeners();
    await _preferences?.setString(speechSourceKey, value.name);
  }

  Future<void> setJyutpingLayout(JyutpingLayout value) async {
    _jyutpingLayout = value;
    notifyListeners();
    await _preferences?.setString(jyutpingLayoutKey, value.name);
  }

  Future<void> setPinyinDisplay(PinyinDisplay value) async {
    _showJyutping = value != PinyinDisplay.hidden;
    if (value == PinyinDisplay.line) _jyutpingLayout = JyutpingLayout.line;
    if (value == PinyinDisplay.ruby) _jyutpingLayout = JyutpingLayout.ruby;
    notifyListeners();
    await _preferences?.setBool(showJyutpingKey, _showJyutping);
    await _preferences?.setString(jyutpingLayoutKey, _jyutpingLayout.name);
  }

  /// User-filled values for lesson blanks (`fill` metadata), keyed by
  /// item + blank index. Empty string resets to the computed default.
  static String blankKey(String itemId, int index) => 'blank_${itemId}_$index';

  String? blankValue(String itemId, int index) {
    final value = _preferences?.getString(blankKey(itemId, index));
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> setBlankValue(String itemId, int index, String value) async {
    final key = blankKey(itemId, index);
    if (value.trim().isEmpty) {
      await _preferences?.remove(key);
    } else {
      await _preferences?.setString(key, value.trim());
    }
    notifyListeners();
  }
}

/// Parses the persisted source; unknown values fall back to online.
SpeechSource speechSourceFromString(String? value) {
  for (final source in SpeechSource.values) {
    if (source.name == value) return source;
  }
  return SpeechSource.online;
}

/// Parses the persisted layout; unknown values keep the separate line.
JyutpingLayout jyutpingLayoutFromString(String? value) {
  for (final layout in JyutpingLayout.values) {
    if (layout.name == value) return layout;
  }
  return JyutpingLayout.line;
}
