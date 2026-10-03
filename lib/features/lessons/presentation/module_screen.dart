import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/audio/minimax_config.dart';
import '../../../core/audio/speech_service.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../theme/app_theme.dart';
import '../../settings/settings_controller.dart';
import '../domain/fill_blanks.dart';
import '../domain/lesson_models.dart';
import 'widgets/dialogue_bubble.dart';
import 'widgets/fill_sheet.dart';
import 'widgets/lesson_illustration.dart';
import 'widgets/phrase_card.dart';

class ModuleScreen extends StatefulWidget {
  const ModuleScreen({super.key, required this.module, this.embedded = false});

  final LessonModule module;
  final bool embedded;

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  String? _section;

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _ModuleBody(
        module: widget.module,
        section: _section,
        onSectionChanged: (value) => setState(() => _section = value),
        embedded: true,
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.module.title)),
      body: _ModuleBody(
        module: widget.module,
        section: _section,
        onSectionChanged: (value) => setState(() => _section = value),
        embedded: false,
      ),
    );
  }
}

class _ModuleBody extends StatelessWidget {
  const _ModuleBody({
    required this.module,
    required this.section,
    required this.onSectionChanged,
    required this.embedded,
  });

  final LessonModule module;
  final String? section;
  final ValueChanged<String?> onSectionChanged;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sections = module.sections;
    final items = section == null
        ? module.items
        : module.items.where((item) => item.section == section).toList();

    return ListenableBuilder(
      listenable: Listenable.merge([scope.settings, scope.speech]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;
            final horizontal =
                AppBreakpoints.classForWidth(constraints.maxWidth) ==
                    LayoutClass.compact
                ? 16.0
                : 24.0;
            final header = module.recordings.isNotEmpty || module.isDialogue
                ? 1
                : 0;
            final picture = module.showsImage ? 1 : 0;
            Widget pictureBanner() {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LessonIllustration(asset: module.image!, height: 140),
              );
            }

            final useGrid = wide && !module.isDialogue && items.length > 1;

            Widget headerButton(BuildContext context) {
              final recordingId = '${module.id}-recording';
              Widget recordingButton() {
                final playing =
                    scope.speech.activeItemId == recordingId &&
                    scope.speech.isSpeaking;
                return _RecordingButton(
                  label: module.recordings.length > 1
                      ? '听老师读（${module.recordings.length}段）'
                      : '听老师读',
                  playing: playing,
                  onPressed: () {
                    if (playing) {
                      scope.speech.stop();
                    } else {
                      scope.speech.playRecordings(
                        module.recordings,
                        itemId: recordingId,
                      );
                    }
                  },
                );
              }

              // Dialogue follow-along: teacher slices first, TTS fallback.
              Widget sequenceButton() {
                final sequenceId = '${module.id}-all';
                if (scope.speech.activeSequenceId == sequenceId) {
                  return _SequenceProgress(
                    entries: _sequenceEntries(scope, module, items),
                    speech: scope.speech,
                    onStop: () => scope.speech.stop(),
                  );
                }
                final entries = _sequenceEntries(scope, module, items);
                final teacherCount = entries
                    .where((e) => e.hasTeacherAudio)
                    .length;
                final enabled =
                    teacherCount > 0 || scope.speech.isCantoneseAvailable;
                return _PlayAllButton(
                  enabled: enabled,
                  label: teacherCount > 0 ? '跟播整段对话' : '朗读整段对话',
                  onPressed: () =>
                      scope.speech.playSequence(entries, itemId: sequenceId),
                );
              }

              if (module.isDialogue) {
                // Follow-along sequence replaces whole-file playback:
                // same teacher audio, plus per-line progress + karaoke.
                return sequenceButton();
              }
              if (module.recordings.isNotEmpty) {
                return recordingButton();
              }
              return const SizedBox.shrink();
            }

            Widget itemCard(BuildContext context, int itemIndex) {
              final item = items[itemIndex];
              final speaking = scope.speech.activeItemId == item.id;
              final inSequence =
                  scope.speech.activeSequenceId == '${module.id}-all';
              final fill = _resolveFill(scope, item);
              void openFill(FilledBlank blank) {
                showFillSheet(context: context, item: item, blank: blank);
              }

              final teacherAsset = module.teacherAudioFor(item);
              VoidCallback? onPlayTeacher;
              if (teacherAsset != null) {
                final clip = item.clip!;
                onPlayTeacher = () => scope.speech.playSegment(
                  assetPath: teacherAsset,
                  start: clip.start,
                  end: clip.end,
                  itemId: item.id,
                );
              }
              // Only the entry currently playing subscribes to position
              // ticks for karaoke; every other card stays static.
              final following = speaking && inSequence;
              final karaokeTiming = following ? item.clip?.words : null;
              final followPosition = following
                  ? scope.speech.sequencePositionMs
                  : null;
              final rubyJyutping =
                  scope.settings.jyutpingLayout == JyutpingLayout.ruby;
              final card = module.isDialogue && item.speaker != null
                  ? DialogueBubble(
                      item: item,
                      index: itemIndex,
                      showJyutping: scope.settings.showJyutping,
                      showMandarin: scope.settings.showMandarin,
                      rubyJyutping: rubyJyutping,
                      speaking: speaking,
                      canSpeak: scope.speech.isCantoneseAvailable,
                      onPlay: () => scope.speech.speak(
                        _utterance(item, fill.speakText),
                        itemId: item.id,
                      ),
                      teacherAsset: teacherAsset,
                      onPlayTeacher: onPlayTeacher,
                      karaokeTiming: karaokeTiming,
                      followPosition: followPosition,
                      fill: fill,
                      onBlankTap: openFill,
                    )
                  : PhraseCard(
                      item: item,
                      index: itemIndex,
                      showJyutping: scope.settings.showJyutping,
                      showMandarin: scope.settings.showMandarin,
                      rubyJyutping: rubyJyutping,
                      speaking: speaking,
                      canSpeak: scope.speech.isCantoneseAvailable,
                      onPlay: () => scope.speech.speak(
                        _utterance(item, fill.speakText),
                        itemId: item.id,
                      ),
                      teacherAsset: teacherAsset,
                      onPlayTeacher: onPlayTeacher,
                      karaokeTiming: karaokeTiming,
                      followPosition: followPosition,
                      fill: fill,
                      onBlankTap: openFill,
                    );
              return _FollowActive(speaking: speaking, child: card);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (embedded)
                  Padding(
                    padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
                    child: Text(
                      module.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                if (sections.isNotEmpty)
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        8,
                        horizontal,
                        8,
                      ),
                      children: [
                        _SectionChip(
                          label: '全部',
                          selected: section == null,
                          onTap: () => onSectionChanged(null),
                        ),
                        for (final s in sections)
                          _SectionChip(
                            label: s,
                            selected: section == s,
                            onTap: () => onSectionChanged(s),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: useGrid
                      ? CustomScrollView(
                          slivers: [
                            if (picture == 1)
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  horizontal,
                                  8,
                                  horizontal,
                                  0,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: pictureBanner(),
                                ),
                              ),
                            if (header == 1)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    horizontal,
                                    8,
                                    horizontal,
                                    0,
                                  ),
                                  child: headerButton(context),
                                ),
                              ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                horizontal,
                                8,
                                horizontal,
                                32,
                              ),
                              sliver: SliverGrid.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 420,
                                      mainAxisSpacing: 0,
                                      crossAxisSpacing: 12,
                                      mainAxisExtent: 260,
                                    ),
                                itemCount: items.length,
                                itemBuilder: (context, i) =>
                                    itemCard(context, i),
                              ),
                            ),
                          ],
                        )
                      : Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                horizontal,
                                8,
                                horizontal,
                                32,
                              ),
                              itemCount: items.length + header + picture,
                              itemBuilder: (context, index) {
                                if (picture == 1 && index == 0) {
                                  return pictureBanner();
                                }
                                if (header == 1 && index == picture) {
                                  return headerButton(context);
                                }
                                return itemCard(
                                  context,
                                  index - header - picture,
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

SpeechUtterance _utterance(LessonItem item, String text) {
  return SpeechUtterance(
    text: text,
    voiceId: minimaxVoiceForSpeaker(item.speaker),
  );
}

/// Blanks resolved against settings + today (see [resolveLessonFill]).
LessonFill _resolveFill(AppScope scope, LessonItem item) {
  return resolveLessonFill(
    item: item,
    displayName: scope.settings.displayName,
    now: DateTime.now(),
    nameReadings: scope.dictionary.readings,
    stored: (index) => scope.settings.blankValue(item.id, index),
  );
}

/// Dialogue follow-along queue: teacher slice first, TTS text fallback
/// (filled blanks included).
SequenceEntry _sequenceEntry(
  AppScope scope,
  LessonModule module,
  LessonItem item,
) {
  final asset = module.teacherAudioFor(item);
  final clip = item.clip;
  final text = _resolveFill(scope, item).speakText;
  if (asset != null && clip != null) {
    return SequenceEntry(
      itemId: item.id,
      fallbackText: text,
      voiceId: minimaxVoiceForSpeaker(item.speaker),
      assetPath: asset,
      start: clip.start,
      end: clip.end,
    );
  }
  return SequenceEntry(
    itemId: item.id,
    fallbackText: text,
    voiceId: minimaxVoiceForSpeaker(item.speaker),
  );
}

List<SequenceEntry> _sequenceEntries(
  AppScope scope,
  LessonModule module,
  List<LessonItem> items,
) {
  return [for (final item in items) _sequenceEntry(scope, module, item)];
}

/// Scrolls the card into view when it becomes the playing line.
class _FollowActive extends StatefulWidget {
  const _FollowActive({required this.speaking, required this.child});

  final bool speaking;
  final Widget child;

  @override
  State<_FollowActive> createState() => _FollowActiveState();
}

class _FollowActiveState extends State<_FollowActive> {
  @override
  void didUpdateWidget(_FollowActive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.speaking && widget.speaking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            alignment: 0.3,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Replaces the play-all button while a sequence runs: sentence counter,
/// progress bar (intra-sentence fraction when the player reports
/// position), and a stop button.
class _SequenceProgress extends StatelessWidget {
  const _SequenceProgress({
    required this.entries,
    required this.speech,
    required this.onStop,
  });

  final List<SequenceEntry> entries;
  final SpeechService speech;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: speech.sequencePositionMs,
      builder: (context, positionMs, _) {
        final total = entries.length;
        final index = speech.activeSequenceIndex.clamp(0, total - 1);
        var fraction = total == 0 ? 0.0 : index / total;
        final entry = total == 0 ? null : entries[index];
        if (positionMs != null && entry != null && entry.hasTeacherAudio) {
          final start = entry.start!.inMilliseconds;
          final length = entry.end!.inMilliseconds - start;
          if (length > 0) {
            final intra = ((positionMs - start) / length).clamp(0.0, 1.0);
            fraction = (index + intra) / total;
          }
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.green, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      total == 0 ? '播放中' : '正在播放第 ${index + 1} / $total 句',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: fraction.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: AppColors.line,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onStop,
                tooltip: '停止',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecordingButton extends StatelessWidget {
  const _RecordingButton({
    required this.label,
    required this.playing,
    required this.onPressed,
  });

  final String label;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(playing ? Icons.stop_rounded : Icons.graphic_eq_rounded),
        label: Text(playing ? '停止' : label),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.green,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          color: selected ? Colors.white : AppColors.ink,
        ),
        side: const BorderSide(color: AppColors.line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({
    required this.enabled,
    required this.onPressed,
    this.label = '朗读整段对话',
  });

  final bool enabled;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.playlist_play_rounded),
        label: Text(label),
      ),
    );
  }
}
