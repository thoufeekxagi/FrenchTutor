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
import 'screens/onboarding/speak_onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/gemini_live_service.dart';
import 'services/revenue_cat_service.dart';
import 'services/sync_service.dart';

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
///   1. not onboarded -> [SpeakOnboardingScreen] (goal, level, tutor — no account
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

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  bool _hasSession = AuthService.shared.currentSession != null;
  bool _explicitlySignedOut = false;
  bool _signOutMarkerLoaded = false;
  bool? _aiConsented;
  bool _isRestoringAccount = AuthService.shared.currentSession != null;
  bool _requiresInstallOnboarding = true;
  String? _restoreInFlightUserId;
  String? _restoredUserId;
  Future<void>? _resumeSyncInFlight;
  StreamSubscription<AuthState>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requiresInstallOnboarding = !ref
        .read(learningStoreProvider)
        .profile()
        .isOnboarded;
    _subscription = AuthService.shared.onAuthStateChange.listen(
      _onAuthStateChange,
    );
    AuthService.shared.localAuthRevision.addListener(_onLocalAuthRevision);
    final initialSession = AuthService.shared.currentSession;
    if (initialSession != null && !_requiresInstallOnboarding) {
      _isRestoringAccount = _restoredUserId != initialSession.user.id;
      _prepareSignedInLocalState(initialSession.user.id);
      _startAccountRestore(initialSession.user.id);
    }
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Route-level observers normally close their own Live service. Keep a
      // root guard as well: a forgotten observer must never leave a billable
      // Gemini socket running after the app is backgrounded or terminated.
      GeminiLiveService.disconnectActiveSocket();
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumePendingCourseWork());
    }
  }

  Future<void> _resumePendingCourseWork() {
    final existing = _resumeSyncInFlight;
    if (existing != null) return existing;
    final session = AuthService.shared.currentSession;
    if (session == null || _requiresInstallOnboarding) {
      return Future<void>.value();
    }

    late final Future<void> run;
    run = _resumePendingCourseWorkNow().whenComplete(() {
      if (identical(_resumeSyncInFlight, run)) _resumeSyncInFlight = null;
    });
    _resumeSyncInFlight = run;
    return run;
  }

  Future<void> _resumePendingCourseWorkNow() async {
    try {
      final profile = ref.read(learningStoreProvider).profile();
      if (!profile.isOnboarded) return;
      final sync = ref.read(syncServiceProvider);
      await sync.drainOutbox();
      final plan = ref
          .read(adaptiveCourseStoreProvider)
          .ensureCurrentPlan(profile);
      // Course AI generation is user-triggered only. Resuming the app must
      // never spend provider credits in the background.
      await sync.syncAdaptiveCoursePlan(plan);
    } catch (error, stackTrace) {
      debugPrint('Course resume failed: $error\n$stackTrace');
    }
  }

  void _onLocalAuthRevision() {
    if (!mounted || AuthService.shared.currentSession != null) return;
    setState(() {
      _hasSession = false;
      _explicitlySignedOut = true;
      _signOutMarkerLoaded = true;
      _isRestoringAccount = false;
      _restoreInFlightUserId = null;
      _restoredUserId = null;
    });
  }

  /// Makes the local account cache safe to use before any remote request
  /// starts. In particular, a fresh install has to create its profile row
  /// before the user id can be linked and the remote profile can be restored.
  void _prepareSignedInLocalState(String userId) {
    try {
      final learningStore = ref.read(learningStoreProvider);
      // This also materializes the row on a fresh install. Linking must happen
      // after that read or the update-only adoption query has nothing to link.
      learningStore.profile();
      learningStore.linkSupabaseUser(userId);
      ref.read(adaptiveCourseStoreProvider).linkSupabaseUser(userId);
    } catch (_) {
      // Keep the account behind the restore gate when the local cache cannot
      // be prepared. The restore pass will retry through the normal path.
    }
  }

  void _onAuthStateChange(AuthState state) {
    final session = state.session;
    if (session != null) {
      _explicitlySignedOut = false;
      _signOutMarkerLoaded = true;
      _isRestoringAccount = _restoredUserId != session.user.id;
      _prepareSignedInLocalState(session.user.id);
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
      // Restore every server-side learner record (vocab/session/mission/
      // competency state) into the local cache. The signed-in shell stays
      // behind the restore gate until the profile and adaptive route are
      // known to be coherent; token refreshes for an already-restored user do
      // not restart this gate.
      if (!_requiresInstallOnboarding && _restoredUserId != session.user.id) {
        _startAccountRestore(session.user.id);
      }
    } else {
      _isRestoringAccount = false;
      _restoreInFlightUserId = null;
      _restoredUserId = null;
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

  void _startAccountRestore(String restoringUserId) {
    if (_restoreInFlightUserId == restoringUserId) return;
    _restoreInFlightUserId = restoringUserId;
    unawaited(_restoreAndSeedContent(restoringUserId));
  }

  void _retryAccountRestore() {
    final session = AuthService.shared.currentSession;
    if (session == null) return;
    setState(() => _isRestoringAccount = true);
    _startAccountRestore(session.user.id);
  }

  void _finishInstallOnboarding() {
    final session = AuthService.shared.currentSession;
    setState(() {
      _requiresInstallOnboarding = false;
      if (session != null) _isRestoringAccount = true;
    });
    if (session != null) {
      _prepareSignedInLocalState(session.user.id);
      _startAccountRestore(session.user.id);
    }
  }

  Future<void> _restoreAndSeedContent(String restoringUserId) async {
    SyncHydrationResult? hydration;
    try {
      try {
        hydration = await ref.read(syncServiceProvider).hydrateAfterSignIn();
      } catch (_) {
        // Keep the account behind the restore gate. The finally block exposes
        // a retry action once the failed request has unwound.
      }
      final restoreReady =
          hydration?.profileFetchSucceeded == true &&
          hydration?.adaptiveCourseFetchSucceeded == true;
      // The optional onboarding trial was recorded while signed out, so its
      // per-write sync calls intentionally no-op. Claim and upload those
      // learner-owned rows explicitly once this account is authenticated. It
      // is deliberately background work: local Course creation must not wait
      // on a network timeout after signup.
      unawaited(
        ref.read(syncServiceProvider).syncAdoptedOnboardingTrials().catchError((
          error,
          stackTrace,
        ) {
          debugPrint('Onboarding trial adoption failed: $error\n$stackTrace');
        }),
      );
      if (restoreReady) {
        try {
          // Onboarding can finish before account creation. After remote state
          // is hydrated, explicitly push the current route so a new account
          // does not lose its pre-auth adaptive course.
          final profile = ref.read(learningStoreProvider).profile();
          if (profile.isOnboarded) {
            final plan = ref
                .read(adaptiveCourseStoreProvider)
                .ensureCurrentPlan(profile);
            final sync = ref.read(syncServiceProvider);
            await sync.syncProfile(profile);
            await sync.drainOutbox();
            final coursePersisted = await sync.syncAdaptiveCoursePlan(plan);
            // Course preparation is independent from lesson taps. Do not
            // hold account restoration on an AI provider response; the five
            // fixed foundation lessons remain immediately usable while the
            // persisted personalized batch is prepared and hydrated.
            if (!coursePersisted) {
              debugPrint(
                'Course preparation deferred until its persisted plan retry '
                'succeeds.',
              );
            }
          }
        } catch (error, stackTrace) {
          debugPrint(
            'Adaptive course restore/push failed: $error\n$stackTrace',
          );
        }
      }
      // Hydration updates SQLite directly, so no provider notification is
      // emitted automatically. Rebuild the gate once the profile and course
      // route are ready so a fresh install cannot remain on stale onboarding.
      final profile = ref.read(learningStoreProvider).profile();
      final profileRestoreCompleted =
          restoreReady &&
          (profile.isOnboarded ||
              (hydration?.profileFetchSucceeded == true &&
                  hydration?.profileFound == false));
      if (mounted &&
          AuthService.shared.currentSession?.user.id == restoringUserId &&
          profileRestoreCompleted) {
        setState(() {
          _isRestoringAccount = false;
          _restoredUserId = restoringUserId;
        });
      }
      if (profileRestoreCompleted) {
        try {
          await ref
              .read(starterContentServiceProvider)
              .ensureSeededForCurrentUser();
          // Audio must remain demand-driven. Warming the entire grammar
          // catalog here opened dozens of Gemini Live sockets after login,
          // even when the learner never opened Grammar.
        } catch (error, stackTrace) {
          debugPrint('Starter content seeding failed: $error\n$stackTrace');
        }
      }
    } finally {
      if (_restoreInFlightUserId == restoringUserId) {
        _restoreInFlightUserId = null;
        if (mounted &&
            AuthService.shared.currentSession?.user.id == restoringUserId &&
            _isRestoringAccount) {
          // The restore failed or returned incomplete critical data. Rebuild
          // so the visible gate exposes its retry action instead of leaving a
          // permanently spinning screen with no recovery path.
          setState(() {});
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (_requiresInstallOnboarding) {
      return SpeakOnboardingScreen(onFinished: _finishInstallOnboarding);
    }
    if (_hasSession && _isRestoringAccount) {
      return _RestoringProgressView(
        onRetry: _restoreInFlightUserId == null ? _retryAccountRestore : null,
      );
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

/// Shown while a signed-in account restores its profile and course route.
/// This keeps every startup route read behind the same hydration boundary.
class _RestoringProgressView extends StatelessWidget {
  const _RestoringProgressView({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090B),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/pulse_sprint_logo.png',
              width: 128,
              height: 128,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 22),
            const CircularProgressIndicator(color: Color(0xFFB8F36B)),
            const SizedBox(height: 14),
            const Text(
              'Restoring your progress…',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
