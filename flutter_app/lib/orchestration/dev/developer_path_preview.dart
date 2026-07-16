import '../models/competency.dart';
import '../models/content_descriptor.dart';

class DeveloperPersonaScenario {
  const DeveloperPersonaScenario({
    required this.id,
    required this.name,
    required this.summary,
    required this.level,
    required this.availableMinutes,
    required this.canSpeakAloud,
    required this.networkAvailable,
  });

  final String id;
  final String name;
  final String summary;
  final String level;
  final int availableMinutes;
  final bool canSpeakAloud;
  final bool networkAvailable;

  DeveloperPersonaScenario copyWith({
    int? availableMinutes,
    bool? canSpeakAloud,
    bool? networkAvailable,
  }) => DeveloperPersonaScenario(
    id: id,
    name: name,
    summary: summary,
    level: level,
    availableMinutes: availableMinutes ?? this.availableMinutes,
    canSpeakAloud: canSpeakAloud ?? this.canSpeakAloud,
    networkAvailable: networkAvailable ?? this.networkAvailable,
  );
}

const developerPersonaScenarios = [
  DeveloperPersonaScenario(
    id: 'commuter_a0',
    name: 'Commuting beginner',
    summary: 'A0 · fragmented commute and lunch practice',
    level: 'A0',
    availableMinutes: 60,
    canSpeakAloud: false,
    networkAvailable: true,
  ),
  DeveloperPersonaScenario(
    id: 'evening_a1',
    name: 'Evening beginner',
    summary: 'A1 · stable after-work routine',
    level: 'A1',
    availableMinutes: 45,
    canSpeakAloud: true,
    networkAvailable: true,
  ),
  DeveloperPersonaScenario(
    id: 'intensive_a2',
    name: 'Intensive learner',
    summary: 'A2 · deep study blocks at home',
    level: 'A2',
    availableMinutes: 240,
    canSpeakAloud: true,
    networkAvailable: true,
  ),
  DeveloperPersonaScenario(
    id: 'working_b1',
    name: 'Working candidate',
    summary: 'B1 · serious Canadian-goal learner',
    level: 'B1',
    availableMinutes: 120,
    canSpeakAloud: true,
    networkAvailable: true,
  ),
  DeveloperPersonaScenario(
    id: 'exam_b2',
    name: 'Exam candidate',
    summary: 'B2 · short runway and uneven skills',
    level: 'B2',
    availableMinutes: 90,
    canSpeakAloud: true,
    networkAvailable: true,
  ),
  DeveloperPersonaScenario(
    id: 'shift_a1',
    name: 'Variable schedule',
    summary: 'A1 · short session without voice',
    level: 'A1',
    availableMinutes: 20,
    canSpeakAloud: false,
    networkAvailable: false,
  ),
];

class DeveloperPreviewTask {
  const DeveloperPreviewTask({
    required this.contentItemId,
    required this.competencyId,
    required this.competencyTitle,
    required this.modality,
    required this.role,
    required this.estimatedMinutes,
    required this.reason,
  });

  final String contentItemId;
  final String competencyId;
  final String competencyTitle;
  final PerformanceModality modality;
  final ContentMappingRole role;
  final int estimatedMinutes;
  final String reason;
}

class DeveloperPathPreview {
  const DeveloperPathPreview({
    required this.persona,
    required this.tasks,
    required this.totalMinutes,
    required this.notes,
  });

  final DeveloperPersonaScenario persona;
  final List<DeveloperPreviewTask> tasks;
  final int totalMinutes;
  final List<String> notes;
}

class DeveloperPathPreviewBuilder {
  const DeveloperPathPreviewBuilder();

  DeveloperPathPreview build({
    required CompetencyFramework framework,
    required DeveloperPersonaScenario persona,
  }) {
    final competencies = _topologicalCompetencies(framework);
    final mappingsByCompetency = <String, List<ContentCompetencyMapping>>{};
    for (final mapping in framework.mappings) {
      mappingsByCompetency
          .putIfAbsent(mapping.competencyId, () => [])
          .add(mapping);
    }

    final tasks = <DeveloperPreviewTask>[];
    var usedMinutes = 0;
    for (final competency in competencies) {
      final mappings = mappingsByCompetency[competency.id] ?? const [];
      final eligible = mappings.where((mapping) {
        final speaking = _isSpeaking(mapping.modality);
        if (speaking && !persona.canSpeakAloud) return false;
        if (speaking && !persona.networkAvailable) return false;
        return true;
      }).toList()..sort((a, b) => b.weight.compareTo(a.weight));
      if (eligible.isEmpty) continue;
      final mapping = eligible.first;
      final minutes = _minutesFor(mapping.modality);
      if (usedMinutes + minutes > persona.availableMinutes &&
          tasks.isNotEmpty) {
        continue;
      }
      tasks.add(
        DeveloperPreviewTask(
          contentItemId: mapping.contentItemId,
          competencyId: competency.id,
          competencyTitle: competency.title,
          modality: mapping.modality,
          role: mapping.role,
          estimatedMinutes: minutes,
          reason: competency.prerequisiteIds.isEmpty
              ? 'Foundation for ${competency.title.toLowerCase()}'
              : 'Builds on ${competency.prerequisiteIds.join(', ')}',
        ),
      );
      usedMinutes += minutes;
    }

    final notes = <String>[
      'Preview only: no learner evidence, mastery, or production plan is changed.',
      if (persona.level == 'A0' || persona.level == 'A1')
        'The current graph begins at A2; this persona needs an A0/A1 diagnostic bridge.',
      if (persona.level == 'B2')
        'The current graph is a foundation slice, not a B2 exam-readiness pathway.',
      if (!persona.canSpeakAloud)
        'Speaking and pronunciation-production tasks were excluded by environment.',
      if (!persona.networkAvailable)
        'Network-dependent live tasks were excluded.',
    ];
    return DeveloperPathPreview(
      persona: persona,
      tasks: tasks,
      totalMinutes: usedMinutes,
      notes: notes,
    );
  }

  List<Competency> _topologicalCompetencies(CompetencyFramework framework) {
    final byId = {
      for (final competency in framework.competencies)
        competency.id: competency,
    };
    final visited = <String>{};
    final ordered = <Competency>[];

    void visit(Competency competency) {
      if (!visited.add(competency.id)) return;
      for (final prerequisiteId in competency.prerequisiteIds) {
        final prerequisite = byId[prerequisiteId];
        if (prerequisite != null) visit(prerequisite);
      }
      ordered.add(competency);
    }

    for (final competency in framework.competencies) {
      visit(competency);
    }
    return ordered;
  }

  bool _isSpeaking(PerformanceModality modality) =>
      modality == PerformanceModality.controlledSpeaking ||
      modality == PerformanceModality.spontaneousSpeaking ||
      modality == PerformanceModality.pronunciationProduction;

  int _minutesFor(PerformanceModality modality) => switch (modality) {
    PerformanceModality.listeningRecognition => 10,
    PerformanceModality.readingRecognition => 7,
    PerformanceModality.controlledWriting => 12,
    PerformanceModality.spontaneousWriting => 18,
    PerformanceModality.controlledSpeaking => 12,
    PerformanceModality.spontaneousSpeaking => 18,
    PerformanceModality.pronunciationProduction => 8,
  };
}
