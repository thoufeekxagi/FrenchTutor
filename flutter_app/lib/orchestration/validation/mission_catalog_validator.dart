import '../models/content_descriptor.dart';
import '../models/mission.dart';

class MissionCatalogValidator {
  const MissionCatalogValidator();

  List<String> validate(
    MissionCatalog catalog, {
    required CompetencyFramework framework,
    required Set<String> knownContentIds,
  }) {
    final issues = <String>[];
    final missionIds = <String>{};
    final competencyIds = {
      for (final competency in framework.competencies) competency.id,
    };
    final mappedPairs = {
      for (final mapping in framework.mappings)
        (mapping.contentItemId, mapping.modality),
    };

    for (final mission in catalog.missions) {
      if (!missionIds.add(mission.id)) {
        issues.add('Duplicate mission id: ${mission.id}');
      }
      if (!competencyIds.contains(mission.primaryCompetencyId)) {
        issues.add(
          'Mission ${mission.id} references unknown primary competency ${mission.primaryCompetencyId}',
        );
      }
      for (final competencyId in mission.supportingCompetencyIds) {
        if (!competencyIds.contains(competencyId)) {
          issues.add(
            'Mission ${mission.id} references unknown supporting competency $competencyId',
          );
        }
      }
      if (mission.steps.isEmpty) {
        issues.add('Mission ${mission.id} has no steps');
      }
      final stepIds = <String>{};
      for (final step in mission.steps) {
        if (!stepIds.add(step.id)) {
          issues.add('Mission ${mission.id} has duplicate step ${step.id}');
        }
        if (!knownContentIds.contains(step.contentItemId)) {
          issues.add(
            'Mission ${mission.id} references unknown content ${step.contentItemId}',
          );
        }
        if (!mappedPairs.contains((step.contentItemId, step.modality))) {
          issues.add(
            'Mission ${mission.id} step ${step.id} has no matching content mapping',
          );
        }
        if (step.estimatedMinutes <= 0) {
          issues.add(
            'Mission ${mission.id} step ${step.id} must have positive estimated minutes',
          );
        }
      }
    }
    return issues;
  }
}
