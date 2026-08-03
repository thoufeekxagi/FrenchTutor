import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../design/app_router.dart';
import '../providers/database_provider.dart';
import '../widgets/adaptive/adaptive.dart';
import '../widgets/floating_notetaker.dart';
import '../widgets/web/web_app_shell.dart';
import 'home/dashboard_screen.dart';
import 'labs/labs_screen.dart';
import 'path/path_screen.dart';
import 'progress/progress_screen.dart';
import 'settings/settings_screen.dart';

/// Primary navigation destinations, defined once and shared between the
/// mobile bottom tab bar and the desktop sidebar (`WebAppShell`) so
/// neither shell can drift out of sync with the other.
const _destinations = [
  NavDestination(
    icon: CupertinoIcons.house,
    activeIcon: CupertinoIcons.house_fill,
    label: 'Today',
  ),
  NavDestination(
    icon: CupertinoIcons.map,
    activeIcon: CupertinoIcons.map_fill,
    label: 'Path',
  ),
  NavDestination(
    icon: CupertinoIcons.square_grid_2x2,
    activeIcon: CupertinoIcons.square_grid_2x2_fill,
    label: 'Practice',
  ),
  NavDestination(
    icon: CupertinoIcons.chart_bar_square,
    activeIcon: CupertinoIcons.chart_bar_square_fill,
    label: 'Progress',
  ),
];

class MainTabScreen extends ConsumerStatefulWidget {
  const MainTabScreen({super.key});

  @override
  ConsumerState<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends ConsumerState<MainTabScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final notetaker = ref.watch(notetakerStateProvider);
    // Built fresh every rebuild (not a static const list) so `isActive` can
    // be threaded down — every tab stays alive forever inside IndexedStack,
    // so completing something on one tab (e.g. Practice) and switching back
    // to Today previously never re-read the sessions table: `DashboardScreen`
    // /`TodayMissionWidget` only ever reloaded via their OWN internal
    // push-and-await calls, never just from becoming visible again.
    final screens = [
      DashboardScreen(isActive: _currentIndex == 0),
      const PathScreen(),
      const LabsScreen(),
      const ProgressScreen(),
    ];
    final body = Stack(
      children: [
        IndexedStack(index: _currentIndex, children: screens),
        FloatingNotetakerOverlay(state: notetaker),
      ],
    );

    final isDesktop =
        MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded;
    if (isDesktop) {
      return WebAppShell(
        destinations: _destinations,
        currentIndex: _currentIndex,
        onSelect: (index) => setState(() => _currentIndex = index),
        topBarActions: [
          WebIconButton(
            icon: CupertinoIcons.gear,
            tooltip: 'Settings',
            onTap: () => AppRouter.push(context, (_) => const SettingsScreen()),
          ),
        ],
        body: body,
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Passeport.card.withValues(alpha: 0.96),
          border: Border(top: BorderSide(color: Passeport.hairline)),
        ),
        child: CupertinoTabBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            PSHaptics.selection();
            setState(() => _currentIndex = index);
          },
          backgroundColor: Colors.transparent,
          activeColor: Passeport.maroon,
          inactiveColor: Passeport.slateDim,
          iconSize: 24,
          height: 54,
          items: [
            for (final d in _destinations)
              BottomNavigationBarItem(
                icon: Icon(d.icon),
                activeIcon: Icon(d.activeIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}
