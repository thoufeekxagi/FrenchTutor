import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../../models/content_models.dart';
import '../../models/exam_practice.dart';
import 'app_migrations.dart';

const _examUuid = Uuid();

/// Local, independent storage for exam-readiness attempts.
///
/// These rows intentionally do not enter `generated_stories`: regular course
/// shelves should never show an exam simulation, and exam history needs its
/// own exam/level/skill/completion dimensions.
class ExamPracticeStore {
  ExamPracticeStore(this._db) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  /// Starts a non-story readiness skill (writing or speaking). The payload is
  /// intentionally opaque here so those skills can evolve independently while
  /// sharing the same exam history and completion contract.
  String startMetadata({
    required String examName,
    required String levelBand,
    required String skill,
    required Map<String, dynamic> content,
  }) {
    final id = _examUuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO exam_practice_attempts
         (id, exam_name, level_band, skill, content_json, created_at, updated_at, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'in_progress')''',
      [id, examName, levelBand, skill, jsonEncode(content), now, now],
    );
    return id;
  }

  ExamPracticeAttempt startStory({
    required String examName,
    required String levelBand,
    required String skill,
    required GeneratedStory story,
  }) {
    final attempt = ExamPracticeAttempt(
      id: _examUuid.v4(),
      examName: examName,
      levelBand: levelBand,
      skill: skill,
      story: story,
      createdAt: DateTime.now(),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''INSERT INTO exam_practice_attempts
         (id, exam_name, level_band, skill, content_json, created_at, updated_at, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'in_progress')''',
      [
        attempt.id,
        attempt.examName,
        attempt.levelBand,
        attempt.skill,
        jsonEncode(_storyJson(story)),
        attempt.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
    return attempt;
  }

  void complete({required String id, required int score, required int total}) {
    final completedAt = DateTime.now().toUtc().toIso8601String();
    _db.execute(
      '''UPDATE exam_practice_attempts
         SET status = 'completed', score = ?, total = ?,
             completed_at = ?, updated_at = ?
         WHERE id = ?''',
      [score, total, completedAt, completedAt, id],
    );
  }

  int startedCount() {
    final rows = _db.select(
      "SELECT COUNT(*) AS count FROM exam_practice_attempts WHERE deleted_at IS NULL",
    );
    return rows.first['count'] as int;
  }

  List<ExamPracticeAttempt> list({String? skill}) {
    final rows = _db.select(
      '''SELECT id, exam_name, level_band, skill, content_json,
                created_at, completed_at, score, total
         FROM exam_practice_attempts
         WHERE deleted_at IS NULL ${skill == null ? '' : 'AND skill = ?'}
         ORDER BY created_at DESC''',
      skill == null ? const [] : [skill],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  List<ExamPracticeSummary> summaries() {
    final rows = _db.select('''
      SELECT id, exam_name, level_band, skill, created_at,
             completed_at, score, total
      FROM exam_practice_attempts
      WHERE deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT 12
    ''');
    return rows
        .map(
          (row) => ExamPracticeSummary(
            id: row['id'] as String,
            examName: row['exam_name'] as String,
            levelBand: row['level_band'] as String,
            skill: row['skill'] as String,
            createdAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            completedAt: DateTime.tryParse(
              row['completed_at'] as String? ?? '',
            ),
            score: row['score'] as int?,
            total: row['total'] as int?,
          ),
        )
        .toList(growable: false);
  }

  ExamPracticeAttempt _fromRow(Row row) {
    final content = (jsonDecode(row['content_json'] as String) as Map)
        .cast<String, dynamic>();
    final storyJson = (content['story'] as Map).cast<String, dynamic>();
    final story = GeneratedStory(
      id: storyJson['id'] as String,
      passage: ReadingPassage.fromJson(
        (storyJson['passage'] as Map).cast<String, dynamic>(),
      ),
      quiz: (storyJson['quiz'] as List)
          .map(
            (item) => MultipleChoiceQuestion.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      keywords: (storyJson['keywords'] as List)
          .map(
            (item) =>
                VocabEntry.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList(),
      createdAt:
          DateTime.tryParse(storyJson['createdAt'] as String? ?? '') ??
          DateTime.now(),
      levelBand:
          storyJson['levelBand'] as String? ?? row['level_band'] as String,
      summary: storyJson['summary'] as String? ?? '',
      topic: storyJson['topic'] as String? ?? '',
      readTimeMinutes: storyJson['readTimeMinutes'] as int? ?? 5,
      practiceMode: 'exam',
    );
    return ExamPracticeAttempt(
      id: row['id'] as String,
      examName: row['exam_name'] as String,
      levelBand: row['level_band'] as String,
      skill: row['skill'] as String,
      story: story,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      completedAt: DateTime.tryParse(row['completed_at'] as String? ?? ''),
      score: row['score'] as int?,
      total: row['total'] as int?,
    );
  }

  Map<String, dynamic> _storyJson(GeneratedStory story) => {
    'id': story.id,
    'passage': story.passage.toJson(),
    'quiz': story.quiz.map((question) => question.toJson()).toList(),
    'keywords': story.keywords.map((word) => word.toJson()).toList(),
    'createdAt': story.createdAt.toUtc().toIso8601String(),
    'levelBand': story.levelBand,
    'summary': story.summary,
    'topic': story.topic,
    'readTimeMinutes': story.readTimeMinutes,
  };
}
