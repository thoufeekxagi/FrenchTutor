import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../orchestration/dev/developer_path_preview.dart';
import '../../orchestration/models/competency_state.dart';
import '../../orchestration/models/error_event.dart';
import '../../orchestration/models/learning_plan.dart';
import '../../orchestration/planning/orchestrator.dart';
import '../../orchestration/twin/evidence_observation_adapter.dart';
import '../../orchestration/twin/twin_updater.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_card.dart';

class OrchestrationLabScreen extends ConsumerStatefulWidget {
  const OrchestrationLabScreen({super.key});

  @override
  ConsumerState<OrchestrationLabScreen> createState() =>
      _OrchestrationLabScreenState();
}

class _OrchestrationLabScreenState
    extends ConsumerState<OrchestrationLabScreen> {
  DeveloperPersonaScenario _persona = developerPersonaScenarios[2];
  List<CompetencyState>? _persistedStates;
  PlanSnapshot? _persistedPlan;
  bool _persisting = false;

  String get _today {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _persistSnapshot() async {
    setState(() => _persisting = true);
    final framework = ref.read(competencyStoreProvider).framework();
    if (framework == null) {
      setState(() => _persisting = false);
      return;
    }
    final service = ref.read(orchestrationServiceProvider);
    final states = service.refreshCompetencyStates(
      framework: framework,
      evidenceStore: ref.read(evidenceStoreProvider),
      stateStore: ref.read(competencyStateStoreProvider),
    );
    final plan = service.ensureTodayPlan(
      framework: framework,
      competencyStates: states,
      errors: ref.read(evidenceStoreProvider).errorEvents(),
      planStore: ref.read(planStoreProvider),
      localDate: _today,
      availableMinutes: _persona.availableMinutes,
      canSpeakAloud: _persona.canSpeakAloud,
      networkAvailable: _persona.networkAvailable,
      goal: 'tef_canada',
    );
    if (!mounted) return;
    setState(() {
      _persistedStates = states;
      _persistedPlan = plan;
      _persisting = false;
    });
  }

  Future<void> _choosePersona() async {
    final selected = await showPSActionSheet<DeveloperPersonaScenario>(
      context,
      title: 'Test persona',
      actions: [
        for (final persona in developerPersonaScenarios)
          (
            label: '${persona.name}, ${persona.summary}',
            value: persona,
            destructive: false,
          ),
      ],
    );
    if (selected != null && mounted) setState(() => _persona = selected);
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final framework = ref.watch(competencyStoreProvider).framework();
    if (framework == null) {
      return Scaffold(
        backgroundColor: DesignTokens.canvas,
        appBar: AppBar(
          title: Text('Orchestration Lab', style: DesignTokens.display(20)),
        ),
        body: Center(
          child: Text(
            'No persisted competency framework.',
            style: DesignTokens.body(15).copyWith(color: DesignTokens.slateDim),
          ),
        ),
      );
    }
    final evidenceStore = ref.watch(evidenceStoreProvider);
    final evidence = evidenceStore.evidenceEvents();
    final errors = evidenceStore.errorEvents();
    final learnerModel = O3ProbabilisticLearnerModel();
    learnerModel.rebuild(
      const EvidenceObservationAdapter().convert(
        evidence: evidence,
        framework: framework,
      ),
    );
    final competencyStates = _plannerStates(
      model: learnerModel,
      errors: errors,
      now: DateTime.now(),
    );
    final preview = const DeveloperPathPreviewBuilder().build(
      framework: framework,
      persona: _persona,
      competencyStates: competencyStates,
    );

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Orchestration Lab', style: DesignTokens.display(20)),
      ),
      body: PSContentColumn(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.screenMargin,
            vertical: DesignTokens.space2,
          ),
          children: [
            PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Runtime', color: DesignTokens.slateDim),
                  const SizedBox(height: DesignTokens.space2),
                  Text(
                    framework.curriculumVersion,
                    style: DesignTokens.display(18, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: DesignTokens.space2),
                  Text(
                    '${framework.competencies.length} competencies · '
                    '${framework.mappings.length} mappings · framework ${framework.frameworkVersion}',
                    style: DesignTokens.mono(
                      11,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                  const SizedBox(height: DesignTokens.space1),
                  Text(
                    '${evidence.length} evidence events · '
                    '${learnerModel.beliefs.length} modeled states · '
                    '${errors.where((error) => error.resolvedByEvidenceId == null).length} open errors',
                    style: DesignTokens.mono(
                      11,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.space3),
            PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Scenario', color: DesignTokens.slateDim),
                  const SizedBox(height: DesignTokens.space2),
                  Semantics(
                    button: true,
                    label: 'Choose test persona, currently ${_persona.name}',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _choosePersona,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: DesignTokens.minTapTarget,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _persona.name,
                                    style: DesignTokens.body(
                                      15,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: DesignTokens.space1),
                                  Text(
                                    _persona.summary,
                                    style: DesignTokens.body(
                                      12,
                                    ).copyWith(color: DesignTokens.slateDim),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              CupertinoIcons.chevron_down,
                              size: 16,
                              color: DesignTokens.slateDim,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space3),
                  PSSegmented<int>(
                    segments: const [
                      (value: 20, label: '20m'),
                      (value: 45, label: '45m'),
                      (value: 90, label: '90m'),
                      (value: 120, label: '2h'),
                    ],
                    selected:
                        [20, 45, 90, 120].contains(_persona.availableMinutes)
                        ? _persona.availableMinutes
                        : 120,
                    onChanged: (minutes) => setState(
                      () => _persona = _persona.copyWith(
                        availableMinutes: minutes,
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space3),
                  _ToggleRow(
                    label: 'Can speak aloud',
                    value: _persona.canSpeakAloud,
                    onChanged: (value) => setState(
                      () => _persona = _persona.copyWith(canSpeakAloud: value),
                    ),
                  ),
                  _ToggleRow(
                    label: 'Network available',
                    value: _persona.networkAvailable,
                    onChanged: (value) => setState(
                      () =>
                          _persona = _persona.copyWith(networkAvailable: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.space3),
            PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Persisted state', color: DesignTokens.slateDim),
                  const SizedBox(height: DesignTokens.space2),
                  Text(
                    'Rebuilds learner_competency_states from the evidence '
                    'ledger and persists it, then generates/loads today\'s '
                    'immutable plan snapshot. Evidence count below is the '
                    'per-competency repetition signal.',
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                  const SizedBox(height: DesignTokens.space3),
                  Semantics(
                    button: true,
                    label: 'Persist competency states and generate today\'s plan',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _persisting ? null : _persistSnapshot,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: DesignTokens.minTapTarget,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _persisting
                                    ? 'Persisting…'
                                    : 'Persist & generate today\'s plan',
                                style: DesignTokens.body(
                                  14,
                                  weight: FontWeight.w600,
                                ).copyWith(color: DesignTokens.primary),
                              ),
                            ),
                            const Icon(
                              CupertinoIcons.arrow_2_circlepath,
                              size: 16,
                              color: DesignTokens.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_persistedPlan case final plan?) ...[
                    const SizedBox(height: DesignTokens.space3),
                    Text(
                      'Plan ${plan.localDate} · ${plan.status.name} · '
                      '${plan.tasks.length} tasks · ${plan.totalMinutes} min',
                      style: DesignTokens.mono(
                        11,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                    const SizedBox(height: DesignTokens.space1),
                    Text(
                      plan.explanation,
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ],
                  if (_persistedStates case final states? when states.isNotEmpty) ...[
                    const SizedBox(height: DesignTokens.space3),
                    for (final state in [...states]
                      ..sort(
                        (a, b) => b.evidenceCount.compareTo(a.evidenceCount),
                      ))
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: DesignTokens.space1,
                        ),
                        child: Text(
                          '${state.competencyId} · ${state.modality.wireName}, '
                          '${state.evidenceCount}x · mastery '
                          '${(state.masteryEstimate * 100).toStringAsFixed(0)}% · '
                          '${state.transferStatus.wireName}'
                          '${state.nextReviewAt != null ? ' · next review ${state.nextReviewAt!.toLocal().toString().split(' ').first}' : ''}',
                          style: DesignTokens.mono(
                            10,
                          ).copyWith(color: DesignTokens.slateDim),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.space5),
            Row(
              children: [
                KickerText('Path preview', color: DesignTokens.slateDim),
                const Spacer(),
                Text(
                  '${preview.totalMinutes} min',
                  style: DesignTokens.mono(
                    11,
                  ).copyWith(color: DesignTokens.primary),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space2),
            for (final (index, task) in preview.tasks.indexed) ...[
              PasseportCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DesignTokens.infoSoft,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusSmall,
                        ),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: DesignTokens.mono(11, weight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.competencyTitle,
                            style: DesignTokens.body(
                              14,
                              weight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: DesignTokens.space1),
                          Text(
                            task.contentItemId,
                            style: DesignTokens.mono(
                              11,
                            ).copyWith(color: DesignTokens.slateDim),
                          ),
                          const SizedBox(height: DesignTokens.space1),
                          Text(
                            '${task.priority.name.toUpperCase()} · score ${task.score.toStringAsFixed(2)}',
                            style: DesignTokens.mono(
                              11,
                              weight: FontWeight.w600,
                            ).copyWith(color: DesignTokens.primary),
                          ),
                          const SizedBox(height: DesignTokens.space1),
                          Text(
                            '${task.modality.wireName} · ${task.role.name} · ${task.estimatedMinutes} min',
                            style: DesignTokens.body(
                              11,
                            ).copyWith(color: DesignTokens.info),
                          ),
                          const SizedBox(height: DesignTokens.space1),
                          Text(
                            task.reason,
                            style: DesignTokens.body(
                              12,
                            ).copyWith(color: DesignTokens.slateDim),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.space2),
            ],
            const SizedBox(height: DesignTokens.space3),
            PasseportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KickerText('Boundaries', color: DesignTokens.slateDim),
                  const SizedBox(height: DesignTokens.space2),
                  for (final note in preview.notes)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: DesignTokens.space2,
                      ),
                      child: Text(
                        note,
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: DesignTokens.slateDim),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.space6),
          ],
        ),
      ),
    );
  }
}

List<PlannerCompetencyState> _plannerStates({
  required O3ProbabilisticLearnerModel model,
  required List<ErrorEvent> errors,
  required DateTime now,
}) {
  final beliefsByCompetency = <String, List<CompetencyBeliefState>>{};
  for (final belief in model.beliefs.values) {
    beliefsByCompetency.putIfAbsent(belief.competencyId, () => []).add(belief);
  }
  return beliefsByCompetency.entries
      .map((entry) {
        final beliefs = entry.value;
        final belief =
            beliefs.fold<double>(0, (sum, item) => sum + item.pKnown) /
            beliefs.length;
        final confidence =
            beliefs.fold<double>(0, (sum, item) => sum + item.confidence) /
            beliefs.length;
        final lastObservedAt = beliefs
            .map((item) => item.lastObservedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (latest, item) =>
                  latest == null || item.isAfter(latest) ? item : latest,
            );
        final recentErrors = errors
            .where(
              (error) =>
                  error.competencyId == entry.key &&
                  error.resolvedByEvidenceId == null &&
                  !error.occurredAt.isBefore(
                    now.subtract(const Duration(days: 14)),
                  ),
            )
            .length;
        return PlannerCompetencyState(
          competencyId: entry.key,
          belief: belief,
          uncertainty: 1 - confidence,
          dueForReview:
              lastObservedAt != null &&
              lastObservedAt.isBefore(now.subtract(const Duration(days: 3))),
          recentErrors: recentErrors,
        );
      })
      .toList(growable: false);
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: DesignTokens.minTapTarget),
    child: Row(
      children: [
        Expanded(child: Text(label, style: DesignTokens.body(14))),
        PSSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
