import '../../data/content_service.dart';
import '../../data/database/competency_store.dart';
import '../validation/competency_graph_validator.dart';

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
  });

  final CompetencyGraphValidator validator;

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
