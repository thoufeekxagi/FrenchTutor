import '../../data/content_service.dart';
import '../../data/database/competency_store.dart';
import '../validation/competency_graph_validator.dart';
import '../validation/mission_catalog_validator.dart';

class OrchestrationBootstrapResult {
  const OrchestrationBootstrapResult({
    required this.frameworkVersion,
    required this.curriculumVersion,
    required this.competencyCount,
    required this.mappingCount,
    required this.persisted,
  });

  final String frameworkVersion;
  final String curriculumVersion;
  final int competencyCount;
  final int mappingCount;
  final bool persisted;
}

class OrchestrationBootstrapper {
  const OrchestrationBootstrapper({
    this.validator = const CompetencyGraphValidator(),
    this.missionValidator = const MissionCatalogValidator(),
  });

  final CompetencyGraphValidator validator;
  final MissionCatalogValidator missionValidator;

  OrchestrationBootstrapResult bootstrap({
    required ContentService content,
    required CompetencyStore store,
  }) {
    final framework = content.competencyFramework();
    if (framework == null) {
      throw StateError('Competency framework was not preloaded');
    }
    final issues = validator.validate(
      framework,
      knownContentIds: content.knownContentIds(),
    );
    if (issues.isNotEmpty) {
      throw StateError('Invalid competency framework:\n${issues.join('\n')}');
    }
    final missionCatalog = content.missionCatalog();
    if (missionCatalog == null) {
      throw StateError('Mission catalog was not preloaded');
    }
    final missionIssues = missionValidator.validate(
      missionCatalog,
      framework: framework,
      knownContentIds: content.knownContentIds(),
    );
    if (missionIssues.isNotEmpty) {
      throw StateError('Invalid mission catalog:\n${missionIssues.join('\n')}');
    }

    final current = store.framework();
    final shouldPersist =
        current == null ||
        current.frameworkVersion != framework.frameworkVersion ||
        current.curriculumVersion != framework.curriculumVersion ||
        current.competencies.length != framework.competencies.length ||
        current.mappings.length != framework.mappings.length;
    if (shouldPersist) store.replaceFramework(framework);

    return OrchestrationBootstrapResult(
      frameworkVersion: framework.frameworkVersion,
      curriculumVersion: framework.curriculumVersion,
      competencyCount: framework.competencies.length,
      mappingCount: framework.mappings.length,
      persisted: shouldPersist,
    );
  }
}
