import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/database_provider.dart';
import '../widgets/adaptive/adaptive.dart';
import '../widgets/floating_notetaker.dart';
import 'home/dashboard_screen.dart';
import 'labs/labs_screen.dart';
import 'path/path_screen.dart';
import 'progress/progress_screen.dart';
import 'scan/scan_screen.dart';

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
      const ScanScreen(),
      const ProgressScreen(),
    ];
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: screens),
          FloatingNotetakerOverlay(state: notetaker),
        ],
      ),
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
          items: const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.house),
              activeIcon: Icon(CupertinoIcons.house_fill),
              label: 'Today',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.map),
              activeIcon: Icon(CupertinoIcons.map_fill),
              label: 'Path',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.square_grid_2x2),
              activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
              label: 'Practice',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.camera_on_rectangle),
              activeIcon: Icon(CupertinoIcons.camera_on_rectangle_fill),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.chart_bar_square),
              activeIcon: Icon(CupertinoIcons.chart_bar_square_fill),
              label: 'Progress',
            ),
          ],
        ),
      ),
    );
  }
}
