import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../data/database/app_migrations.dart';
import '../models/profile.dart';
import 'universal_learning_data_service.dart';

/// Keeps a replaceable, local projection of the learner evidence used by
/// Review. Raw learning tables remain authoritative. A failed cache refresh
/// must never affect a Course or Practice write.
abstract final class ReviewContextCacheService {
  static const _cacheId = 'current';
  static bool _refreshQueued = false;

  /// Coalesces bursts of completion writes into one background refresh.
  /// The caller never awaits this operation.
  static void schedule(CommonDatabase db) {
    if (_refreshQueued) return;
    _refreshQueued = true;
    unawaited(
      Future<void>.microtask(() {
        try {
          _refresh(db);
        } catch (_) {
          // This is only an optimization. The live snapshot builder can
          // always rebuild directly from the source tables.
        } finally {
          _refreshQueued = false;
        }
      }),
    );
  }

  static void rebuildNow(CommonDatabase db) {
    try {
      _refresh(db);
    } catch (_) {
      // Keep this best-effort for tests and partially migrated databases.
    }
  }

  static Map<String, dynamic>? read(CommonDatabase db) {
    try {
      runAppMigrations(db);
      final rows = db.select(
        'SELECT dossier_json FROM review_context_cache '
        'WHERE id = ? AND deleted_at IS NULL LIMIT 1',
        [_cacheId],
      );
      if (rows.isEmpty) return null;
      final raw = rows.first['dossier_json'];
      if (raw is Map) return raw.cast<String, dynamic>();
      final decoded = jsonDecode(raw.toString());
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  static void _refresh(CommonDatabase db) {
    runAppMigrations(db);
    // Profile values are deliberately excluded from this cache. They are read
    // fresh when a Review plan is opened so a settings change is immediate.
    final snapshot = UniversalLearningDataService.buildSnapshot(
      db,
      Profile(id: 'review-cache'),
    );
    final dossier = <String, dynamic>{
      'version': 1,
      'sourceFingerprint': snapshot.fingerprint,
      'courseSessionCount': snapshot.courseSessionCount,
      'practiceSessionCount': snapshot.practiceSessionCount,
      'sessions': snapshot.evidence
          .take(20)
          .map(
            (item) => {
              'id': item.id,
              'source': item.source,
              'mode': item.mode,
              'topic': item.topic,
              'summary': item.summary,
              'details': item.details.take(8).toList(growable: false),
              'occurredAt': item.occurredAt.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
      'recentTopics': snapshot.recentTopics.take(12).toList(growable: false),
      'transcriptExcerpts': snapshot.transcriptExcerpts
          .take(12)
          .toList(growable: false),
      'writingSignals': snapshot.writingSignals.take(8).toList(growable: false),
      'vocabularySignals': snapshot.vocabularySignals
          .take(24)
          .toList(growable: false),
      'examSignals': snapshot.examSignals.take(8).toList(growable: false),
      'performanceSignals': snapshot.performanceSignals
          .take(32)
          .toList(growable: false),
      'repeatedMistakes': snapshot.repeatedMistakes
          .take(12)
          .toList(growable: false),
      'targetPhrases': snapshot.targetPhrases.take(24).toList(growable: false),
    };
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''INSERT OR REPLACE INTO review_context_cache
         (id, source_fingerprint, dossier_json, updated_at, deleted_at)
         VALUES (?, ?, ?, ?, NULL)''',
      [_cacheId, snapshot.fingerprint, jsonEncode(dossier), now],
    );
  }
}
