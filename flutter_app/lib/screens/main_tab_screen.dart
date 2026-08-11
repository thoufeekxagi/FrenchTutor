import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          PSHaptics.selection();
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(CupertinoIcons.house),
            selectedIcon: Icon(CupertinoIcons.house_fill),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.map),
            selectedIcon: Icon(CupertinoIcons.map_fill),
            label: 'Path',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.square_grid_2x2),
            selectedIcon: Icon(CupertinoIcons.square_grid_2x2_fill),
            label: 'Practice',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.camera_on_rectangle),
            selectedIcon: Icon(CupertinoIcons.camera_on_rectangle_fill),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.chart_bar_square),
            selectedIcon: Icon(CupertinoIcons.chart_bar_square_fill),
            label: 'Progress',
          ),
        ],
      ),
    );
  }
}
