import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yue_buddy/features/settings/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads defaults and persists settings', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    await controller.load();
    expect(controller.showJyutping, isTrue);
    expect(controller.showMandarin, isTrue);
    expect(controller.speechRate, 0.42);

    await controller.setShowJyutping(false);
    await controller.setShowMandarin(false);
    await controller.setSpeechRate(0.3);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SettingsController.showJyutpingKey), isFalse);
    expect(prefs.getBool(SettingsController.showMandarinKey), isFalse);
    expect(prefs.getDouble(SettingsController.speechRateKey), 0.3);
  });
}
