import 'package:flutter/foundation.dart';

import '../data/database/learning_store.dart';
import '../data/database/pilot_infrastructure_store.dart';
import '../models/pilot_access.dart';

class PilotAccessService {
  PilotAccessService({required this.store, required this.infrastructure});

  static const dailyLimitSeconds = 60 * 60;

  final LearningStore store;
  final PilotInfrastructureStore infrastructure;

  PilotAccessSnapshot snapshot() {
    final entitlement = infrastructure.entitlement();
    final safeEntitlement =
        entitlement.status == PilotEntitlementStatus.localPreview && !kDebugMode
        ? const PilotEntitlement(
            productId: 'founding_access',
            status: PilotEntitlementStatus.inactive,
            source: 'unconfigured',
          )
        : entitlement;
    return PilotAccessSnapshot(
      entitlement: safeEntitlement,
      dailyLimitSeconds: dailyLimitSeconds,
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
