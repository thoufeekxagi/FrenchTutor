import 'package:flutter/material.dart';
import 'design/app_theme.dart';
import 'screens/main_tab_screen.dart';

class FrenchTutorApp extends StatelessWidget {
  const FrenchTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParleSprint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(),
      scrollBehavior: const AppScrollBehavior(),
      home: const MainTabScreen(),
    );
  }
}
