import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'design/app_theme.dart';
import 'providers/database_provider.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/main_tab_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/auth_service.dart';

class FrenchTutorApp extends StatelessWidget {
  const FrenchTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParleSprint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(),
      scrollBehavior: const AppScrollBehavior(),
      home: const AuthGate(),
    );
  }
}

/// The single decision point for what the user sees, re-evaluated on every
/// auth state change AND when onboarding completes. Deliberate ORDER — the
/// learner experiences value first, commits second:
///   1. not onboarded -> [OnboardingScreen] (goal, level, tutor — no account
///      wall in front of the product)
///   2. onboarded but no session -> [AuthScreen] ("create an account to save
///      your progress" — the natural close of onboarding)
///   3. onboarded + session -> [MainTabScreen]
///
/// Everything renders INSIDE this gate (no pushReplacement out of it) so a
/// later sign-out from Settings always lands back on the sign-in screen —
/// with the old push-based flow the gate was unmounted after onboarding and
/// sign-out navigated nowhere.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _hasSession = AuthService.shared.currentSession != null;
  StreamSubscription<AuthState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = AuthService.shared.onAuthStateChange.listen(
      _onAuthStateChange,
    );
  }

  void _onAuthStateChange(AuthState state) {
    final session = state.session;
    if (session != null) {
      // Stamp the local profile with the Supabase user id (PILOT_PLAN.md
      // Phase 5's "local rows adopt the new user_id" step). Idempotent —
      // safe to run on every signed-in event, not just the very first one.
      try {
        ref.read(learningStoreProvider).linkSupabaseUser(session.user.id);
      } catch (_) {
        // A local DB hiccup must never block showing the signed-in user
        // their app — the link is retried on the next auth event regardless.
      }
    }
    if (!mounted) return;
    setState(() => _hasSession = session != null);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = ref.read(learningStoreProvider).profile().isOnboarded;
    if (!onboarded) {
      return OnboardingScreen(onFinished: () => setState(() {}));
    }
    if (!_hasSession) return const AuthScreen();
    return const MainTabScreen();
  }
}
