import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'home/dashboard_screen.dart';
import 'labs/labs_screen.dart';
import 'mocks/mocks_screen.dart';
import 'progress/progress_screen.dart';
import 'settings/settings_screen.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;

  static const _screens = [
    DashboardScreen(),
    LabsScreen(),
    MocksScreen(),
    ProgressScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
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
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Labs'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded), label: 'Mocks'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart_rounded), label: 'Progress'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
