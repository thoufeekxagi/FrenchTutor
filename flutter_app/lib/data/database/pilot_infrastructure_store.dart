import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/pilot_access.dart';
import 'app_migrations.dart';

const _uuid = Uuid();

class PendingSyncMutation {
  const PendingSyncMutation({
    required this.id,
    required this.tableName,
    required this.rowId,
    required this.operation,
    required this.attemptCount,
  });

  final String id;
  final String tableName;
  final String rowId;
  final String operation;
  final int attemptCount;
}

class OperationalEventRecord {
  const OperationalEventRecord({
    required this.id,
    required this.name,
    required this.properties,
    required this.occurredAt,
  });

  final String id;
  final String name;
  final Map<String, Object?> properties;
  final DateTime occurredAt;
}

class PilotInfrastructureStore {
  PilotInfrastructureStore(this._db) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  String _now() => DateTime.now().toUtc().toIso8601String();

  String installationId(String platform) {
    final existing = _db.select(
      'SELECT id FROM installations WHERE deleted_at IS NULL LIMIT 1',
    );
    if (existing.isNotEmpty) return existing.first['id'] as String;

    final id = _uuid.v4();
    final now = _now();
    _db.execute(
      'INSERT INTO installations (id, platform, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [id, platform, now, now],
    );
    return id;
  }

  PilotEntitlement entitlement() {
    final rows = _db.select(
      'SELECT * FROM entitlements WHERE deleted_at IS NULL ORDER BY verified_at DESC, updated_at DESC LIMIT 1',
    );
    if (rows.isEmpty) {
      return const PilotEntitlement(
        productId: 'founding_access',
        status: PilotEntitlementStatus.localPreview,
        source: 'local',
      );
    }
    final row = rows.first;
    return PilotEntitlement(
      productId: row['product_id'] as String,
      status:
          PilotEntitlementStatus.values.asNameMap()[row['status'] as String] ??
          PilotEntitlementStatus.inactive,
      source: row['source'] as String,
      expiresAt: _date(row['expires_at']),
      verifiedAt: _date(row['verified_at']),
    );
  }

  void saveEntitlement(PilotEntitlement entitlement) {
    final now = _now();
    _db.execute(
      '''INSERT INTO entitlements
         (id, product_id, status, source, expires_at, verified_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        _uuid.v4(),
        entitlement.productId,
        entitlement.status.name,
        entitlement.source,
        entitlement.expiresAt?.toUtc().toIso8601String(),
        entitlement.verifiedAt?.toUtc().toIso8601String(),
        now,
        now,
      ],
    );
  }

  void queueMutation({
    required String tableName,
    required String rowId,
    required String operation,
  }) {
    const tables = {
      'profiles',
      'vocab_cards',
      'vocab_reviews',
      'daily_sessions',
      'ai_sessions',
      'credit_usage',
      'entitlements',
      'operational_events',
      'evidence_events',
      'error_events',
      'learner_competency_states',
      'learning_plans',
      'plan_tasks',
      'lesson_progress',
      'mistake_tags',
    };
    const operations = {'upsert', 'delete'};
    if (!tables.contains(tableName) || !operations.contains(operation)) {
      throw ArgumentError('Unsupported sync mutation');
    }
    final now = _now();
    _db.execute(
      '''INSERT INTO sync_outbox
         (id, table_name, row_id, operation, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [_uuid.v4(), tableName, rowId, operation, now, now],
    );
  }

  List<PendingSyncMutation> pendingMutations({int limit = 100}) {
    final rows = _db.select(
      'SELECT * FROM sync_outbox WHERE processed_at IS NULL ORDER BY created_at LIMIT ?',
      [limit],
    );
    return rows
        .map(
          (row) => PendingSyncMutation(
            id: row['id'] as String,
            tableName: row['table_name'] as String,
            rowId: row['row_id'] as String,
            operation: row['operation'] as String,
            attemptCount: row['attempt_count'] as int,
          ),
        )
        .toList();
  }

  void recordOperationalEvent({
    required String installationId,
    required String name,
    required Map<String, Object?> properties,
  }) {
    const allowedProperties = {
      'app_started': {'platform'},
      'ai_connection': {'stage', 'result_code'},
      'daily_path': {'action', 'stage'},
    };
    final allowedKeys = allowedProperties[name];
    final safe =
        allowedKeys != null &&
        properties.keys.every(allowedKeys.contains) &&
        properties.values.every(
          (value) => value is String && value.length <= 32,
        );
    if (!safe) throw ArgumentError('Unsupported operational event');

    final now = _now();
    _db.execute(
      '''INSERT INTO operational_events
         (id, installation_id, name, properties_json, occurred_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [_uuid.v4(), installationId, name, jsonEncode(properties), now, now, now],
    );
  }

  List<OperationalEventRecord> pendingOperationalEvents({int limit = 100}) {
    final rows = _db.select(
      'SELECT * FROM operational_events WHERE uploaded_at IS NULL ORDER BY occurred_at LIMIT ?',
      [limit],
    );
    return rows
        .map(
          (row) => OperationalEventRecord(
            id: row['id'] as String,
            name: row['name'] as String,
            properties: (jsonDecode(row['properties_json'] as String) as Map)
                .cast<String, Object?>(),
            occurredAt: DateTime.parse(row['occurred_at'] as String),
          ),
        )
        .toList();
  }

  DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
