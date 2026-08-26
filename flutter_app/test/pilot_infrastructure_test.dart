import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/database/learning_store.dart';
import 'package:french_tutor/data/database/pilot_infrastructure_store.dart';
import 'package:french_tutor/models/pilot_access.dart';
import 'package:french_tutor/services/pilot_access_service.dart';
import 'package:french_tutor/services/subscription_gate_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('Pilot infrastructure', () {
    test('creates stable installation identity and current schema', () {
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
        [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
          17,
          18,
          19,
          20,
          21,
          22,
          23,
          24,
          25,
          26,
          27,
          28,
          29,
          30,
          31,
          32,
          33,
          34,
          35,
        ],
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

      infrastructure.setEntitlementUser('test-user');
      infrastructure.saveEntitlement(
        PilotEntitlement(
          productId: 'com.parlesprint.pro.annual',
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

    test('gives one shared premium preview per local day', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final infrastructure = PilotInfrastructureStore(db);
      final gate = SubscriptionGateService(
        infrastructure: infrastructure,
        database: db,
      );

      expect(gate.tryEnter(PremiumArea.reading), isTrue);
      expect(gate.previewUsedToday, isTrue);
      expect(gate.tryEnter(PremiumArea.listening), isFalse);
      expect(gate.isLabLocked('vocabulary'), isFalse);
      expect(gate.isLabLocked('writing'), isTrue);

      infrastructure.setEntitlementUser('test-user');
      infrastructure.saveEntitlement(
        PilotEntitlement(
          productId: 'com.parlesprint.pro.annual',
          status: PilotEntitlementStatus.active,
          source: 'revenuecat',
          verifiedAt: DateTime.now().toUtc(),
        ),
      );
      expect(gate.hasPremiumAccess, isTrue);
      expect(gate.tryEnter(PremiumArea.writing), isTrue);
    });

    test('legacy invite entitlements never grant release access', () {
      final entitlement = PilotEntitlement(
        productId: 'invite:SPRINT2026',
        status: PilotEntitlementStatus.active,
        source: 'legacy_code',
        verifiedAt: DateTime.now().toUtc(),
      );

      expect(entitlement.grantsAccess, isFalse);
      expect(entitlement.isPaidActive, isFalse);
    });

    test(
      'entitlement cache is isolated when the signed-in account changes',
      () {
        final db = sqlite3.openInMemory();
        addTearDown(db.dispose);
        final infrastructure = PilotInfrastructureStore(db);

        infrastructure.setEntitlementUser('user-a');
        infrastructure.saveEntitlement(
          PilotEntitlement(
            productId: 'com.parlesprint.pro.annual',
            status: PilotEntitlementStatus.active,
            source: 'revenuecat_customer_info',
            verifiedAt: DateTime.now().toUtc(),
          ),
        );
        expect(infrastructure.entitlement().isPaidActive, isTrue);

        infrastructure.setEntitlementUser('user-b');
        expect(
          infrastructure.entitlement().status,
          PilotEntitlementStatus.localPreview,
        );
      },
    );

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
      final localDate = DateTime.now().toIso8601String().substring(0, 10);
      db.execute(
        '''INSERT INTO credit_usage
           (id, local_date, seconds_used, created_at)
           VALUES (?, ?, ?, ?)''',
        ['credit-1', localDate, 900, now],
      );

      final snapshot = PilotAccessService(
        store: store,
        infrastructure: infrastructure,
      ).snapshot();

      expect(snapshot.serverAuthoritative, isFalse);
      expect(snapshot.usedSeconds, 900);
      // Free-tier daily allowance is 30 minutes (1800s), not the old flat
      // 60 minutes — 900 used leaves 900 remaining, not 2700.
      expect(snapshot.remainingSeconds, 900);
      expect(snapshot.canStartAiSession, isTrue);

      db.execute(
        '''INSERT INTO credit_usage
           (id, local_date, seconds_used, created_at)
           VALUES (?, ?, ?, ?)''',
        ['credit-2', localDate, 900, now],
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
