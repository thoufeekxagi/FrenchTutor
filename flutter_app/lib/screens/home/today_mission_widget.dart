import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../flow/mission_task_executor.dart';
import '../../orchestration/evidence/task_result_adapters.dart';
import '../../orchestration/models/competency.dart';
import '../../orchestration/models/content_descriptor.dart';
import '../../orchestration/models/mission.dart';
import '../../orchestration/models/plan_task.dart';
import '../../orchestration/models/learning_plan.dart';
import '../../orchestration/planning/rotation_planner.dart';
import '../../design/app_router.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_primary_button.dart';
import '../subscription/paywall_screen.dart';

/// The rotation planner doesn't participate in the competency graph at all
/// (see plan: "Replace the mission/competency-catalog system with a simple
/// daily content rotation") — an empty framework means `supports()` always
/// reports false, so `TaskResultAdapters` gracefully skips evidence for
/// every rotated task rather than needing thousands of content-competency
/// mappings authored for a system that's no longer in the loop.
const _noCompetencyFramework = CompetencyFramework(
  frameworkVersion: 'none',
  curriculumVersion: 'none',
  competencies: [],
  mappings: [],
);

class TodayMissionWidget extends ConsumerStatefulWidget {
  const TodayMissionWidget({super.key, this.onProgress});

  final VoidCallback? onProgress;

  @override
  ConsumerState<TodayMissionWidget> createState() => _TodayMissionWidgetState();
}

class _TodayMissionWidgetState extends ConsumerState<TodayMissionWidget> {
  PlanSnapshot? _plan;
  MissionDefinition? _mission;
  String? _error;
  bool _loading = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final planStore = ref.read(planStoreProvider);
      final now = DateTime.now();
      final localDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      const planner = RotationPlanner();
      final existingRaw = planStore.activePlanForDate(localDate);
      // A persisted "active" plan with zero tasks is corrupt/stale (nothing
      // to resume) — `.first` below would crash the whole screen on load.
      // Treat it the same as "no plan yet" and generate a fresh one instead.
      final existing = existingRaw != null && existingRaw.tasks.isNotEmpty
          ? existingRaw
          : null;
      PlanSnapshot plan;
      MissionDefinition mission;
      if (existing != null) {
        plan = existing;
        final modalityName = existing.inputSnapshot['modality'] as String?;
        final modality = modalityName == null
            ? existing.tasks.first.modality
            : PerformanceModality.values.firstWhere(
                (m) => m.wireName == modalityName,
                orElse: () => existing.tasks.first.modality,
              );
        mission = planner.buildMissionFor(
          contentItemIds: existing.tasks.map((t) => t.contentItemId).toList(),
          modality: modality,
          learnerLevel: profile.level,
        );
      } else {
        final result = planner.buildNext(
          planStore: planStore,
          learningStore: ref.read(learningStoreProvider),
          content: ref.read(contentServiceProvider),
          localDate: localDate,
          availableMinutes: _minutesFor(profile.sessionLength),
          learnerLevel: profile.level,
        );
        planStore.savePlan(result.plan);
        plan = result.plan;
        mission = result.mission;
      }
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _mission = mission;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      // Any failure building today's plan used to crash this whole screen
      // (an uncaught exception in an unawaited initState call) — surface it
      // as the same retryable notice `_runNext` already shows for a failed
      // mission step, instead of taking down the app.
      debugPrint('TodayMissionWidget: failed to load today\'s plan: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load today\'s mission. Please try again.';
        _loading = false;
      });
    }
  }

  int _minutesFor(String length) => switch (length) {
    'quick' => 12,
    'deep' => 40,
    _ => 20,
  };

  PlanTaskRecord? get _nextTask {
    final plan = _plan;
    if (plan == null) return null;
    for (final task in plan.tasks) {
      if (task.status == PlanTaskStatus.active ||
          task.status == PlanTaskStatus.pending) {
        return task;
      }
    }
    return null;
  }

  PlanTaskRecord? _nextTaskFor(PlanSnapshot plan) {
    for (final task in plan.tasks) {
      if (task.status == PlanTaskStatus.active ||
          task.status == PlanTaskStatus.pending) {
        return task;
      }
    }
    return null;
  }

  Future<void> _advanceToNextMission(PlanSnapshot completedPlan) async {
    final profile = ref.read(learningStoreProvider).profile();
    final planStore = ref.read(planStoreProvider);
    const planner = RotationPlanner();
    final result = planner.buildNext(
      planStore: planStore,
      learningStore: ref.read(learningStoreProvider),
      content: ref.read(contentServiceProvider),
      localDate: completedPlan.localDate,
      availableMinutes: _minutesFor(profile.sessionLength),
      learnerLevel: profile.level,
      replacesPlanId: completedPlan.id,
      replanReason: 'mission_completed',
    );
    planStore.replan(replaces: completedPlan, newPlan: result.plan);
    if (mounted) {
      setState(() {
        _plan = result.plan;
        _mission = result.mission;
      });
    }
  }

  Future<void> _runNext([PlanTaskRecord? selectedTask]) async {
    final plan = _plan;
    final mission = _mission;
    final task = selectedTask ?? _nextTask;
    if (plan == null || mission == null || task == null) {
      return;
    }
    if (ref.read(subscriptionGateServiceProvider).isModalityLocked(task.modality)) {
      final subscribed = await AppRouter.push<bool>(
        context,
        (_) => const PaywallScreen(),
        fullscreenDialog: true,
      );
      if (subscribed != true || !mounted) return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await MissionTaskExecutor(
        store: ref.read(learningStoreProvider),
        planStore: ref.read(planStoreProvider),
        evidenceStore: ref.read(evidenceStoreProvider),
        taskResultAdapters: TaskResultAdapters(framework: _noCompetencyFramework),
        sceneCacheStore: ref.read(generatedSceneCacheStoreProvider),
      ).run(context: context, task: task, mission: mission);
      final updated = ref.read(planStoreProvider).byId(plan.id);
      if (updated == null) return;
      if (_nextTaskFor(updated) == null) {
        await _advanceToNextMission(updated);
      } else if (mounted) {
        setState(() => _plan = updated);
      }
      widget.onProgress?.call();
    } catch (e) {
      debugPrint('TodayMissionWidget: mission step failed to start: $e');
      if (mounted) {
        setState(() {
          _error = 'This mission step could not start. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _skipNext() {
    final plan = _plan;
    final task = _nextTask;
    if (plan == null || task == null) return;
    ref
        .read(planStoreProvider)
        .completeTask(
          taskId: task.id,
          status: PlanTaskStatus.skipped,
          resultSummary: {'reason': 'learner_skipped'},
        );
    setState(() => _plan = ref.read(planStoreProvider).byId(plan.id));
    widget.onProgress?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: PSProgressIndicator());
    }
    if (_error != null && _plan == null) {
      return _MissionNotice(message: _error!, onRetry: _load);
    }
    final plan = _plan;
    final mission = _mission;
    if (plan == null || mission == null) {
      return _MissionNotice(
        message: 'Your learning plan is not ready yet. Please try again.',
        onRetry: _load,
      );
    }
    final completed = plan.tasks
        .where(
          (task) =>
              task.status == PlanTaskStatus.completed ||
              task.status == PlanTaskStatus.skipped,
        )
        .length;
    final task = _nextTask;
    if (task == null) {
      return _MissionComplete(
        title: mission.title,
        stepCount: plan.tasks.length,
      );
    }
    final locked = ref
        .read(subscriptionGateServiceProvider)
        .isModalityLocked(task.modality);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(DesignTokens.space5),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            boxShadow: DesignTokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'TODAY’S MISSION',
                    style: DesignTokens.body(11, weight: FontWeight.w700)
                        .copyWith(
                          color: DesignTokens.slateDim,
                          letterSpacing: 1.1,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '$completed of ${plan.tasks.length}',
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w600,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
              ),
              // A stepper with a single node conveys nothing (just a lone
              // dot) — only worth showing once there's an actual sequence.
              if (plan.tasks.length > 1) ...[
                const SizedBox(height: DesignTokens.space4),
                _MissionProgress(total: plan.tasks.length, completed: completed),
              ],
              const SizedBox(height: DesignTokens.space5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: locked
                              ? DesignTokens.canvasDim
                              : DesignTokens.infoSoft,
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusMedium,
                          ),
                        ),
                        child: Icon(
                          _iconFor(task.modality),
                          color: locked ? DesignTokens.muted : DesignTokens.info,
                          size: 23,
                        ),
                      ),
                      if (locked)
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: DesignTokens.surface,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              CupertinoIcons.lock_fill,
                              size: 12,
                              color: DesignTokens.mutedDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: DesignTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.status == PlanTaskStatus.active
                              ? 'CONTINUING'
                              : 'NEXT STEP',
                          style:
                              DesignTokens.body(
                                10.5,
                                weight: FontWeight.w700,
                              ).copyWith(
                                color: DesignTokens.primary,
                                letterSpacing: 0.9,
                              ),
                        ),
                        const SizedBox(height: DesignTokens.space1),
                        Text(mission.title, style: DesignTokens.display(22)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space3),
              Text(
                _taskLabel(task.modality),
                style: DesignTokens.body(
                  15,
                  weight: FontWeight.w600,
                ).copyWith(color: DesignTokens.inkSoft),
              ),
              if (_error != null) ...[
                const SizedBox(height: DesignTokens.space3),
                Text(
                  _error!,
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w600,
                  ).copyWith(color: DesignTokens.danger),
                ),
              ],
              const SizedBox(height: DesignTokens.space4),
              Row(
                children: [
                  const Icon(
                    CupertinoIcons.clock,
                    size: 16,
                    color: DesignTokens.slateDim,
                  ),
                  const SizedBox(width: DesignTokens.space2),
                  Text(
                    '${task.estimatedMinutes} min',
                    style: DesignTokens.body(
                      13,
                      weight: FontWeight.w600,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                  const SizedBox(width: DesignTokens.space4),
                  Text(
                    'Step ${task.sequence + 1} of ${plan.tasks.length}',
                    style: DesignTokens.body(
                      13,
                      weight: FontWeight.w600,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.space5),
              PasseportPrimaryButton(
                label: locked
                    ? 'Unlock with subscription'
                    : task.status == PlanTaskStatus.active
                    ? 'Continue mission'
                    : 'Start mission',
                icon: locked ? CupertinoIcons.lock_fill : CupertinoIcons.arrow_right,
                onPressed: _running ? null : _runNext,
                isLoading: _running,
                loadingLabel: 'Preparing your mission…',
              ),
              Center(
                child: SizedBox(
                  height: DesignTokens.minTapTarget,
                  child: TextButton(
                    onPressed: _running ? null : _skipNext,
                    child: Text(
                      'Skip for today',
                      style: DesignTokens.body(
                        13,
                        weight: FontWeight.w500,
                      ).copyWith(color: DesignTokens.slateDim),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconFor(PerformanceModality modality) => switch (modality) {
    PerformanceModality.readingRecognition => CupertinoIcons.rectangle_stack,
    PerformanceModality.listeningRecognition => CupertinoIcons.headphones,
    PerformanceModality.controlledWriting ||
    PerformanceModality.spontaneousWriting => CupertinoIcons.pencil,
    PerformanceModality.controlledSpeaking ||
    PerformanceModality.spontaneousSpeaking => CupertinoIcons.waveform,
    PerformanceModality.pronunciationProduction => CupertinoIcons.mic,
  };

  String _taskLabel(PerformanceModality modality) => switch (modality) {
    PerformanceModality.readingRecognition =>
      'Learn the words for this mission',
    PerformanceModality.listeningRecognition =>
      'Understand the scenario in context',
    PerformanceModality.controlledWriting =>
      'Build a supported written response',
    PerformanceModality.spontaneousWriting =>
      'Write independently in this scenario',
    PerformanceModality.controlledSpeaking => 'Use the language with Marie',
    PerformanceModality.spontaneousSpeaking => 'Respond naturally with Marie',
    PerformanceModality.pronunciationProduction =>
      'Practise the target sounds aloud',
  };
}

class _MissionProgress extends StatelessWidget {
  const _MissionProgress({required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < total; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 3,
                color: index <= completed
                    ? DesignTokens.success
                    : DesignTokens.canvasDim,
              ),
            ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: index < completed
                  ? DesignTokens.success
                  : index == completed
                  ? DesignTokens.primary
                  : DesignTokens.canvasDim,
              shape: BoxShape.circle,
            ),
            child: index < completed
                ? const Icon(
                    CupertinoIcons.checkmark,
                    color: Colors.white,
                    size: 14,
                  )
                : null,
          ),
        ],
      ],
    );
  }
}

class _MissionComplete extends StatelessWidget {
  const _MissionComplete({required this.title, required this.stepCount});

  final String title;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.successSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.checkmark_seal_fill,
            color: DesignTokens.success,
            size: 28,
          ),
          const SizedBox(height: DesignTokens.space3),
          Text('Mission complete', style: DesignTokens.display(22)),
          const SizedBox(height: DesignTokens.space1),
          Text(
            '$title is saved with $stepCount completed step${stepCount == 1 ? '' : 's'}. Your next mission will build on this practice.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.slateDim, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MissionNotice extends StatelessWidget {
  const _MissionNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.space5),
      decoration: BoxDecoration(
        color: DesignTokens.infoSoft,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: DesignTokens.body(15).copyWith(height: 1.4)),
          const SizedBox(height: DesignTokens.space3),
          SizedBox(
            width: 160,
            child: PasseportPrimaryButton(
              label: 'Try again',
              onPressed: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}
