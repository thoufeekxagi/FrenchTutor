import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../flow/pathway_coordinator.dart';
import '../../models/daily_session.dart';
import '../../providers/database_provider.dart';
import '../../widgets/adaptive/adaptive.dart';
import '../../widgets/passeport_card.dart';

const _stageTitles = {
  PathwayStage.vocab: 'Vocabulary',
  PathwayStage.grammar: 'Grammar',
  PathwayStage.listening: 'Reading & Listening',
  PathwayStage.writing: 'Writing',
  PathwayStage.speaking: 'Speaking',
};

const _stageHints = {
  PathwayStage.vocab: 'a few words, spaced repetition',
  PathwayStage.grammar: 'one pattern, short drills',
  PathwayStage.listening: 'a short passage, word by word',
  PathwayStage.writing: 'two sentences, graded',
  PathwayStage.speaking: 'use it all with Marie',
};

/// The Daily Path card on Home — deliberately compact (2026-07 redesign):
/// title, a five-segment progress bar, ONE next-step line, and Continue.
/// The old five-row checklist said the same thing three times; the segments
/// carry the day's shape at a glance without shouting. State is the persisted
/// `daily_sessions` row via [PathwayCoordinator]; navigation stays owned there.
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
      padding: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Today's French", style: Passeport.display(17, weight: FontWeight.w600)),
              const Spacer(),
              Text(_progressLabel(session),
                  style: Passeport.body(12, weight: FontWeight.w500).copyWith(color: Passeport.slateDim)),
            ],
          ),
          const SizedBox(height: 14),
          _segmentBar(session, next),
          const SizedBox(height: 12),
          Text(
            next != null ? _leadLine(session, next) : 'Done for today — à demain !',
            style: Passeport.body(13).copyWith(color: Passeport.slateDim),
          ),
          if (next != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _continue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Passeport.maroon,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _isResuming(session, next) ? 'Continue ${_stageTitles[next]}' : 'Continue',
                  style: Passeport.body(15, weight: FontWeight.w600),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _skipCurrent,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: Size.zero,
                ),
                child: Text('Skip for today',
                    style: Passeport.body(12).copyWith(color: Passeport.slateDim)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Five thin segments: gold = done, bordeaux = up next, faint = later.
  /// The whole day's shape in one glance, no list.
  Widget _segmentBar(DailySession session, PathwayStage? next) {
    return Row(
      children: [
        for (final stage in PathwayStage.values) ...[
          Expanded(
            child: Tooltip(
              message: _stageTitles[stage]!,
              child: AnimatedContainer(
                duration: DesignTokens.durationMedium,
                curve: DesignTokens.curveStandard,
                height: 5,
                decoration: BoxDecoration(
                  color: _segmentColor(session.stages[stage]!.status, stage == next),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          if (stage != PathwayStage.values.last) const SizedBox(width: 5),
        ],
      ],
    );
  }

  Color _segmentColor(StageStatus status, bool isNext) {
    if (status == StageStatus.completed) return Passeport.brass;
    if (status == StageStatus.skipped) return Passeport.brass.withValues(alpha: 0.35);
    if (isNext) return Passeport.maroon;
    return Passeport.ink.withValues(alpha: 0.08);
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
      return 'Paused in ${_stageTitles[next]!.toLowerCase()} — pick up right where you left off.';
    }
    return 'Up next · ${_stageTitles[next]} — ${_stageHints[next]}';
  }

  bool _isResuming(DailySession session, PathwayStage next) =>
      session.stages[next]!.status == StageStatus.paused;
}
