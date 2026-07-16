import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../../orchestration/models/competency.dart';
import '../../orchestration/models/content_descriptor.dart';
import 'app_migrations.dart';

class CompetencyStore {
  CompetencyStore(this._db) {
    runAppMigrations(_db);
  }

  final CommonDatabase _db;

  String _now() => DateTime.now().toUtc().toIso8601String();

  void replaceFramework(CompetencyFramework framework) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM content_competencies');
      _db.execute('DELETE FROM competencies');
      _db.execute('DELETE FROM competency_frameworks');
      final frameworkNow = _now();
      _db.execute(
        '''INSERT INTO competency_frameworks
           (id, framework_version, curriculum_version, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)''',
        [
          framework.curriculumVersion,
          framework.frameworkVersion,
          framework.curriculumVersion,
          frameworkNow,
          frameworkNow,
        ],
      );
      for (final competency in framework.competencies) {
        final now = _now();
        _db.execute(
          '''INSERT INTO competencies
             (id, kind, title, description, difficulty_band,
              prerequisite_ids_json, target_level_label, exam_relevance_json,
              curriculum_version, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            competency.id,
            competency.kind.name,
            competency.title,
            competency.description,
            competency.difficultyBand,
            jsonEncode(competency.prerequisiteIds),
            competency.targetLevelLabel,
            jsonEncode(competency.examRelevance),
            framework.curriculumVersion,
            now,
            now,
          ],
        );
      }
      for (final mapping in framework.mappings) {
        final now = _now();
        _db.execute(
          '''INSERT INTO content_competencies
             (id, content_item_id, competency_id, role, modality, weight,
              curriculum_version, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            mapping.id,
            mapping.contentItemId,
            mapping.competencyId,
            mapping.role.name,
            mapping.modality.wireName,
            mapping.weight,
            framework.curriculumVersion,
            now,
            now,
          ],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  CompetencyFramework? framework() {
    final frameworkRows = _db.select(
      'SELECT * FROM competency_frameworks WHERE deleted_at IS NULL LIMIT 1',
    );
    final competencyRows = _db.select(
      'SELECT * FROM competencies WHERE deleted_at IS NULL ORDER BY id',
    );
    if (frameworkRows.isEmpty || competencyRows.isEmpty) return null;
    final mappingRows = _db.select(
      'SELECT * FROM content_competencies WHERE deleted_at IS NULL ORDER BY id',
    );
    final frameworkRow = frameworkRows.first;
    final curriculumVersion = frameworkRow['curriculum_version'] as String;
    return CompetencyFramework(
      frameworkVersion: frameworkRow['framework_version'] as String,
      curriculumVersion: curriculumVersion,
      competencies: competencyRows
          .map(
            (row) => Competency(
              id: row['id'] as String,
              kind: CompetencyKind.fromWireName(row['kind'] as String),
              title: row['title'] as String,
              description: row['description'] as String,
              difficultyBand: row['difficulty_band'] as String,
              prerequisiteIds: List<String>.from(
                jsonDecode(row['prerequisite_ids_json'] as String) as List,
              ),
              targetLevelLabel: row['target_level_label'] as String?,
              examRelevance:
                  (jsonDecode(row['exam_relevance_json'] as String) as Map)
                      .cast<String, Object?>(),
              curriculumVersion: row['curriculum_version'] as String,
            ),
          )
          .toList(growable: false),
      mappings: mappingRows
          .map(
            (row) => ContentCompetencyMapping(
              id: row['id'] as String,
              contentItemId: row['content_item_id'] as String,
              competencyId: row['competency_id'] as String,
              role: ContentMappingRole.fromWireName(row['role'] as String),
              modality: PerformanceModality.fromWireName(
                row['modality'] as String,
              ),
              weight: row['weight'] as double,
              curriculumVersion: row['curriculum_version'] as String,
            ),
          )
          .toList(growable: false),
    );
  }
}
