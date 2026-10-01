import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/audio/speech_service.dart';
import '../../core/layout/breakpoints.dart';
import '../../theme/app_theme.dart';
import 'name_reading.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  NameReading? _reading;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = AppBreakpoints.isMasterDetailWidth(
              constraints.maxWidth,
            );
            final horizontal =
                AppBreakpoints.classForWidth(constraints.maxWidth) ==
                        LayoutClass.compact
                    ? 0.0
                    : 32.0;
            Widget content = reading == null
                ? _NameStep(
                    controller: _name,
                    wide: wide,
                    onContinue: () {
                      final value = _name.text.trim();
                      if (value.isEmpty) return;
                      setState(() {
                        _reading =
                            AppScope.of(context).dictionary.read(value);
                      });
                    },
                  )
                : _ReadingStep(
                    reading: reading,
                    wide: wide,
                    onBack: () => setState(() => _reading = null),
                    onStart: () {
                      AppScope.of(context)
                          .settings
                          .setDisplayName(reading.name);
                    },
                  );
            if (!wide) return content;
            // Wide PC/tablet: center a 960 column on the gray gutter.
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: horizontal),
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
    required this.onContinue,
    required this.wide,
  });

  final TextEditingController controller;
  final VoidCallback onContinue;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.start,
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
          '输入你的名字。我们会给出一个粤语读法，方便课后跟读。',
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
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onContinue(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            hintText: '例如：陈小明',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 18,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.line, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.green, width: 2),
            ),
          ),
        ),
      ],
    );

    final cta = ListenableBuilder(
      listenable: controller,
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
            minHeight: MediaQuery.sizeOf(context).height -
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: AppColors.line, width: 2),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '粤语伴会记住你的名字',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '下一步会生成粤语读法和粤拼，点一下就能听。横竖屏、平板和 PC 都能用。',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                cta,
              ],
            ),
          ),
        ],
      ),
    );
  }
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

        final footerNote = speech.isCantoneseAvailable
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
          child: FilledButton(
            onPressed: onStart,
            child: const Text('开始复习'),
          ),
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
