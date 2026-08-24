import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'design/app_theme.dart';
import 'models/pilot_access.dart';
import 'providers/appearance_provider.dart';
import 'providers/database_provider.dart';
import 'screens/auth/speak_auth_screen.dart';
import 'screens/main_tab_screen.dart';
import 'screens/onboarding/ai_consent_screen.dart';
import 'screens/onboarding/v3_onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/revenue_cat_service.dart';

class FrenchTutorApp extends ConsumerWidget {
  const FrenchTutorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    return MaterialApp(
      title: 'ParleSprint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(darkMode: false),
      darkTheme: AppTheme.themeData(darkMode: true),
      themeMode: appearance.darkMode ? ThemeMode.dark : ThemeMode.light,
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
  bool _explicitlySignedOut = false;
  bool _signOutMarkerLoaded = false;
  bool? _aiConsented;
  StreamSubscription<AuthState>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = AuthService.shared.onAuthStateChange.listen(
      _onAuthStateChange,
    );
    AuthService.shared.localAuthRevision.addListener(_onLocalAuthRevision);
    AuthService.shared.wasExplicitlySignedOut().then((value) {
      if (!mounted) return;
      setState(() {
        // A live session always wins over a stale device marker. This also
        // avoids a race if a sign-in completes while preferences are loading.
        _explicitlySignedOut =
            AuthService.shared.currentSession == null && value;
        _signOutMarkerLoaded = true;
      });
    });
    AiConsentScreen.hasConsented().then((value) {
      if (mounted) setState(() => _aiConsented = value);
    });
  }

  void _onLocalAuthRevision() {
    if (!mounted || AuthService.shared.currentSession != null) return;
    setState(() {
      _hasSession = false;
      _explicitlySignedOut = true;
      _signOutMarkerLoaded = true;
    });
  }

  void _onAuthStateChange(AuthState state) {
    final session = state.session;
    if (session != null) {
      _explicitlySignedOut = false;
      _signOutMarkerLoaded = true;
      unawaited(AuthService.shared.clearRememberedSignOut());
      // Apple StoreKit remains the billing authority. RevenueCat uses the
      // Supabase user id only as its stable customer identifier, then sends
      // customer-info updates here whenever a purchase, restore, renewal, or
      // offer-code redemption changes the Apple entitlement.
      ref
          .read(pilotInfrastructureStoreProvider)
          .setEntitlementUser(session.user.id);
      unawaited(
        RevenueCatService.shared.configure(
          appUserId: session.user.id,
          onCustomerInfo: _cacheRevenueCatCustomerInfo,
        ),
      );
      // Stamp the local profile with the Supabase user id (PILOT_PLAN.md
      // Phase 5's "local rows adopt the new user_id" step). Idempotent —
      // safe to run on every signed-in event, not just the very first one.
      try {
        ref.read(learningStoreProvider).linkSupabaseUser(session.user.id);
        ref.read(adaptiveCourseStoreProvider).linkSupabaseUser(session.user.id);
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
      _restoreAndSeedContent();
    } else {
      unawaited(RevenueCatService.shared.logOut());
      final infrastructure = ref.read(pilotInfrastructureStoreProvider);
      infrastructure.clearEntitlements();
    }
    if (!mounted) return;
    setState(() {
      _hasSession = session != null;
      if (state.event == AuthChangeEvent.signedOut) {
        _explicitlySignedOut = true;
        _signOutMarkerLoaded = true;
      }
    });
  }

  void _cacheRevenueCatCustomerInfo(CustomerInfo info) {
    if (!mounted) return;
    final entitlement = info.entitlements.active[parlesprintProEntitlementId];
    final store = ref.read(pilotInfrastructureStoreProvider);
    if (entitlement == null) {
      store.saveEntitlement(
        PilotEntitlement(
          productId: 'none',
          status: PilotEntitlementStatus.inactive,
          source: 'revenuecat_customer_info',
          verifiedAt: DateTime.now().toUtc(),
        ),
      );
    } else {
      store.saveEntitlement(
        PilotEntitlement(
          productId: entitlement.productIdentifier,
          status: PilotEntitlementStatus.active,
          source: 'revenuecat_customer_info',
          expiresAt: entitlement.expirationDate == null
              ? null
              : DateTime.tryParse(entitlement.expirationDate!),
          verifiedAt: DateTime.now().toUtc(),
        ),
      );
    }
    ref.invalidate(subscriptionGateServiceProvider);
    ref.invalidate(pilotAccessServiceProvider);
  }

  void _restoreAndSeedContent() {
    unawaited(() async {
      try {
        await ref
            .read(syncServiceProvider)
            .hydrateAfterSignIn()
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Local starter content still makes the app usable offline; the next
        // auth event retries the remote restore.
      }
      try {
        // Onboarding can finish before account creation. After remote state
        // is hydrated, explicitly push the current route so a new account
        // does not lose its pre-auth adaptive course.
        final profile = ref.read(learningStoreProvider).profile();
        final plan = ref
            .read(adaptiveCourseStoreProvider)
            .ensureCurrentPlan(profile);
        await ref.read(syncServiceProvider).syncAdaptiveCoursePlan(plan);
      } catch (error, stackTrace) {
        debugPrint('Adaptive course restore/push failed: $error\n$stackTrace');
      }
      try {
        await ref
            .read(starterContentServiceProvider)
            .ensureSeededForCurrentUser();
      } catch (error, stackTrace) {
        debugPrint('Starter content seeding failed: $error\n$stackTrace');
      }
    }());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    AuthService.shared.localAuthRevision.removeListener(_onLocalAuthRevision);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_signOutMarkerLoaded) return const _RestoringProgressView();
    // This check intentionally precedes onboarding. Sign-out clears the
    // account's local profile, so evaluating onboarding first would reopen
    // the welcome funnel instead of letting the learner switch accounts.
    if (_explicitlySignedOut ||
        (_hasSession && AuthService.shared.currentSession == null)) {
      return const SpeakAuthScreen(initialSignUp: false);
    }
    final onboarded = ref.read(learningStoreProvider).profile().isOnboarded;
    if (!onboarded) {
      return V3OnboardingScreen(onFinished: () => setState(() {}));
    }
    if (_aiConsented == null) return const _RestoringProgressView();
    if (!_aiConsented!) {
      return AiConsentScreen(
        onAccepted: () => setState(() => _aiConsented = true),
      );
    }
    if (!_hasSession) return const SpeakAuthScreen();
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
      backgroundColor: const Color(0xFF08090B),
      body: Center(
        child: Image.asset(
          'assets/images/pulse_sprint_logo.png',
          width: 128,
          height: 128,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
