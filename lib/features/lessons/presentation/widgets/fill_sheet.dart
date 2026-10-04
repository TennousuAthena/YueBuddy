import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/app_shell.dart';
import '../../../../theme/app_theme.dart';
import '../../domain/fill_blanks.dart';
import '../../domain/lesson_models.dart';

String _titleFor(BlankKind kind) {
  return switch (kind) {
    BlankKind.name => '你的名字',
    BlankKind.phone => '电话号码',
    BlankKind.month => '月份',
    BlankKind.day => '日期',
    BlankKind.weekday => '星期',
    BlankKind.origin => '你来自哪里',
    BlankKind.other => '填空',
  };
}

String _hintFor(BlankKind kind) {
  return switch (kind) {
    BlankKind.name => '例如：陈小明',
    BlankKind.phone => '例如：13800138000',
    BlankKind.month => '1–12',
    BlankKind.day => '1–31',
    BlankKind.weekday => '',
    BlankKind.origin => '例如：成都人',
    BlankKind.other => '填入你的内容',
  };
}

TextInputType _keyboardFor(BlankKind kind) {
  return switch (kind) {
    BlankKind.phone => TextInputType.phone,
    BlankKind.month => TextInputType.number,
    BlankKind.day => TextInputType.number,
    BlankKind.name => TextInputType.name,
    BlankKind.weekday => TextInputType.text,
    BlankKind.origin => TextInputType.text,
    BlankKind.other => TextInputType.text,
  };
}

/// Month/day range guard; other kinds accept anything non-empty.
String? _validate(BlankKind kind, String value) {
  final text = value.trim();
  if (text.isEmpty) return '内容不能为空';
  final number = int.tryParse(text);
  if (kind == BlankKind.month &&
      (number == null || number < 1 || number > 12)) {
    return '月份是 1–12';
  }
  if (kind == BlankKind.day && (number == null || number < 1 || number > 31)) {
    return '日期是 1–31';
  }
  return null;
}

Future<void> showFillSheet({
  required BuildContext context,
  required LessonItem item,
  required FilledBlank blank,
}) {
  final scope = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0x803C3C3C),
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: AppShell.contentWidth),
    builder: (context) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: _FillSheet(item: item, blank: blank, scope: scope),
      );
    },
  );
}

class _FillSheet extends StatefulWidget {
  const _FillSheet({
    required this.item,
    required this.blank,
    required this.scope,
  });

  final LessonItem item;
  final FilledBlank blank;
  final AppScope scope;

  @override
  State<_FillSheet> createState() => _FillSheetState();
}

class _FillSheetState extends State<_FillSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final stored = widget.scope.settings.blankValue(
      widget.item.id,
      widget.blank.index,
    );
    _controller = TextEditingController(text: stored ?? widget.blank.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _options {
    final fill = widget.item.fill;
    final index = widget.blank.index;
    if (widget.blank.kind == BlankKind.origin &&
        (index < 0 || index >= fill.length || fill[index].options.isEmpty)) {
      return kOriginSuggestions;
    }
    if (index < 0 || index >= fill.length) return const [];
    return fill[index].options;
  }

  Future<void> _save(String value) async {
    final error = _validate(widget.blank.kind, value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (widget.blank.kind == BlankKind.origin) {
      await widget.scope.settings.setOrigin(value);
    } else {
      await widget.scope.settings.setBlankValue(
        widget.item.id,
        widget.blank.index,
        value,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reset() async {
    if (widget.blank.kind == BlankKind.origin) {
      await widget.scope.settings.setOrigin('');
    } else {
      await widget.scope.settings.setBlankValue(
        widget.item.id,
        widget.blank.index,
        '',
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.paddingOf(context).bottom +
        MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
                      color: AppColors.blue.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _titleFor(widget.blank.kind),
                      style: const TextStyle(
                        color: AppColors.blue,
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
              if (widget.blank.kind == BlankKind.weekday)
                _WeekdayPicker(current: widget.blank.value, onPick: _save)
              else ...[
                if (_options.isNotEmpty) ...[
                  _OptionPicker(
                    options: _options,
                    current: widget.blank.value,
                    onPick: _save,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: _keyboardFor(widget.blank.kind),
                  inputFormatters:
                      widget.blank.kind == BlankKind.month ||
                          widget.blank.kind == BlankKind.day
                      ? [FilteringTextInputFormatter.digitsOnly]
                      : null,
                  decoration: InputDecoration(
                    hintText: _hintFor(widget.blank.kind),
                    errorText: _error,
                  ),
                  onSubmitted: _save,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _save(_controller.text),
                  child: const Text('保存'),
                ),
              ],
              if (widget.blank.hasOverride) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: _reset, child: const Text('恢复默认')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionPicker extends StatelessWidget {
  const _OptionPicker({
    required this.options,
    required this.current,
    required this.onPick,
  });

  final List<String> options;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option),
            selected: current == option,
            onSelected: (_) => onPick(option),
            selectedColor: AppColors.blue,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w800,
              color: current == option ? Colors.white : AppColors.ink,
            ),
            side: const BorderSide(color: AppColors.line, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
      ],
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.current, required this.onPick});

  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final day in days)
            ChoiceChip(
              label: Text('星期$day'),
              selected: current == day,
              onSelected: (_) => onPick(day),
              selectedColor: AppColors.blue,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w800,
                color: current == day ? Colors.white : AppColors.ink,
              ),
              side: const BorderSide(color: AppColors.line, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
        ],
      ),
    );
  }
}
