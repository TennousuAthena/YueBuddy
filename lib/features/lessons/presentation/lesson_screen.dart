import 'package:flutter/material.dart';

import '../../../core/layout/breakpoints.dart';
import '../../../theme/app_theme.dart';
import '../domain/lesson_models.dart';
import 'module_screen.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({super.key, required this.lesson, this.initialModuleId});

  final Lesson lesson;
  final String? initialModuleId;

  static const _icons = <String, IconData>{
    'l1-basics': Icons.record_voice_over_rounded,
    'l1-daily': Icons.waving_hand_rounded,
    'l1-dialogue-1': Icons.forum_rounded,
    'l1-contact': Icons.call_rounded,
    'l1-campus': Icons.location_city_rounded,
    'l1-datetime': Icons.schedule_rounded,
    'l1-dialogue-2': Icons.chat_bubble_rounded,
    'l2-eat': Icons.restaurant_rounded,
    'l2-daily': Icons.waving_hand_rounded,
    'l2-breakfast': Icons.free_breakfast_rounded,
    'l2-drinks': Icons.local_cafe_rounded,
    'l2-tea': Icons.cookie_rounded,
    'l2-meals': Icons.dinner_dining_rounded,
    'l2-dialogue-1': Icons.forum_rounded,
    'l2-dialogue-2': Icons.celebration_rounded,
    'l2-other': Icons.menu_book_rounded,
  };

  static const _colors = <String, Color>{
    'l1-basics': AppColors.green,
    'l1-daily': AppColors.orange,
    'l1-dialogue-1': AppColors.blue,
    'l1-contact': AppColors.purple,
    'l1-campus': Color(0xFF00CD9C),
    'l1-datetime': Color(0xFFFF6B9D),
    'l1-dialogue-2': AppColors.blue,
    'l2-eat': AppColors.orange,
    'l2-daily': AppColors.green,
    'l2-breakfast': Color(0xFFFF9600),
    'l2-drinks': AppColors.blue,
    'l2-tea': Color(0xFFFF6B9D),
    'l2-meals': Color(0xFF00CD9C),
    'l2-dialogue-1': AppColors.purple,
    'l2-dialogue-2': AppColors.blue,
    'l2-other': AppColors.green,
  };

  static IconData iconFor(String id) =>
      _icons[id] ?? Icons.menu_book_rounded;
  static Color colorFor(String id) => _colors[id] ?? AppColors.green;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  String? _selectedModuleId;

  @override
  void initState() {
    super.initState();
    _selectedModuleId =
        widget.initialModuleId ?? widget.lesson.modules.firstOrNull?.id;
  }

  LessonModule get _selectedModule {
    final modules = widget.lesson.modules;
    return modules.firstWhere(
      (m) => m.id == _selectedModuleId,
      orElse: () => modules.first,
    );
  }

  void _openModule(BuildContext context, LessonModule module) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ModuleScreen(module: module),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('第${widget.lesson.number}課 ${widget.lesson.title}')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (AppBreakpoints.isMasterDetailWidth(constraints.maxWidth)) {
            return _buildMasterDetail(context);
          }
          return _buildSinglePane(context, constraints.maxWidth);
        },
      ),
    );
  }

  Widget _buildSinglePane(BuildContext context, double maxWidth) {
    final layout = AppBreakpoints.classForWidth(maxWidth);
    final columns = layout == LayoutClass.compact ? 1 : 2;
    final horizontal = layout == LayoutClass.compact
        ? 20.0
        : 24.0;
    if (columns <= 1) {
      return ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
        children: [
          _LessonHeader(lesson: widget.lesson),
          const SizedBox(height: 18),
          for (var i = 0; i < widget.lesson.modules.length; i++)
            _ModuleCard(
              module: widget.lesson.modules[i],
              index: i,
              icon: LessonScreen.iconFor(widget.lesson.modules[i].id),
              color: LessonScreen.colorFor(widget.lesson.modules[i].id),
              selected: false,
              onTap: () =>
                  _openModule(context, widget.lesson.modules[i]),
            ),
        ],
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
          sliver: SliverList.list(
            children: [
              _LessonHeader(lesson: widget.lesson),
              const SizedBox(height: 18),
            ],
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 32),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 104,
            ),
            itemCount: widget.lesson.modules.length,
            itemBuilder: (context, i) => _ModuleCard(
              module: widget.lesson.modules[i],
              index: i,
              icon: LessonScreen.iconFor(widget.lesson.modules[i].id),
              color: LessonScreen.colorFor(widget.lesson.modules[i].id),
              selected: false,
              gridMode: true,
              onTap: () =>
                  _openModule(context, widget.lesson.modules[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMasterDetail(BuildContext context) {
    final modules = widget.lesson.modules;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(32, 8, 12, 32),
            children: [
              _LessonHeader(lesson: widget.lesson),
              const SizedBox(height: 16),
              for (var i = 0; i < modules.length; i++)
                _ModuleCard(
                  module: modules[i],
                  index: i,
                  icon: LessonScreen.iconFor(modules[i].id),
                  color: LessonScreen.colorFor(modules[i].id),
                  selected: modules[i].id == _selectedModule.id,
                  onTap: () =>
                      setState(() => _selectedModuleId = modules[i].id),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 2, thickness: 2, color: AppColors.line),
        Expanded(
          child: ModuleScreen(
            key: ValueKey('embedded-${_selectedModule.id}'),
            module: _selectedModule,
            embedded: true,
          ),
        ),
      ],
    );
  }
}

class _LessonHeader extends StatelessWidget {
  const _LessonHeader({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${lesson.date} · ${lesson.itemCount} 条',
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '选一个模块，把课上的句子再听一遍。',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.index,
    required this.icon,
    required this.color,
    required this.onTap,
    this.selected = false,
    this.gridMode = false,
  });

  final LessonModule module;
  final int index;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool selected;
  final bool gridMode;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('module-${module.id}-$index'),
      tween: Tween(begin: 0, end: 1),
      duration: Motion.medium(context),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: gridMode ? 0 : 12),
        child: Material(
          color: selected ? AppColors.green.withValues(alpha: 0.08) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: selected ? AppColors.green : AppColors.line,
              width: 2,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          module.subtitle,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: selected ? AppColors.greenDark : AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
