import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../theme/app_theme.dart';
import '../../../glossary/glossary.dart';
import '../../../glossary/glossary_text.dart';
import '../../domain/fill_blanks.dart';
import '../../domain/karaoke.dart';
import '../../domain/lesson_models.dart';

class PhraseCard extends StatelessWidget {
  const PhraseCard({
    super.key,
    required this.item,
    required this.index,
    required this.showJyutping,
    required this.showMandarin,
    required this.speaking,
    required this.canSpeak,
    required this.onPlay,
    required this.fill,
    required this.onBlankTap,
    this.teacherAsset,
    this.onPlayTeacher,
    this.karaokeTiming,
    this.followPosition,
  });

  final LessonItem item;
  final int index;
  final bool showJyutping;
  final bool showMandarin;
  final bool speaking;
  final bool canSpeak;
  final VoidCallback onPlay;

  /// Blanks resolved to display strings (see [resolveLessonFill]).
  final LessonFill fill;
  final ValueChanged<FilledBlank> onBlankTap;

  /// Asset path of the teacher recording slice (see
  /// [LessonModule.teacherAudioFor]). Null when no timestamp exists yet.
  final String? teacherAsset;
  final VoidCallback? onPlayTeacher;

  /// Word timings for karaoke. Only honored together with
  /// [followPosition]; otherwise the line renders statically.
  final WordTiming? karaokeTiming;

  /// Live player position (recording-absolute ms). When non-null, this
  /// card — and only this card — rebuilds its text per position tick.
  final ValueListenable<int?>? followPosition;

  @override
  Widget build(BuildContext context) {
    final glossary = AppScope.of(context).glossary;
    return TweenAnimationBuilder<double>(
      key: ValueKey('phrase-${item.id}-$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.medium(context),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: AnimatedContainer(
        duration: Motion.short(context),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.showsImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  item.image!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CantoneseLine(
                    fill: fill,
                    glossary: glossary,
                    karaokeTiming: karaokeTiming,
                    followPosition: followPosition,
                    onBlankTap: onBlankTap,
                  ),
                ),
                const SizedBox(width: 8),
                DualSpeakControl(
                  speaking: speaking,
                  canSpeakTts: canSpeak,
                  onPlayTts: onPlay,
                  hasTeacherClip: teacherAsset != null,
                  onPlayTeacher: onPlayTeacher,
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: Motion.short(context),
              child: showJyutping
                  ? Padding(
                      key: const ValueKey('jyutping'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        fill.displayJyutping,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.greenDark,
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-jyutping')),
            ),
            AnimatedSwitcher(
              duration: Motion.short(context),
              child: showMandarin
                  ? Padding(
                      key: const ValueKey('mandarin'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        fill.displayMandarin,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-mandarin')),
            ),
            if (item.note != null) ...[
              const SizedBox(height: 8),
              Text(
                item.note!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Cantonese line: static text normally, karaoke-driven while this
/// card's sequence entry plays. Only the followed card subscribes to
/// position ticks, so the rest of the list never rebuilds mid-playback.
class _CantoneseLine extends StatelessWidget {
  const _CantoneseLine({
    required this.fill,
    required this.glossary,
    required this.karaokeTiming,
    required this.followPosition,
    required this.onBlankTap,
  });

  final LessonFill fill;
  final Glossary glossary;
  final WordTiming? karaokeTiming;
  final ValueListenable<int?>? followPosition;
  final ValueChanged<FilledBlank> onBlankTap;

  List<BlankSpan> get _blankSpans => [
        for (final blank in fill.blanks)
          BlankSpan(
            start: blank.start,
            end: blank.end,
            filled: blank.value.isNotEmpty,
            onTap: () => onBlankTap(blank),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: AppColors.ink,
      height: 1.25,
    );
    final timing = karaokeTiming;
    final positions = followPosition;
    if (timing == null || positions == null) {
      return GlossaryText(
        text: fill.displayCantonese,
        glossary: glossary,
        style: style,
        blanks: _blankSpans,
      );
    }
    return ValueListenableBuilder<int?>(
      valueListenable: positions,
      builder: (context, positionMs, _) {
        final sung = positionMs == null
            ? 0
            : sungCharCount(
                display: fill.displayCantonese,
                timing: timing,
                positionMs: positionMs,
              );
        return GlossaryText(
          text: fill.displayCantonese,
          glossary: glossary,
          style: style,
          blanks: _blankSpans,
          sungCount: sung < 0 ? 0 : sung,
        );
      },
    );
  }
}

/// Split发音 control: teacher recording (3/4) + TTS synth (1/4).
///
/// The teacher slice plays without device Cantonese voice or network;
/// the small TTS button keeps the synth voice as a fallback/reference.
class DualSpeakControl extends StatelessWidget {
  const DualSpeakControl({
    super.key,
    required this.speaking,
    required this.canSpeakTts,
    required this.onPlayTts,
    required this.hasTeacherClip,
    required this.onPlayTeacher,
  });

  final bool speaking;
  final bool canSpeakTts;
  final VoidCallback onPlayTts;
  final bool hasTeacherClip;
  final VoidCallback? onPlayTeacher;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Tooltip(
              message: hasTeacherClip ? '老师原音' : '暂无老师原音时间戳',
              child: FilledButton(
                onPressed: hasTeacherClip ? onPlayTeacher : null,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      speaking ? AppColors.blue : AppColors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.line,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      speaking
                          ? Icons.stop_rounded
                          : Icons.graphic_eq_rounded,
                      size: 20,
                    ),
                    const SizedBox(width: 2),
                    const Text('原音'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: Tooltip(
              message: canSpeakTts ? '合成发音' : '没有粤语语音',
              child: IconButton.filled(
                onPressed: canSpeakTts ? onPlayTts : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.blue.withValues(alpha: 0.16),
                  foregroundColor: AppColors.blue,
                  disabledBackgroundColor: AppColors.line,
                  padding: EdgeInsets.zero,
                ),
                icon: Icon(
                  speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
