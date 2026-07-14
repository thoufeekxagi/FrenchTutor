import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/theme.dart';
import 'screens/main_tab_screen.dart';

class FrenchTutorApp extends StatelessWidget {
  const FrenchTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'French Tutor',
      debugShowCheckedModeBanner: false,
      theme: Passeport.themeData(),
      home: const MainTabScreen(),
    );
  }
}
