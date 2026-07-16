import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../flow/pathway_coordinator.dart';
import '../../models/daily_session.dart';
import '../../orchestration/evidence/task_result_adapters.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_card.dart';

const _stageTitles = {
  PathwayStage.vocab: 'Vocabulary',
  PathwayStage.grammar: 'Grammar',
  PathwayStage.listening: 'Reading',
  PathwayStage.writing: 'Writing',
  PathwayStage.speaking: 'Speaking',
};

const _stageIcons = {
  PathwayStage.vocab: CupertinoIcons.square_stack_3d_up,
  PathwayStage.grammar: CupertinoIcons.book,
  PathwayStage.listening: CupertinoIcons.headphones,
  PathwayStage.writing: CupertinoIcons.pencil,
  PathwayStage.speaking: CupertinoIcons.mic_fill,
};

/// Muted per-stage tints — the bento variety of the gamified mockup, held
/// down to the Passeport palette so it stays adult (no candy colors).
const _stageHues = {
  PathwayStage.vocab: Passeport.brass,
  PathwayStage.grammar: Passeport.ink,
  PathwayStage.listening: Passeport.sage,
  PathwayStage.writing: Passeport.maroon,
  PathwayStage.speaking: Passeport.slateDim,
};

/// Today's French as a bento tile grid (2026-07, per ux-design/gamified
/// mockup — its structure, our palette). Each stage is a tile; ONLY the
/// current stage tile is an action (filled bordeaux, Start/Continue), done
/// tiles carry a gold check, later tiles sit muted and inert. Order is still
/// enforced by the PathwayCoordinator; the grid is honest about it.
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
      title: 'Skip ${_stageTitles[stage]!.toLowerCase()}?',
      message: "It won't count as done — tomorrow starts fresh anyway.",
      confirmLabel: 'Skip today',
    );
    if (!confirmed || !mounted) return;
    _coordinator.skipStage(stage);
    setState(() {});
    widget.onProgress?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Re-read on every build: cheap (single indexed row) and guarantees the
    // card reflects the persisted truth, including the midnight rollover.
    _coordinator.reload();
    final session = _coordinator.session;
    final next = _coordinator.nextStage;

    return PasseportCard(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Today's French", style: Passeport.display(17, weight: FontWeight.w600)),
              const Spacer(),
              if (next != null)
                GestureDetector(
                  onTap: _skipCurrent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text('Skip',
                        style: Passeport.body(12.5).copyWith(color: Passeport.slateDim)),
                  ),
                )
              else
                Text('à demain !', style: Passeport.body(12.5).copyWith(color: Passeport.slateDim)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            const gap = 10.0;
            final half = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final stage in PathwayStage.values)
                  SizedBox(
                    // 2-column bento; Speaking (the day's finale) gets the
                    // full-width bottom tile.
                    width: stage == PathwayStage.speaking ? constraints.maxWidth : half,
                    child: _StageTile(
                      stage: stage,
                      status: session.stages[stage]!.status,
                      isNext: stage == next,
                      onTap: stage == next ? _openCurrent : null,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.stage,
    required this.status,
    required this.isNext,
    this.onTap,
  });

  final PathwayStage stage;
  final StageStatus status;
  final bool isNext;
  final VoidCallback? onTap;

  bool get _isDone => status == StageStatus.completed;
  bool get _isSkipped => status == StageStatus.skipped;
  bool get _isPaused => status == StageStatus.paused;

  @override
  Widget build(BuildContext context) {
    final hue = _stageHues[stage]!;

    final Color bg;
    final Color fg;
    if (isNext) {
      bg = Passeport.maroon;
      fg = Colors.white;
    } else if (_isDone || _isSkipped) {
      bg = Passeport.brass.withValues(alpha: 0.14);
      fg = Passeport.ink;
    } else {
      bg = hue.withValues(alpha: 0.08);
      fg = Passeport.ink.withValues(alpha: 0.55);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignTokens.durationMedium,
        curve: DesignTokens.curveStandard,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isNext ? Colors.white.withValues(alpha: 0.16) : hue.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                _isDone ? CupertinoIcons.checkmark : _stageIcons[stage]!,
                size: 17,
                color: isNext
                    ? Colors.white
                    : _isDone
                        ? Passeport.brass
                        : hue.withValues(alpha: onTap == null && !_isDone ? 0.6 : 1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _stageTitles[stage]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Passeport.body(13.5, weight: FontWeight.w600).copyWith(color: fg),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _statusLabel,
                    style: Passeport.body(11).copyWith(
                        color: isNext ? Colors.white.withValues(alpha: 0.85) : Passeport.slateDim),
                  ),
                ],
              ),
            ),
            if (isNext)
              const Icon(CupertinoIcons.arrow_right, size: 15, color: Colors.white),
          ],
        ),
      ),
    );
  }

  String get _statusLabel {
    if (isNext) return _isPaused ? 'Continue' : 'Start';
    if (_isDone) return 'Done';
    if (_isSkipped) return 'Skipped';
    return 'Later';
  }
}
