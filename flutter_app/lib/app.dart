import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'design/app_theme.dart';
import 'providers/database_provider.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/main_tab_screen.dart';
import 'screens/onboarding/ai_consent_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/revenue_cat_service.dart';
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
///   2. onboarded, AI data-use not yet accepted -> [AiConsentScreen] (must
///      run before any feature can call the AI provider — Apple Guideline
///      5.1.2(i))
///   3. onboarded + consented but no session -> [AuthScreen] ("create an
///      account to save your progress" — the natural close of onboarding)
///   4. onboarded + consented + session -> [MainTabScreen]
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
  bool? _aiConsented;
  StreamSubscription<AuthState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = AuthService.shared.onAuthStateChange.listen(
      _onAuthStateChange,
    );
    AiConsentScreen.hasConsented().then((value) {
      if (mounted) setState(() => _aiConsented = value);
    });
  }

  void _onAuthStateChange(AuthState state) {
    final session = state.session;
    if (session != null) {
      // RevenueCat's SDK is otherwise never initialized anywhere in the app
      // — without this, every paywall load silently sees zero packages
      // forever (fetchOfferings() short-circuits on `!_initialized`), no
      // matter what's configured in App Store Connect/RevenueCat. Using the
      // Supabase user id as the RevenueCat appUserID is what lets the
      // revenuecat-webhook edge function resolve a purchase back to the
      // right `profiles` row. Idempotent (configure() no-ops once already
      // initialized) — safe on every signed-in event.
      RevenueCatService.shared.configure(appUserId: session.user.id);
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
      // competency state) into the local cache — entirely in the background,
      // never blocking the app on a spinner. This fires on EVERY auth event
      // with a session (including a token refresh maybe an hour into an
      // active lesson, not just the first sign-in), so it must never gate
      // what's on screen: a returning user on a fresh install briefly sees
      // whatever is already local (possibly nothing) and it fills in
      // silently as soon as the pull lands, same "best-effort, eventually
      // consistent" contract every other sync call in this app already has.
      ref
          .read(syncServiceProvider)
          .hydrateAfterSignIn()
          .timeout(const Duration(seconds: 8), onTimeout: () {})
          .catchError((_) {});
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
    if (_aiConsented == null) return const _RestoringProgressView();
    if (!_aiConsented!) {
      return AiConsentScreen(
        onAccepted: () => setState(() => _aiConsented = true),
      );
    }
    if (!_hasSession) return const AuthScreen();
    return const MainTabScreen();
  }
}

/// Shown only for the brief, purely-local SharedPreferences read that decides
/// whether AI consent has already been given — never for network sync, which
/// now always runs silently in the background instead of gating any screen.
class _RestoringProgressView extends StatelessWidget {
  const _RestoringProgressView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.primaryDeep,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: DesignTokens.heroGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Restoring your progress…',
                style: DesignTokens.body(15).copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
