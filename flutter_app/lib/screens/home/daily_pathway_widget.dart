import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../flow/pathway_coordinator.dart';
import '../../models/daily_session.dart';
import '../../providers/database_provider.dart';
import '../../widgets/passeport_card.dart';

const _stageTitles = {
  PathwayStage.vocab: 'Vocabulary',
  PathwayStage.grammar: 'Grammar',
  PathwayStage.listening: 'Reading & Listening',
  PathwayStage.writing: 'Writing',
  PathwayStage.speaking: 'Speaking',
};

const _stageDetails = {
  PathwayStage.vocab: 'Flashcards with spaced repetition',
  PathwayStage.grammar: 'Pick a tense, or let Marie choose',
  PathwayStage.listening: 'Word-by-word passage walkthrough',
  PathwayStage.writing: 'Short emails, paragraphs, essays',
  PathwayStage.speaking: 'Closing roleplay with Marie',
};

/// The Daily Path card on Home. Thin UI over [PathwayCoordinator]: state
/// comes from the persisted `daily_sessions` row (force-quit safe, resets
/// naturally at midnight), navigation goes through the coordinator, and there
/// is exactly ONE primary action — Continue. Stages that aren't current are
/// an outline, not five competing tap targets (PILOT_PLAN.md P0.1/P0.4).
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
    _coordinator = PathwayCoordinator(store: ref.read(learningStoreProvider));
  }

  Future<void> _continue() async {
    await _coordinator.continueNext(context);
    if (!mounted) return;
    setState(() {});
    widget.onProgress?.call();
  }

  Future<void> _skipCurrent() async {
    final stage = _coordinator.nextStage;
    if (stage == null) return;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Today's French", style: Passeport.display(16, weight: FontWeight.w500)),
              const Spacer(),
              Text(_progressLabel(session),
                  style: Passeport.mono(9, weight: FontWeight.w500).copyWith(color: Passeport.slateDim)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            next != null ? _leadLine(session, next) : 'Pathway complete — à demain !',
            style: Passeport.body(12).copyWith(color: Passeport.slateDim),
          ),
          const SizedBox(height: 12),
          if (next != null) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Passeport.maroon,
                        foregroundColor: Passeport.parchment,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        _isResuming(session, next) ? 'Continue — ${_stageTitles[next]}' : 'Continue',
                        style: Passeport.body(14, weight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _skipCurrent,
                  child: Text('Skip', style: Passeport.body(12).copyWith(color: Passeport.slateDim)),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          for (final stage in PathwayStage.values) _stageRow(session, stage, next),
        ],
      ),
    );
  }

  String _progressLabel(DailySession session) {
    final done = PathwayStage.values
        .where((s) =>
            session.stages[s]!.status == StageStatus.completed ||
            session.stages[s]!.status == StageStatus.skipped)
        .length;
    return '$done of ${PathwayStage.values.length}';
  }

  String _leadLine(DailySession session, PathwayStage next) {
    if (_isResuming(session, next)) {
      return 'Pick up where you left off — ${_stageTitles[next]!.toLowerCase()} is waiting.';
    }
    return 'Next: ${_stageTitles[next]} · ${_stageDetails[next]}';
  }

  bool _isResuming(DailySession session, PathwayStage next) =>
      session.stages[next]!.status == StageStatus.paused;

  Widget _stageRow(DailySession session, PathwayStage stage, PathwayStage? next) {
    final record = session.stages[stage]!;
    final isDone = record.status == StageStatus.completed;
    final isSkipped = record.status == StageStatus.skipped;
    final isPaused = record.status == StageStatus.paused;
    final isNext = stage == next;

    final icon = isDone
        ? Icons.check_circle
        : isSkipped
            ? Icons.remove_circle_outline
            : isPaused
                ? Icons.pause_circle_outline
                : Icons.circle_outlined;
    final iconColor = isDone
        ? Passeport.brass
        : isNext
            ? Passeport.maroon
            : Passeport.slate;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _stageTitles[stage]!,
              style: Passeport.body(12.5, weight: isNext ? FontWeight.w600 : FontWeight.w400).copyWith(
                color: isNext ? Passeport.text : Passeport.slateDim,
                decoration: isDone || isSkipped ? TextDecoration.lineThrough : null,
                decorationColor: Passeport.slateDim,
              ),
            ),
          ),
          if (isPaused && isNext)
            Text('paused', style: Passeport.mono(9).copyWith(color: Passeport.slateDim))
          else if (!isDone && !isSkipped && !isNext)
            Text('later', style: Passeport.mono(9).copyWith(color: Passeport.slate)),
        ],
      ),
    );
  }
}
