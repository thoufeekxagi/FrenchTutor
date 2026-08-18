import 'package:flutter/foundation.dart';

import '../data/database/learning_store.dart';
import '../data/database/pilot_infrastructure_store.dart';
import '../models/pilot_access.dart';
import 'learning_allowance_service.dart';
import 'subscription_gate_service.dart';

class PilotAccessService {
  PilotAccessService({required this.store, required this.infrastructure});

  /// Non-subscribed daily AI-talk-time allowance — counted across every
  /// Gemini Live session that day, not per-session.
  static const freeDailyLimitSeconds = 30 * 60;

  /// Subscribed (RevenueCat purchase) daily allowance.
  /// Generous on purpose: paying learners shouldn't feel metered, and nobody
  /// realistically talks 2 hours/day anyway.
  static const subscribedDailyLimitSeconds = 120 * 60;

  final LearningStore store;
  final PilotInfrastructureStore infrastructure;

  PilotAccessSnapshot snapshot() {
    final entitlement = infrastructure.entitlement();
    final safeEntitlement =
        entitlement.status == PilotEntitlementStatus.localPreview && !kDebugMode
        ? const PilotEntitlement(
            productId: 'none',
            status: PilotEntitlementStatus.inactive,
            source: 'free_preview',
          )
        : entitlement;
    // The cached allowance is refreshed asynchronously elsewhere so this
    // stays a synchronous, non-blocking read.
    final bonusSeconds =
        LearningAllowanceService.shared.cachedBonusSecondsBalance;
    return PilotAccessSnapshot(
      entitlement: safeEntitlement,
      dailyLimitSeconds: baseDailyLimitSeconds(safeEntitlement) + bonusSeconds,
      usedSeconds: store.aiSecondsUsedToday(),
      serverAuthoritative: false,
    );
  }

  /// The base allowance (before bonus seconds) for a given entitlement —
  /// exposed separately so callers computing bonus-minute overage (e.g.
  /// session_screen.dart's post-call accounting) use the same tier this
  /// snapshot was built from, not a stale flat constant.
  static int baseDailyLimitSeconds(PilotEntitlement entitlement) {
    final subscribed =
        DevSubscriptionOverride.enabled || entitlement.isPaidActive;
    return subscribed ? subscribedDailyLimitSeconds : freeDailyLimitSeconds;
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
