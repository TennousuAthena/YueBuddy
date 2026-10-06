import 'package:flutter/material.dart';

import '../core/layout/breakpoints.dart';
import '../features/home/home_screen.dart';
import '../features/practice/practice_screen.dart';
import '../features/settings/settings_screen.dart';
import '../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = [HomeScreen(), PracticeScreen(), SettingsScreen()];

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.school_outlined),
      selectedIcon: Icon(Icons.school_rounded),
      label: Text('学习'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.forum_outlined),
      selectedIcon: Icon(Icons.forum_rounded),
      label: Text('智能练习'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('设置'),
    ),
  ];

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppBreakpoints.classForWidth(constraints.maxWidth);
        if (layout == LayoutClass.compact) {
          return Scaffold(
            body: IndexedStack(index: _index, children: _pages),
            bottomNavigationBar: _DuoNavBar(
              index: _index,
              onSelect: _select,
            ),
          );
        }
        final extended = layout.isDesktop;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  extended: extended,
                  minWidth: 72,
                  minExtendedWidth: 200,
                  groupAlignment: 0,
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.green.withValues(alpha: 0.16),
                  selectedIconTheme: const IconThemeData(
                    color: AppColors.greenDark,
                  ),
                  selectedLabelTextStyle: const TextStyle(
                    color: AppColors.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                  unselectedIconTheme: const IconThemeData(
                    color: AppColors.muted,
                  ),
                  unselectedLabelTextStyle: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                  onDestinationSelected: _select,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      child: Image(
                        image: AssetImage('assets/icon/icon_square.png'),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  destinations: _destinations,
                ),
                const VerticalDivider(
                  width: 2,
                  thickness: 2,
                  color: AppColors.line,
                ),
                Expanded(
                  child: IndexedStack(index: _index, children: _pages),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DuoNavBar extends StatelessWidget {
  const _DuoNavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _DuoNavItem(
                label: '学习',
                icon: Icons.school_rounded,
                selected: index == 0,
                onTap: () => onSelect(0),
              ),
              _DuoNavItem(
                label: '智能练习',
                icon: Icons.forum_rounded,
                selected: index == 1,
                onTap: () => onSelect(1),
              ),
              _DuoNavItem(
                label: '设置',
                icon: Icons.settings_rounded,
                selected: index == 2,
                onTap: () => onSelect(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuoNavItem extends StatelessWidget {
  const _DuoNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.green : AppColors.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
