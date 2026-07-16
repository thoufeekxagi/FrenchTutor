import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../flow/pathway_coordinator.dart';
import '../../models/daily_session.dart';
import '../../orchestration/evidence/task_result_adapters.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_primary_button.dart';

const _stageTitles = {
  PathwayStage.vocab: 'Build today’s vocabulary',
  PathwayStage.grammar: 'Put the pattern to work',
  PathwayStage.listening: 'Recognize it in context',
  PathwayStage.writing: 'Make it your own',
  PathwayStage.speaking: 'Use it with Marie',
};

const _stageReasons = {
  PathwayStage.vocab:
      'Start with the words that unlock the rest of today’s practice.',
  PathwayStage.grammar:
      'Use today’s vocabulary inside a pattern you can reuse.',
  PathwayStage.listening:
      'Train your ear on language you have already prepared.',
  PathwayStage.writing:
      'Turn recognition into a sentence you can produce yourself.',
  PathwayStage.speaking:
      'Bring today’s work together in a guided conversation.',
};

const _stageMinutes = {
  PathwayStage.vocab: 6,
  PathwayStage.grammar: 8,
  PathwayStage.listening: 7,
  PathwayStage.writing: 6,
  PathwayStage.speaking: 10,
};

const _stageIcons = {
  PathwayStage.vocab: CupertinoIcons.square_stack_3d_up_fill,
  PathwayStage.grammar: CupertinoIcons.textformat_alt,
  PathwayStage.listening: CupertinoIcons.headphones,
  PathwayStage.writing: CupertinoIcons.pencil,
  PathwayStage.speaking: CupertinoIcons.waveform,
};

class DailyPathwayWidget extends ConsumerStatefulWidget {
  const DailyPathwayWidget({super.key, this.onProgress});

  final VoidCallback? onProgress;

  @override
  ConsumerState<DailyPathwayWidget> createState() => _DailyPathwayWidgetState();
}

class _DailyPathwayWidgetState extends ConsumerState<DailyPathwayWidget> {
  late final PathwayCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    final framework = ref.read(competencyStoreProvider).framework();
    _coordinator = PathwayCoordinator(
      store: ref.read(learningStoreProvider),
      evidenceStore: framework == null ? null : ref.read(evidenceStoreProvider),
      taskResultAdapters: framework == null
          ? null
          : TaskResultAdapters(framework: framework),
    );
  }

  Future<void> _openCurrent() async {
    PSHaptics.light();
    await _coordinator.continueNext(context);
    if (!mounted) return;
    setState(() {});
    widget.onProgress?.call();
  }

  Future<void> _skipCurrent() async {
    final stage = _coordinator.nextStage;
    if (stage == null) return;
    final confirmed = await showPSConfirmDialog(
      context,
      title: 'Skip this step?',
      message:
          'It will stay out of today’s completed practice and reset tomorrow.',
      confirmLabel: 'Skip for today',
    );
    if (!confirmed || !mounted) return;
    _coordinator.skipStage(stage);
    setState(() {});
    widget.onProgress?.call();
  }

  @override
  Widget build(BuildContext context) {
    _coordinator.reload();
    final session = _coordinator.session;
    final next = _coordinator.nextStage;
    final completed = PathwayStage.values.where((stage) {
      final status = session.stages[stage]!.status;
      return status == StageStatus.completed || status == StageStatus.skipped;
    }).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: DesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TODAY’S PLAN',
                style: Passeport.body(
                  11,
                  weight: FontWeight.w700,
                ).copyWith(color: Passeport.slateDim, letterSpacing: 1.1),
              ),
              const Spacer(),
              Text(
                '$completed of ${PathwayStage.values.length}',
                style: Passeport.body(12, weight: FontWeight.w600).copyWith(
                  color: next == null ? Passeport.sage : Passeport.slateDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PathProgress(session: session),
          const SizedBox(height: 22),
          if (next == null)
            const _PlanComplete()
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Passeport.infoSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _stageIcons[next],
                    color: Passeport.sky,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.stages[next]!.status == StageStatus.paused
                            ? 'READY TO RESUME'
                            : 'NEXT UP',
                        style: Passeport.body(
                          10.5,
                          weight: FontWeight.w700,
                        ).copyWith(color: Passeport.maroon, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(_stageTitles[next]!, style: Passeport.display(22)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _stageReasons[next]!,
              style: Passeport.body(
                15,
              ).copyWith(color: Passeport.slateDim, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.clock,
                  size: 16,
                  color: Passeport.slateDim,
                ),
                const SizedBox(width: 6),
                Text(
                  'About ${_stageMinutes[next]} min',
                  style: Passeport.body(
                    13,
                    weight: FontWeight.w600,
                  ).copyWith(color: Passeport.slateDim),
                ),
                const SizedBox(width: 16),
                const Icon(
                  CupertinoIcons.arrow_right_circle,
                  size: 16,
                  color: Passeport.slateDim,
                ),
                const SizedBox(width: 6),
                Text(
                  'Step ${PathwayStage.values.indexOf(next) + 1} of 5',
                  style: Passeport.body(
                    13,
                    weight: FontWeight.w600,
                  ).copyWith(color: Passeport.slateDim),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PasseportPrimaryButton(
              label: session.stages[next]!.status == StageStatus.paused
                  ? 'Resume session'
                  : 'Start session',
              icon: CupertinoIcons.arrow_right,
              onPressed: _openCurrent,
            ),
            const SizedBox(height: 4),
            Center(
              child: SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: _skipCurrent,
                  child: Text(
                    'Skip for today',
                    style: Passeport.body(
                      13,
                      weight: FontWeight.w500,
                    ).copyWith(color: Passeport.slateDim),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PathProgress extends StatelessWidget {
  const _PathProgress({required this.session});

  final DailySession session;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < PathwayStage.values.length; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 3,
                color: _isReached(PathwayStage.values[index])
                    ? Passeport.sage
                    : Passeport.parchmentDim,
              ),
            ),
          _ProgressNode(
            status: session.stages[PathwayStage.values[index]]!.status,
          ),
        ],
      ],
    );
  }

  bool _isReached(PathwayStage stage) {
    final index = PathwayStage.values.indexOf(stage);
    final previous = session.stages[PathwayStage.values[index - 1]]!.status;
    return previous == StageStatus.completed || previous == StageStatus.skipped;
  }
}

class _ProgressNode extends StatelessWidget {
  const _ProgressNode({required this.status});

  final StageStatus status;

  @override
  Widget build(BuildContext context) {
    final isDone =
        status == StageStatus.completed || status == StageStatus.skipped;
    final isCurrent =
        status == StageStatus.active || status == StageStatus.paused;
    return AnimatedContainer(
      duration: DesignTokens.durationFast,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isDone
            ? Passeport.sage
            : isCurrent
            ? Passeport.maroon
            : Passeport.parchmentDim,
        shape: BoxShape.circle,
      ),
      child: isDone
          ? const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 14)
          : isCurrent
          ? const Icon(
              CupertinoIcons.arrow_right,
              color: Colors.white,
              size: 12,
            )
          : null,
    );
  }
}

class _PlanComplete extends StatelessWidget {
  const _PlanComplete();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Passeport.successSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.checkmark_seal_fill,
            color: Passeport.sage,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text('Today’s plan is complete', style: Passeport.display(22)),
          const SizedBox(height: 6),
          Text(
            'Your practice is saved. The next plan starts fresh tomorrow.',
            style: Passeport.body(
              14,
            ).copyWith(color: Passeport.slateDim, height: 1.4),
          ),
        ],
      ),
    );
  }
}
