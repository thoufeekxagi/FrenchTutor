import '../models/daily_session.dart';

/// The typed value every pathway stage screen returns via `Navigator.pop`,
/// exactly once. Screens never call parent callbacks and never decide what
/// their exit means for the day — the PathwayCoordinator does (PILOT_PLAN.md
/// P0.2/P0.3/P0.5). `dispose()` releases resources only.
class StageOutcome<T> {
  const StageOutcome._(this.status, this.result, this.reason);

  /// Objective completion criteria were met.
  const StageOutcome.completed(T result, {String reason = 'finished'})
    : this._(StageStatus.completed, result, reason);

  /// The learner left or the connection dropped mid-stage. Partial evidence
  /// (already-graded cards, drills answered) may ride along in [result], but
  /// the stage stays incomplete and resumable.
  const StageOutcome.paused({T? result, String reason = 'paused'})
    : this._(StageStatus.paused, result, reason);

  /// Deliberate learner choice to skip the stage today.
  const StageOutcome.skipped({String reason = 'skipped'})
    : this._(StageStatus.skipped, null, reason);

  final StageStatus status;
  final T? result;

  /// finished | cancelled | disconnected | error | no_content | skipped …
  final String reason;

  bool get isCompleted => status == StageStatus.completed;
}

/// What the speaking screen actually observed — the coordinator applies the
/// completion threshold (connected + >=1 learner utterance + >=30s), so a
/// cancelled dial or a silent call can never mark the stage done.
class SpeakingResult {
  const SpeakingResult({
    required this.connected,
    required this.durationSeconds,
    required this.learnerUtteranceCount,
    required this.endedReason,
  });

  final bool connected;
  final int durationSeconds;
  final int learnerUtteranceCount;
  final String endedReason;

  bool get meetsThreshold =>
      connected && learnerUtteranceCount >= 1 && durationSeconds >= 30;
}
