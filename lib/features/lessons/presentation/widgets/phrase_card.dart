import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../theme/app_theme.dart';
import '../../../glossary/glossary.dart';
import '../../../glossary/glossary_text.dart';
import '../../domain/fill_blanks.dart';
import '../../domain/karaoke.dart';
import '../../domain/lesson_models.dart';
import '../../domain/ruby_jyutping.dart';
import 'lesson_illustration.dart';
import 'ruby_line.dart';

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
    this.rubyJyutping = false,
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

  /// When true and [showJyutping] is on, readings sit above each word
  /// instead of on their own line.
  final bool rubyJyutping;

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
    final ruby =
        showJyutping && rubyJyutping && fill.displayJyutping.trim().isNotEmpty;
    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
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
                LessonIllustration(asset: item.image!),
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
                      ruby: ruby,
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
                child: showJyutping && !ruby
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
    required this.ruby,
  });

  final LessonFill fill;
  final Glossary glossary;
  final WordTiming? karaokeTiming;
  final ValueListenable<int?>? followPosition;
  final ValueChanged<FilledBlank> onBlankTap;
  final bool ruby;

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
      return _line(style, 0);
    }
    return _KaraokeLine(
      positions: positions,
      sungFor: (positionMs) {
        if (positionMs == null) return 0;
        final sung = sungCharCount(
          display: fill.displayCantonese,
          timing: timing,
          positionMs: positionMs,
        );
        return sung < 0 ? 0 : sung;
      },
      line: (sung) => _line(style, sung),
    );
  }

  Widget _line(TextStyle style, int sung) {
    if (!ruby) {
      return GlossaryText(
        text: fill.displayCantonese,
        glossary: glossary,
        style: style,
        blanks: _blankSpans,
        sungCount: sung,
      );
    }
    return RubyLine(
      text: fill.displayCantonese,
      jyutping: fill.displayJyutping,
      glossary: glossary,
      style: style,
      blanks: _blankSpans,
      sungCount: sung,
      anchors: [
        for (final blank in fill.blanks)
          RubyAnchor(
            start: blank.start,
            end: blank.end,
            reading: blank.reading,
          ),
      ],
    );
  }
}

/// Rebuilds the line only when the sung character count changes.
/// Position ticks arrive much faster than syllables.
class _KaraokeLine extends StatefulWidget {
  const _KaraokeLine({
    required this.positions,
    required this.sungFor,
    required this.line,
  });

  final ValueListenable<int?> positions;
  final int Function(int? positionMs) sungFor;
  final Widget Function(int sung) line;

  @override
  State<_KaraokeLine> createState() => _KaraokeLineState();
}

class _KaraokeLineState extends State<_KaraokeLine> {
  int _sung = 0;

  @override
  void initState() {
    super.initState();
    widget.positions.addListener(_onPosition);
    _sung = widget.sungFor(widget.positions.value);
  }

  @override
  void didUpdateWidget(_KaraokeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positions != widget.positions) {
      oldWidget.positions.removeListener(_onPosition);
      widget.positions.addListener(_onPosition);
    }
    _sung = widget.sungFor(widget.positions.value);
  }

  @override
  void dispose() {
    widget.positions.removeListener(_onPosition);
    super.dispose();
  }

  void _onPosition() {
    final sung = widget.sungFor(widget.positions.value);
    if (sung == _sung || !mounted) return;
    setState(() => _sung = sung);
  }

  @override
  Widget build(BuildContext context) => widget.line(_sung);
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
                  backgroundColor: speaking ? AppColors.blue : AppColors.green,
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
                      speaking ? Icons.stop_rounded : Icons.graphic_eq_rounded,
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
