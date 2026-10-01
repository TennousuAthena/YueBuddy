import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/audio/speech_service.dart';
import '../../core/audio/tts_locale.dart';
import '../../core/layout/breakpoints.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: Listenable.merge([scope.settings, scope.speech]),
        builder: (context, _) {
          final settings = scope.settings;
          final speechCard = _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '发音',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  scope.speech.statusMessage ??
                      (scope.speech.isCantoneseAvailable
                          ? '已使用设备粤语语音（zh-HK）。'
                          : cantoneseUnavailableMessage),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '语速',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Slider(
                  value: settings.speechRate,
                  min: 0.2,
                  max: 0.7,
                  divisions: 10,
                  label: settings.speechRate.toStringAsFixed(2),
                  onChanged: settings.setSpeechRate,
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('慢', style: TextStyle(color: AppColors.muted)),
                    Text('正常', style: TextStyle(color: AppColors.muted)),
                    Text('快', style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ],
            ),
          );
          final displayCard = _Card(
            child: Column(
              children: [
                _ToggleRow(
                  title: '显示粤拼',
                  subtitle: 'Jyutping',
                  value: settings.showJyutping,
                  onChanged: settings.setShowJyutping,
                ),
                _ToggleRow(
                  title: '显示普通话',
                  subtitle: '对照翻译',
                  value: settings.showMandarin,
                  onChanged: settings.setShowMandarin,
                ),
              ],
            ),
          );
          const aboutCard = _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '关于',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '粤语伴 YueBuddy 0.1.0\n前两课已开放。模块里优先听老师录音，单句仍可用合成语音。',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final layout =
                  AppBreakpoints.classForWidth(constraints.maxWidth);
              final horizontal = layout == LayoutClass.compact
                  ? 20.0
                  : layout == LayoutClass.medium
                      ? 24.0
                      : 32.0;
              if (layout == LayoutClass.compact) {
                return ListView(
                  padding:
                      EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
                  children: [
                    _NameCard(name: settings.displayName),
                    const SizedBox(height: 12),
                    speechCard,
                    const SizedBox(height: 12),
                    displayCard,
                    const SizedBox(height: 12),
                    aboutCard,
                  ],
                );
              }
              final wide = layout == LayoutClass.expanded;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: wide ? 960 : 720,
                  ),
                  child: ListView(
                    padding:
                        EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
                    children: [
                      _NameCard(name: settings.displayName),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: speechCard),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              children: [
                                displayCard,
                                const SizedBox(height: 12),
                                aboutCard,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NameCard extends StatelessWidget {
  const _NameCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final reading = scope.dictionary.read(name);
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reading.jyutping,
                  style: const TextStyle(
                    color: AppColors.greenDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: scope.speech.isCantoneseAvailable
                ? () => scope.speech.speak(
                    SpeechUtterance(text: reading.speakText),
                    itemId: 'profile-name',
                  )
                : null,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.line,
            ),
            icon: const Icon(Icons.volume_up_rounded),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(subtitle, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: child,
    );
  }
}
