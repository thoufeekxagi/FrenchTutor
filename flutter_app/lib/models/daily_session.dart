import 'dart:convert';

/// Lifecycle of one stage inside a day's pathway. `paused`/`abandoned` exist so
/// that closing a screen or losing the network is never silently recorded as
/// learning (PILOT_PLAN.md P0.2/P0.3) — only explicit evidence marks `completed`.
enum StageStatus { pending, active, paused, completed, skipped }

enum PathwayStage { vocab, grammar, listening, writing, speaking }

/// Per-stage persisted record: status plus a small free-form result summary
/// (words covered, scores, utterance counts) that later stages feed on.
class StageRecord {
  StageRecord({this.status = StageStatus.pending, this.resultJson});

  StageStatus status;
  Map<String, dynamic>? resultJson;

  Map<String, dynamic> toJson() => {
    'status': status.name,
    if (resultJson != null) 'result': resultJson,
  };

  factory StageRecord.fromJson(Map<String, dynamic> json) => StageRecord(
    status:
        StageStatus.values.asNameMap()[json['status']] ?? StageStatus.pending,
    resultJson: (json['result'] as Map?)?.cast<String, dynamic>(),
  );
}

/// One row of `daily_sessions` — the persisted, resumable Daily Path. Today's
/// content (word list, passage) is fixed here at first assembly and never
/// regenerated mid-day, so an interrupted learner resumes the exact same plan.
class DailySession {
  DailySession({
    required this.id,
    required this.localDate,
    this.plannedLength = 'standard',
    this.currentStage,
    this.currentItemIndex = 0,
    Map<PathwayStage, StageRecord>? stages,
    this.vocabEntryIds,
    this.grammarLessonId,
    this.readingPassageJson,
    this.startedAt,
    this.completedAt,
  }) : stages =
           stages ?? {for (final s in PathwayStage.values) s: StageRecord()};

  final String id;
  final String localDate; // YYYY-MM-DD device-local
  String plannedLength; // quick | standard | deep
  PathwayStage? currentStage;
  int currentItemIndex;
  final Map<PathwayStage, StageRecord> stages;
  List<String>? vocabEntryIds;
  String? grammarLessonId;
  Map<String, dynamic>? readingPassageJson;
  DateTime? startedAt;
  DateTime? completedAt;

  bool get isComplete => PathwayStage.values.every(
    (s) =>
        stages[s]!.status == StageStatus.completed ||
        stages[s]!.status == StageStatus.skipped,
  );

  PathwayStage? get nextStage {
    for (final s in PathwayStage.values) {
      final status = stages[s]!.status;
      if (status != StageStatus.completed && status != StageStatus.skipped) {
        return s;
      }
    }
    return null;
  }

  String stagesToJson() => jsonEncode(
    stages.map((stage, record) => MapEntry(stage.name, record.toJson())),
  );

  static Map<PathwayStage, StageRecord> stagesFromJson(String json) {
    final decoded = (jsonDecode(json) as Map).cast<String, dynamic>();
    return {
      for (final s in PathwayStage.values)
        s: decoded[s.name] != null
            ? StageRecord.fromJson(
                (decoded[s.name] as Map).cast<String, dynamic>(),
              )
            : StageRecord(),
    };
  }
}
