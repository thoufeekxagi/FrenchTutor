import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../models/content_models.dart';
import 'app_migrations.dart';

enum VocabularySessionStatus { active, paused, completed }

class VocabularySessionRecord {
  VocabularySessionRecord({
    required this.id,
    required this.title,
    required this.source,
    required this.topic,
    required this.levelBand,
    required this.entries,
    required this.contextExamples,
    required this.currentStep,
    required this.currentIndex,
    required this.recallGrades,
    required this.contextResults,
    required this.sentenceResults,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    this.focusNote,
    this.completedAt,
  });

  final String id;
  final String title;
  final String source;
  final String topic;
  final String levelBand;
  final List<VocabEntry> entries;
  final Map<String, BilingualExample> contextExamples;
  final String currentStep;
  final int currentIndex;
  final Map<String, String> recallGrades;
  final Map<String, bool> contextResults;
  final Map<String, String> sentenceResults;
  final VocabularySessionStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String? focusNote;
  final DateTime? completedAt;

  bool get isOpen => status != VocabularySessionStatus.completed;
}

/// Local source of truth for an in-progress or completed vocabulary workshop.
/// Content rows remain owned by the existing curriculum/generated-set stores;
/// this table only freezes the deck and workshop state around them.
class VocabularySessionStore {
  VocabularySessionStore(this._db) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  void create({
    required String id,
    required String title,
    required String source,
    required String topic,
    required String levelBand,
    required List<VocabEntry> entries,
    Map<String, BilingualExample> contextExamples = const {},
    String? focusNote,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO vocabulary_sessions
         (id, title, source, topic, level_band, entries_json, focus_note,
         current_step, current_index, recall_grades_json,
          context_results_json, sentence_results_json, context_examples_json,
          status, started_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'preview', 0, '{}', '{}', '{}',
                 ?, 'active', ?, ?)''',
      [
        id,
        title,
        source,
        topic,
        levelBand,
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
        focusNote,
        jsonEncode(
          contextExamples.map((key, value) => MapEntry(key, value.toJson())),
        ),
        now,
        now,
      ],
    );
  }

  VocabularySessionRecord? get(String id) {
    final rows = _db.select(
      'SELECT * FROM vocabulary_sessions '
      'WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  List<VocabularySessionRecord> recent({int limit = 8}) {
    final rows = _db.select(
      'SELECT * FROM vocabulary_sessions '
      'WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT ?',
      [limit.clamp(1, 50).toInt()],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  VocabularySessionRecord? latestOpen() {
    final rows = _db.select(
      "SELECT * FROM vocabulary_sessions "
      "WHERE deleted_at IS NULL AND status != 'completed' "
      'ORDER BY updated_at DESC LIMIT 1',
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  void saveProgress({
    required String id,
    required String currentStep,
    required int currentIndex,
    required Map<String, String> recallGrades,
    required Map<String, bool> contextResults,
    required Map<String, String> sentenceResults,
    required Map<String, BilingualExample> contextExamples,
  }) {
    _db.execute(
      '''UPDATE vocabulary_sessions SET
         current_step = ?, current_index = ?, recall_grades_json = ?,
         context_results_json = ?, sentence_results_json = ?,
         context_examples_json = ?, status = 'active', updated_at = ?
         WHERE id = ? AND deleted_at IS NULL''',
      [
        currentStep,
        currentIndex,
        jsonEncode(recallGrades),
        jsonEncode(contextResults),
        jsonEncode(sentenceResults),
        jsonEncode(
          contextExamples.map((key, value) => MapEntry(key, value.toJson())),
        ),
        DateTime.now().toUtc().toIso8601String(),
        id,
      ],
    );
  }

  void pause(String id) {
    _db.execute(
      "UPDATE vocabulary_sessions SET status = 'paused', updated_at = ? "
      'WHERE id = ? AND deleted_at IS NULL AND status != \'completed\'',
      [DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  void complete(String id) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      "UPDATE vocabulary_sessions SET status = 'completed', "
      'completed_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL',
      [now, now, id],
    );
  }

  VocabularySessionRecord _fromRow(Row row) {
    final entries = jsonDecode(row['entries_json'] as String) as List;
    Map<String, dynamic> decodeMap(String key) {
      final raw = row[key] as String?;
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    }

    final status =
        VocabularySessionStatus.values.asNameMap()[row['status'] as String?] ??
        VocabularySessionStatus.active;
    final contextExamples = decodeMap('context_examples_json').map(
      (key, value) => MapEntry(
        key,
        BilingualExample.fromJson((value as Map).cast<String, dynamic>()),
      ),
    );
    return VocabularySessionRecord(
      id: row['id'] as String,
      title: row['title'] as String,
      source: row['source'] as String,
      topic: row['topic'] as String? ?? '',
      levelBand: row['level_band'] as String? ?? 'A1',
      entries: entries
          .whereType<Map>()
          .map((entry) => VocabEntry.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      contextExamples: contextExamples,
      currentStep: row['current_step'] as String? ?? 'preview',
      currentIndex: row['current_index'] as int? ?? 0,
      recallGrades: decodeMap(
        'recall_grades_json',
      ).map((key, value) => MapEntry(key, value.toString())),
      contextResults: decodeMap(
        'context_results_json',
      ).map((key, value) => MapEntry(key, value == true)),
      sentenceResults: decodeMap(
        'sentence_results_json',
      ).map((key, value) => MapEntry(key, value.toString())),
      status: status,
      startedAt: DateTime.parse(row['started_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      focusNote: row['focus_note'] as String?,
      completedAt: row['completed_at'] is String
          ? DateTime.tryParse(row['completed_at'] as String)
          : null,
    );
  }
}
