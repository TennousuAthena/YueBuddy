import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/audio/speech_service.dart';
import '../../core/audio/tts_locale.dart';
import '../../core/layout/breakpoints.dart';
import '../../theme/app_theme.dart';
import 'about_section.dart';
import 'settings_controller.dart';

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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                _SpeechStatus(
                  message:
                      scope.speech.statusMessage ??
                      (scope.speech.isCantoneseAvailable
                          ? '已使用设备粤语语音（zh-HK）。'
                          : cantoneseUnavailableMessage),
                  warning:
                      scope.speech.statusIsWarning ||
                      !scope.speech.isCantoneseAvailable,
                ),
                const SizedBox(height: 16),
                const Text(
                  '语音来源',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SegmentedButton<SpeechSource>(
                  segments: const [
                    ButtonSegment(
                      value: SpeechSource.online,
                      label: Text('在线语音'),
                      icon: Icon(Icons.cloud_outlined),
                    ),
                    ButtonSegment(
                      value: SpeechSource.device,
                      label: Text('系统离线'),
                      icon: Icon(Icons.smartphone_outlined),
                    ),
                  ],
                  selected: {settings.speechSource},
                  onSelectionChanged: (selected) =>
                      settings.setSpeechSource(selected.first),
                ),
                const SizedBox(height: 4),
                const Text(
                  '在线语音需联网，音质更好；系统离线只用本机粤语语音。',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                const Text('语速', style: TextStyle(fontWeight: FontWeight.w800)),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('拼音', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SegmentedButton<PinyinDisplay>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: PinyinDisplay.hidden,
                      label: Text('不显示'),
                    ),
                    ButtonSegment(
                      value: PinyinDisplay.line,
                      label: Text('分开一行'),
                    ),
                    ButtonSegment(
                      value: PinyinDisplay.ruby,
                      label: Text('标在词上'),
                    ),
                  ],
                  selected: {settings.pinyinDisplay},
                  onSelectionChanged: (selected) =>
                      settings.setPinyinDisplay(selected.first),
                ),
                const SizedBox(height: 4),
                const Text(
                  '分开一行把整句粤拼放在下面。标在词上把读音放在每个词的上方。',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
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
          const aboutButton = AboutButton();

          return LayoutBuilder(
            builder: (context, constraints) {
              final layout = AppBreakpoints.classForWidth(constraints.maxWidth);
              final horizontal = layout == LayoutClass.compact
                  ? 20.0
                  : layout == LayoutClass.medium
                  ? 24.0
                  : 32.0;
              if (layout == LayoutClass.compact) {
                return ListView(
                  padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
                  children: [
                    _NameCard(name: settings.displayName),
                    const SizedBox(height: 12),
                    speechCard,
                    const SizedBox(height: 12),
                    displayCard,
                    const SizedBox(height: 12),
                    aboutButton,
                  ],
                );
              }
              final wide = layout == LayoutClass.expanded;
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 960 : 720),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
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
                                aboutButton,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '你好',
            style: TextStyle(
              color: AppColors.greenDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
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
                tooltip: '听名字',
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
          const SizedBox(height: 8),
          const Text(
            '这个名字会写进课文。想换的话，随时改。',
            style: TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editDisplayName(context, name),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('修改名字'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _editDisplayName(BuildContext context, String current) async {
  final saved = await showDialog<String>(
    context: context,
    builder: (context) => _NameEditorDialog(initial: current),
  );
  if (saved == null || !context.mounted) return;
  await AppScope.of(context).settings.setDisplayName(saved);
}

class _NameEditorDialog extends StatefulWidget {
  const _NameEditorDialog({required this.initial});

  final String initial;

  @override
  State<_NameEditorDialog> createState() => _NameEditorDialogState();
}

class _NameEditorDialogState extends State<_NameEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改名字'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        decoration: const InputDecoration(hintText: '例如：陈小明'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final ready = _controller.text.trim().isNotEmpty;
            return FilledButton(
              onPressed: ready ? _save : null,
              child: const Text('保存'),
            );
          },
        ),
      ],
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

class _SpeechStatus extends StatelessWidget {
  const _SpeechStatus({required this.message, required this.warning});

  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    if (!warning) {
      return Text(
        message,
        style: const TextStyle(
          color: AppColors.muted,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1D6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF8A4E00),
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ),
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
