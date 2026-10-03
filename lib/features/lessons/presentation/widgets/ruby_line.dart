import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../../glossary/glossary.dart';
import '../../../glossary/glossary_text.dart';
import '../../domain/karaoke.dart';
import '../../domain/ruby_jyutping.dart';

int _advance(String text, int index) {
  final unit = text.codeUnitAt(index);
  final surrogate = unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length;
  return index + (surrogate ? 2 : 1);
}

/// Cantonese with each word's Jyutping sitting above it.
class RubyLine extends StatelessWidget {
  const RubyLine({
    super.key,
    required this.text,
    required this.jyutping,
    required this.glossary,
    required this.style,
    this.anchors = const [],
    this.blanks = const [],
    this.sungCount = 0,
    this.sungColor = AppColors.orange,
  });

  final String text;
  final String jyutping;
  final Glossary glossary;
  final TextStyle style;
  final List<RubyAnchor> anchors;
  final List<BlankSpan> blanks;
  final int sungCount;
  final Color sungColor;

  @override
  Widget build(BuildContext context) {
    final matches = glossary.findMatches(text);
    bool overlapsBlank(int start, int end) {
      return blanks.any((blank) => start < blank.end && blank.start < end);
    }

    final pieces = layoutRuby(
      text: text,
      jyutping: jyutping,
      anchors: anchors,
      groups: [
        for (final match in matches)
          if (!overlapsBlank(match.start, match.end))
            RubySpan(start: match.start, end: match.end),
      ],
    );
    final karaokeOn = sungCount > 0;
    final split = karaokeOn ? karaokeSplitOffset(text, sungCount) : 0;

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final piece in pieces)
          _RubyColumn(
            piece: piece,
            style: style,
            split: split,
            karaokeOn: karaokeOn,
            sungColor: sungColor,
            match: _matchFor(piece, matches),
            blank: _blankFor(piece),
          ),
      ],
    );
  }

  GlossaryMatch? _matchFor(RubyPiece piece, List<GlossaryMatch> matches) {
    for (final match in matches) {
      if (match.start == piece.start && match.end <= piece.end) return match;
    }
    return null;
  }

  BlankSpan? _blankFor(RubyPiece piece) {
    for (final blank in blanks) {
      if (blank.start == piece.start && blank.end <= piece.end) return blank;
    }
    return null;
  }
}

class _RubyColumn extends StatelessWidget {
  const _RubyColumn({
    required this.piece,
    required this.style,
    required this.split,
    required this.karaokeOn,
    required this.sungColor,
    required this.match,
    required this.blank,
  });

  final RubyPiece piece;
  final TextStyle style;
  final int split;
  final bool karaokeOn;
  final Color sungColor;
  final GlossaryMatch? match;
  final BlankSpan? blank;

  @override
  Widget build(BuildContext context) {
    final fullySung = _fullySung();
    final readingStyle = TextStyle(
      fontSize: 12,
      height: 1,
      fontWeight: FontWeight.w700,
      color: fullySung ? sungColor : AppColors.greenDark,
    );
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (piece.reading.isEmpty)
          const SizedBox(height: 14)
        else
          Text(
            piece.reading,
            softWrap: false,
            textAlign: TextAlign.center,
            style: readingStyle,
          ),
        _characters(),
      ],
    );
    final onTap =
        blank?.onTap ??
        (match == null ? null : () => showGlossarySheet(context, match!.entry));
    if (onTap == null) return column;
    return GestureDetector(onTap: onTap, child: column);
  }

  bool _fullySung() {
    if (!karaokeOn) return false;
    final keep = RegExp(r'[\p{L}\p{N}]', unicode: true);
    var end = piece.start;
    var i = 0;
    while (i < piece.text.length) {
      final next = _advance(piece.text, i);
      if (keep.hasMatch(piece.text.substring(i, next))) {
        end = piece.start + next;
      }
      i = next;
    }
    if (end == piece.start) return split >= piece.end;
    return split >= end;
  }

  Widget _characters() {
    final linked = style.copyWith(
      color: AppColors.greenDark,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dashed,
      decorationColor: AppColors.green,
      decorationThickness: 2,
    );
    TextStyle blankStyle(bool filled) {
      return style.copyWith(
        color: filled ? AppColors.blue : AppColors.muted,
        fontWeight: filled ? FontWeight.w800 : null,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
        decorationColor: filled ? AppColors.blue : AppColors.muted,
        decorationThickness: 2,
      );
    }

    var marked = piece.text.length;
    TextStyle? markedStyle;
    if (blank != null) {
      marked = (blank!.end - piece.start).clamp(0, piece.text.length);
      markedStyle = blankStyle(blank!.filled);
    } else if (match != null) {
      marked = (match!.end - piece.start).clamp(0, piece.text.length);
      markedStyle = linked;
    }
    final plain = marked == piece.text.length && markedStyle == null;
    if (plain && !karaokeOn) {
      return Text(piece.text, style: style);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (marked > 0)
            _span(piece.text.substring(0, marked), piece.start, markedStyle),
          if (marked < piece.text.length)
            _span(piece.text.substring(marked), piece.start + marked, null),
        ],
      ),
    );
  }

  InlineSpan _span(String text, int globalStart, TextStyle? extra) {
    final base = extra ?? style;
    if (!karaokeOn) return TextSpan(text: text, style: extra);
    final cut = (split - globalStart).clamp(0, text.length);
    if (cut <= 0) return TextSpan(text: text, style: extra);
    if (cut >= text.length) {
      return TextSpan(
        text: text,
        style: base.copyWith(color: sungColor),
      );
    }
    return TextSpan(
      children: [
        TextSpan(
          text: text.substring(0, cut),
          style: base.copyWith(color: sungColor),
        ),
        TextSpan(text: text.substring(cut), style: extra),
      ],
    );
  }
}
