import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/audio/speech_service.dart';
import '../../core/platform/harmony.dart';
import '../../core/layout/breakpoints.dart';
import '../../theme/app_theme.dart';
import '../lessons/domain/lesson_models.dart';
import 'name_reading.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  final _origin = TextEditingController();
  NameReading? _reading;

  @override
  void dispose() {
    _name.dispose();
    _origin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final frame = AppFrame(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            );
            final wide = frame.onboardingWide;
            final horizontal = frame.layoutClass == LayoutClass.compact
                ? 0.0
                : frame.pagePadding;
            Widget content = reading == null
                ? _NameStep(
                    controller: _name,
                    origin: _origin,
                    wide: wide,
                    onContinue: () {
                      final value = _name.text.trim();
                      if (value.isEmpty) return;
                      setState(() {
                        _reading = AppScope.of(context).dictionary.read(value);
                      });
                    },
                  )
                : _ReadingStep(
                    reading: reading,
                    wide: wide,
                    onBack: () => setState(() => _reading = null),
                    onStart: () {
                      final settings = AppScope.of(context).settings;
                      settings.setDisplayName(reading.name);
                      settings.setOrigin(_origin.text);
                    },
                  );
            if (!wide) return content;
            // Wide PC/tablet: center a 960 column on the gray gutter.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  child: content,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  const _NameStep({
    required this.controller,
    required this.origin,
    required this.onContinue,
    required this.wide,
  });

  final TextEditingController controller;
  final TextEditingController origin;
  final VoidCallback onContinue;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: wide
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        const Text(
          '先认识一下',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '填入你的名字和家乡可以获取在课程中获取粤语读法',
          style: TextStyle(
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: controller,
          autofocus: !wide,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: _fieldDecoration('例如：陈小明'),
        ),
        const SizedBox(height: 20),
        const Text('来自哪里', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: origin,
          builder: (context, _) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in kOriginSuggestions)
                  ChoiceChip(
                    label: Text(option),
                    selected: origin.text.trim() == option,
                    onSelected: (_) => origin.text = option,
                    selectedColor: AppColors.green,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: origin.text.trim() == option
                          ? Colors.white
                          : AppColors.ink,
                    ),
                    side: const BorderSide(color: AppColors.line, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: origin,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onContinue(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: _fieldDecoration('例如：成都人'),
        ),
      ],
    );

    final cta = ListenableBuilder(
      listenable: Listenable.merge([controller, origin]),
      builder: (context, _) {
        final ready = controller.text.trim().isNotEmpty;
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: ready ? onContinue : null,
            child: const Text('继续'),
          ),
        );
      },
    );

    if (!wide) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                MediaQuery.sizeOf(context).height -
                MediaQuery.paddingOf(context).top -
                MediaQuery.paddingOf(context).bottom -
                48,
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: form),
                const SizedBox(height: 24),
                cta,
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: form),
          const SizedBox(width: 48),
          Expanded(child: cta),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.line, width: 2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.green, width: 2),
    ),
  );
}

class _ReadingStep extends StatelessWidget {
  const _ReadingStep({
    required this.reading,
    required this.onBack,
    required this.onStart,
    required this.wide,
  });

  final NameReading reading;
  final VoidCallback onBack;
  final VoidCallback onStart;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final speech = AppScope.of(context).speech;
    return ListenableBuilder(
      listenable: speech,
      builder: (context, _) {
        final speaking = speech.activeItemId == 'onboarding-name';
        final card = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line, width: 2),
          ),
          child: Column(
            children: [
              Text(
                reading.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                reading.jyutping,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.greenDark,
                ),
              ),
              const SizedBox(height: 18),
              IconButton.filled(
                onPressed: speech.isCantoneseAvailable
                    ? () => speech.speak(
                        SpeechUtterance(text: reading.speakText),
                        itemId: 'onboarding-name',
                      )
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.line,
                  minimumSize: const Size(64, 64),
                ),
                icon: Icon(
                  speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  size: 32,
                ),
              ),
            ],
          ),
        );

        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const Text(
              '你的粤语读法',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '这是常用读音。多音字可能和家里的叫法不一样，听听看就好。',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        );

        final footerNote = isHarmonyOs || speech.isCantoneseAvailable
            ? const SizedBox.shrink()
            : const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  '这台设备没有粤语语音，先记下粤拼。装好「中文（香港）」语音后可以再听。',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              );

        final cta = SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onStart, child: const Text('开始复习')),
        );

        if (!wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 28),
                card,
                footerNote,
                const SizedBox(height: 32),
                cta,
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: card),
              const SizedBox(width: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    footerNote,
                    const SizedBox(height: 28),
                    cta,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
