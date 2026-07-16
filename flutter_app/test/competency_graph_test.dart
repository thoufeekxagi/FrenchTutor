import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/data/content_service.dart';
import 'package:french_tutor/data/database/competency_store.dart';
import 'package:french_tutor/orchestration/models/competency.dart';
import 'package:french_tutor/orchestration/models/content_descriptor.dart';
import 'package:french_tutor/orchestration/validation/competency_graph_validator.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Competency graph', () {
    setUpAll(ContentService.shared.preload);

    test('loads a versioned professional introduction framework', () {
      final framework = ContentService.shared.competencyFramework();

      expect(framework, isNotNull);
      expect(framework!.frameworkVersion, '1.0.0');
      expect(framework.curriculumVersion, 'professional_intro_v1');
      expect(framework.competencies, isNotEmpty);
      expect(framework.mappings, isNotEmpty);
    });

    test('maps only known content through an acyclic competency graph', () {
      final framework = ContentService.shared.competencyFramework()!;
      final issues = const CompetencyGraphValidator().validate(
        framework,
        knownContentIds: ContentService.shared.knownContentIds(),
      );

      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('persists and restores the framework through migration v3', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      final store = CompetencyStore(db);
      final source = ContentService.shared.competencyFramework()!;

      store.replaceFramework(source);
      final restored = store.framework();

      expect(restored, isNotNull);
      expect(restored!.frameworkVersion, source.frameworkVersion);
      expect(restored.curriculumVersion, source.curriculumVersion);
      expect(
        restored.competencies.map((item) => item.id).toSet(),
        source.competencies.map((item) => item.id).toSet(),
      );
      expect(
        restored.mappings.map((item) => item.id).toSet(),
        source.mappings.map((item) => item.id).toSet(),
      );
      expect(
        db
            .select('SELECT version FROM schema_migrations ORDER BY version')
            .map((row) => row['version']),
        [1, 2, 3],
      );
    });

    test('preserves modality and support-level wire names', () {
      expect(
        PerformanceModality.fromWireName('spontaneous_speaking'),
        PerformanceModality.spontaneousSpeaking,
      );
      expect(
        EvidenceSupportLevel.fromWireName('unaided_production'),
        EvidenceSupportLevel.unaidedProduction,
      );
      expect(
        () => PerformanceModality.fromWireName('generic_progress'),
        throwsFormatException,
      );
    });

    test('rejects cycles, unknown content, and unsafe mapping weights', () {
      const version = 'test_v1';
      final framework = CompetencyFramework(
        frameworkVersion: '1.0.0',
        curriculumVersion: version,
        competencies: const [
          Competency(
            id: 'a',
            kind: CompetencyKind.lexical,
            title: 'A',
            description: 'A',
            difficultyBand: 'A1',
            prerequisiteIds: ['b'],
            curriculumVersion: version,
          ),
          Competency(
            id: 'b',
            kind: CompetencyKind.grammar,
            title: 'B',
            description: 'B',
            difficultyBand: 'A1',
            prerequisiteIds: ['a'],
            curriculumVersion: version,
          ),
        ],
        mappings: const [
          ContentCompetencyMapping(
            id: 'map_a',
            contentItemId: 'missing',
            competencyId: 'a',
            role: ContentMappingRole.assesses,
            modality: PerformanceModality.readingRecognition,
            weight: 1.5,
            curriculumVersion: version,
          ),
        ],
      );

      final issues = const CompetencyGraphValidator().validate(
        framework,
        knownContentIds: const {},
      );

      expect(issues.any((issue) => issue.contains('cycle')), isTrue);
      expect(issues.any((issue) => issue.contains('unknown content')), isTrue);
      expect(issues.any((issue) => issue.contains('weight')), isTrue);
      expect(
        issues.any((issue) => issue.contains('b has no content mappings')),
        isTrue,
      );
    });
  });
}
