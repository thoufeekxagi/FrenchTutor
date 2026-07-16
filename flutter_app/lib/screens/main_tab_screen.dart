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

class MainTabScreen extends ConsumerStatefulWidget {
  const MainTabScreen({super.key});

  @override
  ConsumerState<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends ConsumerState<MainTabScreen> {
  int _currentIndex = 0;

  static const _screens = [
    DashboardScreen(),
    PathScreen(),
    LabsScreen(),
    ProgressScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final notetaker = ref.watch(notetakerStateProvider);
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _screens),
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
