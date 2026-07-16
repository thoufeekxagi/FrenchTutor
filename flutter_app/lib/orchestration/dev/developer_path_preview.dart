import '../models/competency.dart';
import '../models/content_descriptor.dart';
import '../planning/orchestrator.dart';

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
    required this.priority,
    required this.score,
    required this.reason,
  });

  final String contentItemId;
  final String competencyId;
  final String competencyTitle;
  final PerformanceModality modality;
  final ContentMappingRole role;
  final int estimatedMinutes;
  final PlanPriority priority;
  final double score;
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
    List<PlannerCompetencyState> competencyStates = const [],
  }) {
    final competencies = {
      for (final competency in framework.competencies)
        competency.id: competency,
    };
    final plan = const Orchestrator().plan(
      framework: framework,
      context: PlanningContext(
        availableMinutes: persona.availableMinutes,
        canSpeakAloud: persona.canSpeakAloud,
        networkAvailable: persona.networkAvailable,
        goal: 'canada',
        competencyStates: competencyStates,
      ),
    );
    final tasks = [
      for (final task in plan.tasks)
        DeveloperPreviewTask(
          contentItemId: task.contentItemId,
          competencyId: task.competencyId,
          competencyTitle:
              competencies[task.competencyId]?.title ?? task.competencyId,
          modality: task.modality,
          role: task.role,
          estimatedMinutes: task.estimatedMinutes,
          priority: task.priority,
          score: task.score,
          reason: _reason(task),
        ),
    ];
    final notes = <String>[
      'Preview only: no learner evidence, mastery, or production plan is changed.',
      if (competencyStates.isEmpty)
        'No graded evidence exists yet; the planner is using cold-start beliefs.',
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
      totalMinutes: plan.totalMinutes,
      notes: notes,
    );
  }

  String _reason(PlanTask task) {
    final strongest =
        task.reasonTrace.where((trace) => trace.contribution > 0).toList()
          ..sort((a, b) => b.contribution.compareTo(a.contribution));
    if (strongest.isEmpty) return 'Selected by constrained utility policy.';
    return strongest
        .take(3)
        .map(
          (trace) =>
              '${trace.reason.name} ${trace.contribution.toStringAsFixed(2)}',
        )
        .join(' · ');
  }
}
