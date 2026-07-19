import 'package:flutter/foundation.dart';

import '../data/database/learning_store.dart';
import '../data/database/pilot_infrastructure_store.dart';
import '../models/pilot_access.dart';
import 'auth_service.dart';
import 'referral_service.dart';

class PilotAccessService {
  PilotAccessService({required this.store, required this.infrastructure});

  static const dailyLimitSeconds = 60 * 60;

  // Apple/Google App Review's fixed demo login (see APP_STORE_CONNECT_PRIVACY.md).
  // A reviewer hitting the normal 60-min/day cap mid-review is a Guideline 2.1
  // rejection risk for something that isn't even a real bug, so this one
  // account gets an effectively unlimited daily allowance instead.
  static const _reviewerEmail = 'admin@parlesprint.com';
  static const _reviewerLimitSeconds = 24 * 60 * 60;

  final LearningStore store;
  final PilotInfrastructureStore infrastructure;

  bool get _isReviewerAccount {
    // Supabase may not be initialized yet (app boot ordering, or a plain
    // unit test that never calls Supabase.initialize) — that's just "not
    // signed in," not an error, so never let this getter throw.
    try {
      return AuthService.shared.currentSession?.user.email == _reviewerEmail;
    } catch (_) {
      return false;
    }
  }

  PilotAccessSnapshot snapshot() {
    // Short-circuit entirely for App Review's demo login: a release build
    // with no `entitlements` row (true for any fresh reviewer install)
    // otherwise resolves to `inactive` below, which would lock the reviewer
    // out of the core feature outright.
    if (_isReviewerAccount) {
      return const PilotAccessSnapshot(
        entitlement: PilotEntitlement(
          productId: 'app_review',
          status: PilotEntitlementStatus.active,
          source: 'reviewer_override',
        ),
        dailyLimitSeconds: _reviewerLimitSeconds,
        usedSeconds: 0,
        serverAuthoritative: false,
      );
    }

    final entitlement = infrastructure.entitlement();
    final safeEntitlement =
        entitlement.status == PilotEntitlementStatus.localPreview && !kDebugMode
        ? const PilotEntitlement(
            productId: 'founding_access',
            status: PilotEntitlementStatus.inactive,
            source: 'unconfigured',
          )
        : entitlement;
    // Bonus minutes earned via invite codes (Supabase is the source of
    // truth — see referral_service.dart) simply extend today's allowance.
    // The cached value is refreshed asynchronously elsewhere so this stays
    // a synchronous, non-blocking read.
    final bonusSeconds = ReferralService.shared.cachedBonusSecondsBalance;
    return PilotAccessSnapshot(
      entitlement: safeEntitlement,
      dailyLimitSeconds: dailyLimitSeconds + bonusSeconds,
      usedSeconds: store.aiSecondsUsedToday(),
      serverAuthoritative: false,
    );
  }
}

enum PilotPlatform { ios, android, web, other }

enum AiStage { freeTalk, vocab, grammar, listening, speaking }

enum AiConnectionResult { connected, disconnected, permissionDenied, error }

enum DailyPathAction { started, resumed, paused, completed }

class PilotTelemetry {
  PilotTelemetry({required this.infrastructure, required this.installationId});

  final PilotInfrastructureStore infrastructure;
  final String installationId;

  void appStarted({required PilotPlatform platform}) {
    infrastructure.recordOperationalEvent(
      installationId: installationId,
      name: 'app_started',
      properties: {'platform': platform.name},
    );
  }

  void aiConnection({
    required AiStage stage,
    required AiConnectionResult result,
  }) {
    infrastructure.recordOperationalEvent(
      installationId: installationId,
      name: 'ai_connection',
      properties: {'stage': stage.name, 'result_code': result.name},
    );
  }

  void dailyPath({required DailyPathAction action, required AiStage stage}) {
    infrastructure.recordOperationalEvent(
      installationId: installationId,
      name: 'daily_path',
      properties: {'action': action.name, 'stage': stage.name},
    );
  }
}
