import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../providers/database_provider.dart';
import '../widgets/floating_notetaker.dart';
import 'home/dashboard_screen.dart';
import 'labs/labs_screen.dart';
import 'progress/progress_screen.dart';
import 'settings/settings_screen.dart';

class MainTabScreen extends ConsumerStatefulWidget {
  const MainTabScreen({super.key});

  @override
  ConsumerState<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends ConsumerState<MainTabScreen> {
  int _currentIndex = 0;

  static const _screens = [
    DashboardScreen(),
    LabsScreen(),
    ProgressScreen(),
    SettingsScreen(),
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Passeport.card,
        selectedItemColor: Passeport.maroon,
        unselectedItemColor: Passeport.slate,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.house_fill), label: 'Today'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.square_grid_2x2), label: 'Practice'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.chart_bar_square), label: 'Progress'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.gear_alt_fill), label: 'Settings'),
        ],
      ),
    );
  }
}
