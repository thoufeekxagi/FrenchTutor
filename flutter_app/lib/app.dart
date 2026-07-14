import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/app_theme.dart';
import 'providers/database_provider.dart';
import 'screens/main_tab_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

class FrenchTutorApp extends ConsumerWidget {
  const FrenchTutorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One synchronous read at startup: first run goes to onboarding, every
    // later run straight to Home. Onboarding replaces itself when done.
    final onboarded = ref.read(learningStoreProvider).profile().isOnboarded;
    return MaterialApp(
      title: 'ParleSprint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(),
      scrollBehavior: const AppScrollBehavior(),
      home: onboarded ? const MainTabScreen() : const OnboardingScreen(),
    );
  }
}
