import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../features/lessons/domain/karaoke.dart';
import '../../theme/app_theme.dart';
import 'glossary.dart';

class GlossaryText extends StatefulWidget {
  const GlossaryText({
    super.key,
    required this.text,
    required this.style,
    required this.glossary,
    this.sungCount = 0,
    this.sungColor = AppColors.orange,
    this.blanks = const [],
  });

  final String text;
  final TextStyle style;
  final Glossary glossary;

  /// Karaoke: number of leading normalized characters already sung.
  /// 0 disables. See [karaokeSplitOffset] for the split rule.
  final int sungCount;
  final Color sungColor;

  /// Fill-in-the-blank ranges. They win over glossary matches so a filled
  /// name never opens the wrong vocabulary sheet.
  final List<BlankSpan> blanks;

  @override
  State<GlossaryText> createState() => _GlossaryTextState();
}

/// A tappable blank inside lesson text.
class BlankSpan {
  const BlankSpan({
    required this.start,
    required this.end,
    required this.filled,
    required this.onTap,
  });

  final int start;
  final int end;
  final bool filled;
  final VoidCallback onTap;
}

class _GlossaryTextState extends State<GlossaryText> {
  List<GlossaryMatch> _matches = const [];
  List<TapGestureRecognizer> _recognizers = const [];
  List<TapGestureRecognizer> _blankRecognizers = const [];
  String _blanksKey = '';

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GlossaryText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.glossary != widget.glossary ||
        _blanksKey != _keyOf(widget.blanks)) {
      _sync();
    }
  }

  static String _keyOf(List<BlankSpan> blanks) {
    return blanks
        .map((b) => '${b.start}-${b.end}-${b.filled}')
        .join(',');
  }

  void _sync() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    for (final recognizer in _blankRecognizers) {
      recognizer.dispose();
    }
    final matches = widget.glossary.findMatches(widget.text);
    _matches = matches;
    _recognizers = [
      for (final match in matches)
        TapGestureRecognizer()
          ..onTap = () => showGlossarySheet(context, match.entry),
    ];
    _blanksKey = _keyOf(widget.blanks);
    _blankRecognizers = [
      for (final blank in widget.blanks)
        TapGestureRecognizer()..onTap = blank.onTap,
    ];
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    for (final recognizer in _blankRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final karaokeOff = widget.sungCount <= 0;
    final split = karaokeOff
        ? 0
        : karaokeSplitOffset(widget.text, widget.sungCount);
    // Entire line sung: recolor everything instead of falling back.
    final allSung = !karaokeOff && split >= widget.text.length;
    InlineSpan span(
      String text,
      int globalStart, {
      TextStyle? style,
      GestureRecognizer? recognizer,
    }) {
      if (karaokeOff) {
        return TextSpan(text: text, style: style, recognizer: recognizer);
      }
      if (allSung) {
        return TextSpan(
            text: text, style: _sung(style), recognizer: recognizer);
      }
      // Span crosses the sung boundary: split it so sung text recolors
      // while vocabulary taps keep working on both sides.
      final cut = split - globalStart;
      if (cut <= 0 || cut >= text.length) {
        final sung = globalStart + text.length <= split;
        return TextSpan(
          text: text,
          style: (sung ? _sung(style) : style),
          recognizer: recognizer,
        );
      }
      return TextSpan(
        style: style,
        recognizer: recognizer,
        children: [
          TextSpan(text: text.substring(0, cut), style: _sung(style)),
          TextSpan(text: text.substring(cut)),
        ],
      );
    }

    if (_matches.isEmpty && widget.blanks.isEmpty) {
      if (karaokeOff) {
        return Text(widget.text, style: widget.style);
      }
      if (allSung) {
        return Text(widget.text, style: _sung(null));
      }
      return Text.rich(
        TextSpan(
          style: widget.style,
          children: [
            TextSpan(
              text: widget.text.substring(0, split),
              style: _sung(null),
            ),
            TextSpan(text: widget.text.substring(split)),
          ],
        ),
      );
    }

    final linked = widget.style.copyWith(
      color: AppColors.greenDark,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dashed,
      decorationColor: AppColors.green,
      decorationThickness: 2,
    );
    TextStyle blankStyle(bool filled) {
      return widget.style.copyWith(
        color: filled ? AppColors.blue : AppColors.muted,
        fontWeight: filled ? FontWeight.w800 : null,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
        decorationColor: filled ? AppColors.blue : AppColors.muted,
        decorationThickness: 2,
      );
    }

    final blanks = [...widget.blanks]..sort((a, b) => a.start - b.start);
    bool overlapsBlank(int start, int end) {
      return blanks.any((b) => start < b.end && b.start < end);
    }

    InlineSpan blankSpan(BlankSpan blank, int blankIndex) {
      return span(
        widget.text.substring(blank.start, blank.end),
        blank.start,
        style: blankStyle(blank.filled),
        recognizer: blankIndex < _blankRecognizers.length
            ? _blankRecognizers[blankIndex]
            : null,
      );
    }

    // Merge glossary matches with blanks; blanks win overlaps.
    final children = <InlineSpan>[];
    var cursor = 0;
    final blankIndexOf = <BlankSpan, int>{
      for (var i = 0; i < widget.blanks.length; i++) widget.blanks[i]: i,
    };
    final events = <({int start, bool isBlank, int index})>[
      for (var i = 0; i < _matches.length; i++)
        if (!overlapsBlank(_matches[i].start, _matches[i].end))
          (start: _matches[i].start, isBlank: false, index: i),
      for (final blank in blanks)
        (start: blank.start, isBlank: true, index: blankIndexOf[blank]!),
    ]..sort((a, b) {
        final byStart = a.start - b.start;
        if (byStart != 0) return byStart;
        // Blank wins ties.
        return (b.isBlank ? 1 : 0) - (a.isBlank ? 1 : 0);
      });
    for (final event in events) {
      if (event.isBlank) {
        final blank = blanks.firstWhere(
          (b) => blankIndexOf[b] == event.index,
        );
        if (blank.start > cursor) {
          children.add(
            span(widget.text.substring(cursor, blank.start), cursor),
          );
        }
        children.add(blankSpan(blank, event.index));
        cursor = blank.end;
      } else {
        final match = _matches[event.index];
        if (match.start > cursor) {
          children.add(
            span(widget.text.substring(cursor, match.start), cursor),
          );
        }
        children.add(
          span(
            match.entry.term,
            match.start,
            style: linked,
            recognizer: _recognizers[event.index],
          ),
        );
        cursor = match.end;
      }
    }
    if (cursor < widget.text.length) {
      children.add(span(widget.text.substring(cursor), cursor));
    }

    return Text.rich(TextSpan(style: widget.style, children: children));
  }

  TextStyle? _sung(TextStyle? style) {
    return (style ?? widget.style).copyWith(color: widget.sungColor);
  }
}

void showGlossarySheet(BuildContext context, GlossaryEntry entry) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0x803C3C3C),
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: AppShell.contentWidth),
    builder: (context) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: _GlossarySheet(entry: entry),
      );
    },
  );
}

class _GlossarySheet extends StatelessWidget {
  const _GlossarySheet({required this.entry});

  final GlossaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      '词汇',
                      style: TextStyle(
                        color: AppColors.greenDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.muted,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  entry.term,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.15,
                  ),
                ),
              ),
              if (entry.jyutping != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        entry.jyutping!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.greenDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      entry.mandarin,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
