import '../models/content_descriptor.dart';

class CompetencyGraphValidator {
  const CompetencyGraphValidator();

  List<String> validate(
    CompetencyFramework framework, {
    required Set<String> knownContentIds,
  }) {
    final issues = <String>[];
    if (framework.frameworkVersion.trim().isEmpty) {
      issues.add('frameworkVersion must not be empty');
    }
    if (framework.curriculumVersion.trim().isEmpty) {
      issues.add('curriculumVersion must not be empty');
    }

    final competencyIds = <String>{};
    for (final competency in framework.competencies) {
      if (competency.id.trim().isEmpty) {
        issues.add('Competency id must not be empty');
      } else if (!competencyIds.add(competency.id)) {
        issues.add('Duplicate competency id: ${competency.id}');
      }
      if (competency.curriculumVersion != framework.curriculumVersion) {
        issues.add(
          'Competency ${competency.id} uses a different curriculum version',
        );
      }
      if (competency.prerequisiteIds.contains(competency.id)) {
        issues.add('Competency ${competency.id} cannot require itself');
      }
    }

    for (final competency in framework.competencies) {
      for (final prerequisiteId in competency.prerequisiteIds) {
        if (!competencyIds.contains(prerequisiteId)) {
          issues.add(
            'Competency ${competency.id} has unknown prerequisite $prerequisiteId',
          );
        }
      }
    }
    issues.addAll(_cycleIssues(framework));

    final mappingIds = <String>{};
    final mappedCompetencyIds = <String>{};
    for (final mapping in framework.mappings) {
      if (!mappingIds.add(mapping.id)) {
        issues.add('Duplicate mapping id: ${mapping.id}');
      }
      if (!competencyIds.contains(mapping.competencyId)) {
        issues.add(
          'Mapping ${mapping.id} references unknown competency ${mapping.competencyId}',
        );
      } else {
        mappedCompetencyIds.add(mapping.competencyId);
      }
      if (!knownContentIds.contains(mapping.contentItemId)) {
        issues.add(
          'Mapping ${mapping.id} references unknown content ${mapping.contentItemId}',
        );
      }
      if (mapping.weight <= 0 || mapping.weight > 1) {
        issues.add(
          'Mapping ${mapping.id} weight must be greater than 0 and at most 1',
        );
      }
      if (mapping.curriculumVersion != framework.curriculumVersion) {
        issues.add('Mapping ${mapping.id} uses a different curriculum version');
      }
    }

    for (final competencyId in competencyIds.difference(mappedCompetencyIds)) {
      issues.add('Competency $competencyId has no content mappings');
    }
    return issues;
  }

  List<String> _cycleIssues(CompetencyFramework framework) {
    final prerequisites = {
      for (final competency in framework.competencies)
        competency.id: competency.prerequisiteIds,
    };
    final visiting = <String>{};
    final visited = <String>{};
    final issues = <String>[];

    bool visit(String id, List<String> path) {
      if (visiting.contains(id)) {
        final cycleStart = path.indexOf(id);
        final cycle = [...path.sublist(cycleStart), id];
        issues.add('Competency prerequisite cycle: ${cycle.join(' -> ')}');
        return true;
      }
      if (visited.contains(id)) return false;
      visiting.add(id);
      for (final prerequisiteId in prerequisites[id] ?? const <String>[]) {
        if (prerequisites.containsKey(prerequisiteId)) {
          visit(prerequisiteId, [...path, id]);
        }
      }
      visiting.remove(id);
      visited.add(id);
      return false;
    }

    for (final id in prerequisites.keys) {
      visit(id, const []);
    }
    return issues.toSet().toList(growable: false);
  }
}
