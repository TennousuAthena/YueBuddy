import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../domain/fill_blanks.dart';
import '../../domain/lesson_models.dart';
import 'phrase_card.dart';

class DialogueBubble extends StatelessWidget {
  const DialogueBubble({
    super.key,
    required this.item,
    required this.index,
    required this.showJyutping,
    required this.showMandarin,
    required this.speaking,
    required this.canSpeak,
    required this.onPlay,
    this.teacherAsset,
    this.onPlayTeacher,
    this.karaokeTiming,
    this.followPosition,
    required this.fill,
    required this.onBlankTap,
  });

  final LessonItem item;
  final int index;
  final bool showJyutping;
  final bool showMandarin;
  final bool speaking;
  final bool canSpeak;
  final VoidCallback onPlay;
  final String? teacherAsset;
  final VoidCallback? onPlayTeacher;

  /// Karaoke passthrough, see [PhraseCard].
  final WordTiming? karaokeTiming;
  final ValueListenable<int?>? followPosition;

  /// Fill-in-the-blank passthrough, see [PhraseCard].
  final LessonFill fill;
  final ValueChanged<FilledBlank> onBlankTap;

  @override
  Widget build(BuildContext context) {
    final speaker = item.speaker ?? '';
    final isPeter = speaker == 'Peter';
    return Column(
      children: [
        Align(
          alignment: isPeter ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: switch (speaker) {
                'Peter' => AppColors.orange,
                'Mary' => AppColors.blue,
                _ => AppColors.purple,
              },
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              item.speaker ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        PhraseCard(
          item: item,
          index: index,
          showJyutping: showJyutping,
          showMandarin: showMandarin,
          speaking: speaking,
          canSpeak: canSpeak,
          onPlay: onPlay,
          teacherAsset: teacherAsset,
          onPlayTeacher: onPlayTeacher,
          karaokeTiming: karaokeTiming,
          followPosition: followPosition,
          fill: fill,
          onBlankTap: onBlankTap,
        ),
      ],
    );
  }
}
