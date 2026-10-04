import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/platform/harmony.dart';
import '../../theme/app_theme.dart';
import '../lessons/domain/lesson_models.dart';
import '../lessons/presentation/lesson_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text('粤语伴 YueBuddy'),
      ),
      body: FutureBuilder<CourseCatalog>(
        future: scope.lessons.loadCatalog(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('课程目录加载失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lessons = snapshot.data!.lessons;
          return ListenableBuilder(
            listenable: scope.speech,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final frame = AppFrame(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  );
                  final columns = frame.homeColumns;
                  final horizontal = frame.pagePadding;
                  final sectionGap = frame.isShort ? 12.0 : 20.0;
                  if (columns <= 1) {
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        frame.topInset,
                        horizontal,
                        frame.bottomInset,
                      ),
                      children: [
                        if (!isHarmonyOs && !scope.speech.isCantoneseAvailable)
                          const _TtsWarningCard(),
                        _HeroCard(dense: frame.isShort),
                        SizedBox(height: sectionGap),
                        const Text(
                          '课程大纲',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < lessons.length; i++)
                          _LessonTile(summary: lessons[i], index: i),
                      ],
                    );
                  }
                  final grid = CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          frame.topInset,
                          horizontal,
                          0,
                        ),
                        sliver: SliverList.list(
                          children: [
                            if (!isHarmonyOs &&
                                !scope.speech.isCantoneseAvailable)
                              const _TtsWarningCard(),
                            _HeroCard(dense: frame.isShort),
                            SizedBox(height: sectionGap),
                            const Text(
                              '课程大纲',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          0,
                          horizontal,
                          frame.bottomInset,
                        ),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 104,
                              ),
                          itemCount: lessons.length,
                          itemBuilder: (context, i) => _LessonTile(
                            summary: lessons[i],
                            index: i,
                            compact: false,
                          ),
                        ),
                      ),
                    ],
                  );
                  // On 1920 the three tiles would stretch into strips.
                  // Cap the grid and center it inside the full-bleed page.
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: frame.homeGridMaxWidth + horizontal * 2,
                      ),
                      child: grid,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(dense ? 14 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF58CC02), Color(0xFF89E219)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '前三课已开放',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: dense ? 20 : 22,
            ),
          ),
          SizedBox(height: dense ? 4 : 6),
          Text(
            '看词句、听老师录音、跟读复习。先从「互相認識」「民以食為天」或「溝通交流」开始。',
            style: TextStyle(
              color: Colors.white,
              fontSize: dense ? 14 : 15,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TtsWarningCard extends StatelessWidget {
  const _TtsWarningCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.orange, width: 2),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.volume_off_rounded, color: AppColors.orange),
          SizedBox(width: 10),
          Expanded(
            child: const Text(
              '这台设备没有粤语语音。请在系统设置中下载「中文（香港）」语音。不会用普通话代替朗读。',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.summary,
    required this.index,
    this.compact = true,
  });

  final LessonSummary summary;
  final int index;
  final bool compact;

  static const _accents = [
    AppColors.green,
    AppColors.orange,
    AppColors.blue,
    AppColors.purple,
    Color(0xFFFF6B9D),
    Color(0xFF00CD9C),
  ];

  static const _icons = <String, IconData>{
    'l1': Icons.waving_hand_rounded,
    'l2': Icons.restaurant_rounded,
    'l3': Icons.forum_rounded,
    'l4': Icons.directions_run_rounded,
    'l5': Icons.favorite_rounded,
    'l6': Icons.flag_rounded,
  };

  static IconData iconFor(String id) => _icons[id] ?? Icons.menu_book_rounded;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final accent = _accents[index % _accents.length];
    final locked = !summary.isAvailable;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.medium(context),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 12 : 0),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.line, width: 2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () async {
              if (locked) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('第${summary.number}课即将开放 · ${summary.date}'),
                  ),
                );
                return;
              }
              final loaded = await scope.lessons.loadLesson(summary.id);
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LessonScreen(lesson: loaded),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: locked ? AppColors.line : accent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      locked ? Icons.lock_rounded : iconFor(summary.id),
                      color: locked ? AppColors.muted : Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          locked ? '${summary.date} · 即将开放' : summary.date,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    locked
                        ? Icons.schedule_rounded
                        : Icons.chevron_right_rounded,
                    color: AppColors.muted,
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
