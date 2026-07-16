import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/data/database/pilot_infrastructure_store.dart';
import 'package:french_tutor/models/pilot_access.dart';
import 'package:french_tutor/services/pilot_access_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Pilot infrastructure', () {
    test('creates stable installation identity and Phase 5 schema', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final infrastructure = PilotInfrastructureStore(db);

      final first = infrastructure.installationId('ios');
      final second = infrastructure.installationId('web');

      expect(second, first);
      expect(
        db
            .select('SELECT version FROM schema_migrations ORDER BY version')
            .map((row) => row['version']),
        [1, 2, 3, 4],
      );
    });

    test('uses local preview until a verified entitlement is cached', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final infrastructure = PilotInfrastructureStore(db);

      expect(
        infrastructure.entitlement().status,
        PilotEntitlementStatus.localPreview,
      );

      infrastructure.saveEntitlement(
        PilotEntitlement(
          productId: 'founding_access',
          status: PilotEntitlementStatus.active,
          source: 'revenuecat',
          verifiedAt: DateTime.now().toUtc(),
        ),
      );

      final entitlement = infrastructure.entitlement();
      expect(entitlement.status, PilotEntitlementStatus.active);
      expect(entitlement.source, 'revenuecat');
      expect(entitlement.grantsAccess, isTrue);
    });

    test('sync outbox stores row references, not learner payloads', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final infrastructure = PilotInfrastructureStore(db);

      infrastructure.queueMutation(
        tableName: 'daily_sessions',
        rowId: 'session-1',
        operation: 'upsert',
      );

      final pending = infrastructure.pendingMutations();
      expect(pending, hasLength(1));
      expect(pending.single.tableName, 'daily_sessions');
      expect(pending.single.rowId, 'session-1');
      expect(
        () => infrastructure.queueMutation(
          tableName: 'messages',
          rowId: 'private-content',
          operation: 'upsert',
        ),
        throwsArgumentError,
      );
    });

    test('operational events contain only fixed categorical properties', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final infrastructure = PilotInfrastructureStore(db);
      final installationId = infrastructure.installationId('ios');
      final telemetry = PilotTelemetry(
        infrastructure: infrastructure,
        installationId: installationId,
      );

      telemetry.appStarted(platform: PilotPlatform.ios);
      telemetry.aiConnection(
        stage: AiStage.speaking,
        result: AiConnectionResult.disconnected,
      );

      final events = infrastructure.pendingOperationalEvents();
      expect(events.map((event) => event.name), [
        'app_started',
        'ai_connection',
      ]);
      expect(events.first.properties, {'platform': 'ios'});
      expect(events.last.properties, {
        'stage': 'speaking',
        'result_code': 'disconnected',
      });
      expect(
        () => infrastructure.recordOperationalEvent(
          installationId: installationId,
          name: 'ai_connection',
          properties: {'transcript': 'private learner speech'},
        ),
        throwsArgumentError,
      );
    });

    test('local credit snapshot is advisory and bounded', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final store = LearningStore(db);
      final infrastructure = PilotInfrastructureStore(db);
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        '''INSERT INTO credit_usage
           (id, local_date, seconds_used, created_at)
           VALUES (?, date('now', 'localtime'), ?, ?)''',
        ['credit-1', 900, now],
      );

      final snapshot = PilotAccessService(
        store: store,
        infrastructure: infrastructure,
      ).snapshot();

      expect(snapshot.serverAuthoritative, isFalse);
      expect(snapshot.usedSeconds, 900);
      expect(snapshot.remainingSeconds, 2700);
      expect(snapshot.canStartAiSession, isTrue);

      db.execute(
        '''INSERT INTO credit_usage
           (id, local_date, seconds_used, created_at)
           VALUES (?, date('now', 'localtime'), ?, ?)''',
        ['credit-2', 2700, now],
      );
      final exhausted = PilotAccessService(
        store: store,
        infrastructure: infrastructure,
      ).snapshot();
      expect(exhausted.remainingSeconds, 0);
      expect(exhausted.canStartAiSession, isFalse);
    });
  });
}
