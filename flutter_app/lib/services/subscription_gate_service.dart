import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqlite3/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/pilot_infrastructure_store.dart';
import '../orchestration/models/competency.dart';
import 'auth_service.dart';

/// Debug-build-only "unlock everything" switch for testing paid-tier UI
/// without a real purchase. Mirrors ActiveTutor's
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

/// The premium areas share one entitlement and one free-preview budget. The
/// area is used for copy/analytics and route mapping; it never creates
/// separate subscription products.
enum PremiumArea {
  course,
  reading,
  listening,
  writing,
  grammar,
  roleplay,
  exam,
  connectors,
  liaison,
  speaking,
  review,
}

abstract final class PremiumAreaMapping {
  static PremiumArea? fromLabId(String labId) => switch (labId) {
    'grammar' => PremiumArea.grammar,
    'reading' => PremiumArea.reading,
    'listening' => PremiumArea.listening,
    'roleplay' => PremiumArea.roleplay,
    'writing' => PremiumArea.writing,
    'connectors' => PremiumArea.connectors,
    'liaison' => PremiumArea.liaison,
    'speaking_mock' => PremiumArea.exam,
    'speaking' => PremiumArea.speaking,
    'review' => PremiumArea.review,
    'vocabulary' || 'flashcards' || 'alphabet' => null,
    _ => PremiumArea.course,
  };
}

/// Feature-level access decisions for non-subscribers. Distinct from
/// [PilotAccessService], which also gates the daily AI-speaking-minutes cap —
/// this gate decides which mission steps and Labs sections use the one daily
/// preview versus the universal paywall.
///
/// Free tier keeps the low-cost vocabulary core usable forever. Every other
/// premium area gets one meaningful preview per local day, then the same
/// subscription prompt.
///
/// Reads the same local `entitlements` table SyncService._hydrateEntitlements
/// keeps in sync with Supabase's StoreKit/RevenueCat subscription webhook, so
/// one flag covers paid subscriptions.
class SubscriptionGateService {
  SubscriptionGateService({
    required this.infrastructure,
    required this.database,
  });

  static const _reviewerEmail = 'admin@parlesprint.com';

  /// Small, durable free core. Everything else gets one useful premium
  /// preview per local day, then the same paywall.
  static const freeLabIds = {'vocabulary', 'flashcards', 'alphabet'};

  final PilotInfrastructureStore infrastructure;
  final CommonDatabase database;

  bool get _isReviewerAccount {
    try {
      return AuthService.shared.currentSession?.user.email == _reviewerEmail;
    } catch (_) {
      return false;
    }
  }

  bool isSubscribed() {
    return hasPremiumAccess;
  }

  bool get hasPremiumAccess {
    if (DevSubscriptionOverride.enabled) return true;
    if (_isReviewerAccount) return true;
    return infrastructure.entitlement().isPaidActive;
  }

  /// Whether the learner may enter [area] right now. This is intentionally
  /// synchronous so every route can make the same decision before pushing a
  /// screen. Paid access always wins; the free core is permanent; all other
  /// areas share one preview per local calendar day.
  bool canEnter(PremiumArea area) {
    if (hasPremiumAccess || _isFreeCore(area)) return true;
    return !previewUsedToday;
  }

  /// Claims today's preview. Calling this at the route boundary prevents a
  /// free learner from opening several premium areas before the UI rebuilds.
  bool tryEnter(PremiumArea area) {
    if (hasPremiumAccess || _isFreeCore(area)) return true;
    if (previewUsedToday) return false;
    final now = DateTime.now();
    final date = _dateKey(now);
    database.execute(
      '''INSERT OR IGNORE INTO premium_preview_usage
         (usage_date, area, created_at, updated_at)
         VALUES (?, ?, ?, ?)''',
      [
        date,
        area.name,
        now.toUtc().toIso8601String(),
        now.toUtc().toIso8601String(),
      ],
    );
    final row = database.select(
      'SELECT area FROM premium_preview_usage '
      'WHERE usage_date = ? AND deleted_at IS NULL LIMIT 1',
      [date],
    );
    return row.isNotEmpty && row.first['area'] == area.name;
  }

  bool get previewUsedToday {
    final row = database.select(
      'SELECT 1 FROM premium_preview_usage '
      'WHERE usage_date = ? AND deleted_at IS NULL LIMIT 1',
      [_dateKey(DateTime.now())],
    );
    return row.isNotEmpty;
  }

  bool isAreaLocked(PremiumArea area) => !canEnter(area);

  bool _isFreeCore(PremiumArea area) => switch (area) {
    PremiumArea.review => true,
    _ => false,
  };

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  PremiumArea? areaForLabId(String labId) =>
      PremiumAreaMapping.fromLabId(labId);

  bool isFreeLab(String labId) => freeLabIds.contains(labId);

  /// Existing modality callers now use the same universal preview policy.
  bool isModalityLocked(PerformanceModality modality) {
    final area = switch (modality) {
      PerformanceModality.readingRecognition => PremiumArea.reading,
      PerformanceModality.listeningRecognition => PremiumArea.listening,
      PerformanceModality.controlledWriting ||
      PerformanceModality.spontaneousWriting => PremiumArea.writing,
      PerformanceModality.pronunciationProduction ||
      PerformanceModality.controlledSpeaking ||
      PerformanceModality.spontaneousSpeaking => PremiumArea.speaking,
    };
    return isAreaLocked(area);
  }

  /// True if a Labs tile (by its identifier, see labs_screen.dart) has no
  /// free preview remaining and should show a lock badge.
  bool isLabLocked(String labId) {
    final area = areaForLabId(labId);
    if (area == null) return false;
    return isAreaLocked(area);
  }
}
