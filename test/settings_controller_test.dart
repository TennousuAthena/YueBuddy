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

  test('persists the speech source with online default', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    await controller.load();
    expect(controller.speechSource, SpeechSource.online);
    expect(controller.useOnlineTts, isTrue);

    await controller.setSpeechSource(SpeechSource.device);
    expect(controller.useOnlineTts, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsController.speechSourceKey), 'device');

    final reloaded = SettingsController();
    await reloaded.load();
    expect(reloaded.speechSource, SpeechSource.device);
  });

  test('persists jyutping layout and defaults to a separate line', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    await controller.load();
    expect(controller.jyutpingLayout, JyutpingLayout.line);

    await controller.setJyutpingLayout(JyutpingLayout.ruby);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SettingsController.jyutpingLayoutKey), 'ruby');

    final reloaded = SettingsController();
    await reloaded.load();
    expect(reloaded.jyutpingLayout, JyutpingLayout.ruby);
  });

  test('pinyin display hides readings or places them', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    await controller.load();
    expect(controller.pinyinDisplay, PinyinDisplay.line);

    await controller.setPinyinDisplay(PinyinDisplay.hidden);
    expect(controller.showJyutping, isFalse);
    expect(controller.jyutpingLayout, JyutpingLayout.line);

    await controller.setPinyinDisplay(PinyinDisplay.ruby);
    expect(controller.showJyutping, isTrue);
    expect(controller.pinyinDisplay, PinyinDisplay.ruby);

    final reloaded = SettingsController();
    await reloaded.load();
    expect(reloaded.pinyinDisplay, PinyinDisplay.ruby);
  });

  test('unknown jyutping layout falls back to the separate line', () async {
    SharedPreferences.setMockInitialValues({
      SettingsController.jyutpingLayoutKey: 'columns',
    });
    final controller = SettingsController();
    await controller.load();
    expect(controller.jyutpingLayout, JyutpingLayout.line);
  });
}
