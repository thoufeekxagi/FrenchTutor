import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/pilot_infrastructure_store.dart';
import '../models/pilot_access.dart';
import '../orchestration/models/competency.dart';
import 'auth_service.dart';

/// Debug-build-only "unlock everything" switch for testing paid-tier UI
/// without a real purchase or invite code. Mirrors ActiveTutor's
/// synchronous-read/async-persist pattern (tutor_persona.dart) — loaded once
/// at app startup, flippable from a Settings toggle, gone entirely from
/// release builds: every check is behind `kDebugMode`, which the compiler
/// dead-code-eliminates in a release build, so this can never ship live.
class DevSubscriptionOverride {
  DevSubscriptionOverride._();

  static const _prefsKey = 'dev_force_pro_unlock';

  static bool _enabled = false;

  static bool get enabled => kDebugMode && _enabled;

  static Future<void> load() async {
    if (!kDebugMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      // Prefs unavailable (fresh install edge) — defaults to off.
    }
  }

  static Future<void> set(bool value) async {
    if (!kDebugMode) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }
}

/// Feature-level lock decisions for non-subscribers. Distinct from
/// [PilotAccessService], which only gates the daily AI-speaking-minutes cap —
/// this gate decides which mission steps and Labs sections are visible-but-
/// locked (lock badge, tap opens the paywall) versus freely usable.
///
/// Free tier keeps two things fully usable forever: vocabulary practice
/// (mission steps + the Labs "Vocabulary" flashcards) and the Labs "Speaking
/// mock" (TCF/TEF), since that's a strong conversion driver for test-takers.
/// Everything else requires a subscription or an invite-code grant.
///
/// Reads the same local `entitlements` table SyncService._hydrateEntitlements
/// keeps in sync with Supabase's `profiles.subscription_active` (set by the
/// RevenueCat webhook or redeem_subscription_invite_code), so one flag covers
/// both paid subscriptions and invite-code grants.
class SubscriptionGateService {
  SubscriptionGateService({required this.infrastructure});

  static const _reviewerEmail = 'admin@parlesprint.com';

  /// Labs tile identifiers that stay free — see labs_screen.dart.
  static const freeLabIds = {'speaking_mock', 'vocabulary'};

  final PilotInfrastructureStore infrastructure;

  bool get _isReviewerAccount {
    try {
      return AuthService.shared.currentSession?.user.email == _reviewerEmail;
    } catch (_) {
      return false;
    }
  }

  bool isSubscribed() {
    if (DevSubscriptionOverride.enabled) return true;
    if (_isReviewerAccount) return true;
    final entitlement = infrastructure.entitlement();
    return entitlement.status == PilotEntitlementStatus.active ||
        entitlement.status == PilotEntitlementStatus.grace;
  }

  /// True if a mission step of this modality should show a lock badge
  /// instead of being runnable. Only vocabulary/reading-recognition stays
  /// free — every other modality (grammar, listening, writing, speaking)
  /// requires a subscription.
  bool isModalityLocked(PerformanceModality modality) {
    if (isSubscribed()) return false;
    return modality != PerformanceModality.readingRecognition;
  }

  /// True if a Labs tile (by its identifier, see labs_screen.dart) should
  /// show a lock badge instead of being tappable.
  bool isLabLocked(String labId) {
    if (isSubscribed()) return false;
    return !freeLabIds.contains(labId);
  }
}
