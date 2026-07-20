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
import 'design/tokens.dart';

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
  bool _restoring = false;
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
      // Restore every server-side learner record (vocab/session/mission/
      // competency state) into the local cache BEFORE the app is shown, so
      // a returning user on a fresh install or new device sees their real
      // progress and the orchestration layer never plans against an empty
      // learner model. Best-effort with a timeout: a slow/offline network
      // must never strand the learner on a spinner forever — whatever is
      // already local (possibly nothing, on a brand-new device) is what
      // they see, and the outbox/hydrate pass retries on the next launch.
      if (mounted) setState(() => _restoring = true);
      ref
          .read(syncServiceProvider)
          .hydrateAfterSignIn()
          .timeout(const Duration(seconds: 8), onTimeout: () {})
          .catchError((_) {})
          .whenComplete(() {
            if (mounted) setState(() => _restoring = false);
          });
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
    if (_restoring) return const _RestoringProgressView();
    return const MainTabScreen();
  }
}

/// Shown for the brief window between sign-in and local hydration finishing
/// — keeps the learner from ever seeing a flash of an empty/cold-start home
/// screen while their real progress is still being pulled from Supabase.
class _RestoringProgressView extends StatelessWidget {
  const _RestoringProgressView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Restoring your progress…', style: DesignTokens.body(15)),
          ],
        ),
      ),
    );
  }
}
