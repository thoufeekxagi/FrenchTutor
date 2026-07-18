import 'package:flutter/material.dart' show showDialog;
import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/content_service.dart';
import '../data/database/evidence_store.dart';
import '../data/database/learning_store.dart';
import '../design/app_router.dart';
import '../models/content_models.dart';
import '../models/daily_session.dart';
import '../orchestration/evidence/task_result_adapters.dart';
import '../orchestration/models/competency.dart';
import '../orchestration/models/task_result.dart';
import '../screens/pathway/agent_led_listening_screen.dart';
import '../screens/pathway/agent_led_vocab_screen.dart';
import '../screens/pathway/agent_led_grammar_screen.dart';
import '../screens/pathway/grammar_picker_screen.dart';
import '../screens/pathway/pathway_writing_screen.dart';
import '../services/lesson_agent_service.dart';
import '../services/srs_service.dart';
import '../widgets/adaptive/adaptive.dart';
import '../screens/pathway/vocab_picker_screen.dart';
import '../screens/session/session_screen.dart';
import 'stage_outcome.dart';

/// The single owner of Daily Path navigation and state (PILOT_PLAN.md Phase 1).
///
/// - Every stage screen is pushed from here and returns a typed StageOutcome
///   exactly once; no stage screen ever calls a parent callback or navigates
///   for another route.
/// - Every transition is persisted immediately to `daily_sessions`, so a
///   force-quit at any point resumes at the same stage with the same content.
/// - Completion is decided HERE from objective evidence, never by a screen
///   being disposed.
class PathwayCoordinator {
  PathwayCoordinator({
    required this.store,
    this.evidenceStore,
    this.taskResultAdapters,
  });

  final LearningStore store;
  final EvidenceStore? evidenceStore;
  final TaskResultAdapters? taskResultAdapters;

  DailySession get session => _session ??= store.dailySession();
  DailySession? _session;

  /// Today's row, re-read (a new day means a fresh row automatically).
  void reload() => _session = store.dailySession();

  void _save() => store.saveDailySession(session);

  StageStatus statusOf(PathwayStage stage) => session.stages[stage]!.status;

  PathwayStage? get nextStage => session.nextStage;

  bool get isComplete => session.isComplete;

  /// Opens the next incomplete stage — the one Continue button's action.
  Future<void> continueNext(BuildContext context) async {
    final stage = nextStage;
    if (stage == null) return;
    await openStage(context, stage);
  }

  /// Deliberate learner choice, distinct from abandoning mid-way.
  void skipStage(PathwayStage stage) {
    session.stages[stage]!.status = StageStatus.skipped;
    _maybeFinishDay();
    _save();
  }

  Future<void> openStage(BuildContext context, PathwayStage stage) async {
    session.startedAt ??= DateTime.now();
    session.currentStage = stage;
    session.stages[stage]!.status = StageStatus.active;
    _save();

    switch (stage) {
      case PathwayStage.vocab:
        await _runVocab(context);
      case PathwayStage.grammar:
        await _runGrammar(context);
      case PathwayStage.listening:
        await _runListening(context);
      case PathwayStage.writing:
        await _runWriting(context);
      case PathwayStage.speaking:
        await _runSpeaking(context);
    }
  }

  // ---------------------------------------------------------------------------
  // Stages
  // ---------------------------------------------------------------------------

  Future<void> _runVocab(BuildContext context) async {
    // Snapshot BEFORE the screen runs: a day's vocab can span several sittings
    // (save-and-continue-later), and each sitting only reports its own words —
    // credit from earlier sittings must merge, never be overwritten.
    final prior = session.stages[PathwayStage.vocab]!.resultJson;
    final priorPracticed =
        (prior?['wordIds'] as List?)?.cast<String>() ?? const <String>[];
    final priorPlanned =
        (prior?['plannedWordIds'] as List?)?.cast<String>() ?? const <String>[];

    final outcome = await AppRouter.push<StageOutcome<VocabStageResult>>(
      context,
      (_) => const VocabPickerScreen(),
      fullscreenDialog: true,
    );
    _applyOutcome(
      PathwayStage.vocab,
      outcome,
      toJson: (r) {
        // Persist the covered word ids: writing targets and the speaking
        // roleplay rebuild VocabEntry objects from these. plannedWordIds is
        // the day's chosen set — what "continue where you left off" reads.
        final practiced = {
          ...priorPracticed,
          ...r.wordsCovered.map((e) => e.id),
        }.toList();
        final planned = {
          ...priorPlanned,
          ...r.plannedWordIds,
        }.toList();
        return {
          'wordIds': practiced,
          'plannedWordIds': planned,
          'reviewedCount': practiced.length,
        };
      },
    );
    final result = outcome?.result;
    final adapters = taskResultAdapters;
    if (result != null && adapters != null) {
      final supportedIds = result.wordsCovered
          .map((word) => word.id)
          .where(
            (id) =>
                adapters.supports(id, PerformanceModality.readingRecognition),
          )
          .toList(growable: false);
      _recordTaskResult(
        PathwayStage.vocab,
        adapters.vocabulary(
          context: _evidenceContext(outcome!),
          reviewedContentItemIds: supportedIds,
        ),
      );
    }
    if (result != null && result.reviewedCount > 0) {
      store.markHabit('anki', minutes: 5);
    }
  }

  Future<void> _runGrammar(BuildContext context) async {
    final outcome = await AppRouter.push<StageOutcome<GrammarStageResult>>(
      context,
      (_) => GrammarPickerScreen(vocabSummary: _vocabResult()),
      fullscreenDialog: true,
    );
    _applyOutcome(
      PathwayStage.grammar,
      outcome,
      toJson: (r) {
        return {
          'topicTitle': r.topicTitle,
          'drillsCorrect': r.drillResults.where((d) => d).length,
          'drillsTotal': r.drillResults.length,
        };
      },
    );
    final result = outcome?.result;
    final adapters = taskResultAdapters;
    final contentItemId = result == null || adapters == null
        ? null
        : _grammarContentItemId(result.topicTitle, adapters);
    if (result != null && contentItemId != null && adapters != null) {
      _recordTaskResult(
        PathwayStage.grammar,
        adapters.grammar(
          context: _evidenceContext(outcome!),
          contentItemId: contentItemId,
          drillResults: result.drillResults,
        ),
      );
    }
    if (outcome?.isCompleted == true) {
      store.markHabit('reading', minutes: 8);
    }
  }

  Future<void> _runListening(BuildContext context) async {
    // The scene is written ONCE per day by the orchestration (Flash-Lite
    // two-role script from today's words) and frozen in the daily record.
    // A cached passage WITHOUT a script (legacy lab mapping, pre-script
    // generations from testing) is stale — regenerated, never replayed:
    // that was the "same croissant/€5 lab content forever" bug.
    var passage = _persistedPassage();
    final hasScript =
        passage?.segments.any((s) => (s.characterFr ?? '').isNotEmpty) ??
        false;
    if (!hasScript) passage = null;

    passage ??= await _generateScene(context);
    if (passage == null) {
      // Generation failed (offline, rate limit): the stage stays pending and
      // can be retried — lab content is never silently substituted as a scene.
      session.stages[PathwayStage.listening]!.status = StageStatus.pending;
      session.currentStage = null;
      _save();
      return;
    }
    session.readingPassageJson = passage.toJson();
    _save();

    if (!context.mounted) return;
    final outcome = await AppRouter.push<StageOutcome<ListeningStageResult>>(
      context,
      (_) => AgentLedListeningScreen(
        passage: passage!,
        vocabSummary: _vocabResult(),
      ),
      fullscreenDialog: true,
    );
    _applyOutcome(
      PathwayStage.listening,
      outcome,
      toJson: (r) {
        return {
          'attempted': r.listeningAttempted,
          'correct': r.listeningCorrect,
        };
      },
    );
    final result = outcome?.result;
    final adapters = taskResultAdapters;
    if (result != null && adapters != null) {
      _recordTaskResult(
        PathwayStage.listening,
        adapters.listening(
          context: _evidenceContext(outcome!),
          contentItemId: passage.id,
          correct: result.listeningCorrect,
          attempted: result.listeningAttempted,
          objectivelyGraded: false,
        ),
      );
    }
    if (outcome?.result != null && outcome!.result!.listeningAttempted > 0) {
      store.markHabit('listening', minutes: 8);
    }
  }

  Future<void> _runWriting(BuildContext context) async {
    final outcome = await AppRouter.push<StageOutcome<WritingStageResult>>(
      context,
      (_) => PathwayWritingScreen(targetWords: _writingTargets()),
      fullscreenDialog: true,
    );
    _applyOutcome(
      PathwayStage.writing,
      outcome,
      toJson: (r) {
        return {
          if (r.score != null) 'score': r.score,
          if (r.hintsUsed > 0) 'hintsUsed': r.hintsUsed,
        };
      },
    );
    final result = outcome?.result;
    final adapters = taskResultAdapters;
    if (result != null && adapters != null) {
      _recordTaskResult(
        PathwayStage.writing,
        adapters.writing(
          context: _evidenceContext(outcome!),
          contentItemId: 'w01',
          scoreOutOf10: result.score,
          hintsUsed: result.hintsUsed,
        ),
      );
    }
    if (outcome?.isCompleted == true) {
      store.markHabit('writing', minutes: 5);
    }
  }

  Future<void> _runSpeaking(BuildContext context) async {
    final result = await AppRouter.push<SpeakingResult>(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        lessonContext: _speakingContext(),
        stage: 'speaking',
        dailySessionId: session.id,
      ),
      fullscreenDialog: true,
    );
    // The threshold lives here: a cancelled dial, a dead connection, or a
    // silent call is an attempt, not a completion (P0.3).
    if (result != null && result.meetsThreshold) {
      _applyOutcome(
        PathwayStage.speaking,
        StageOutcome.completed({
          'durationSeconds': result.durationSeconds,
          'utterances': result.learnerUtteranceCount,
        }, reason: result.endedReason),
        toJson: (r) => r,
      );
    } else {
      _applyOutcome(
        PathwayStage.speaking,
        StageOutcome<Map<String, dynamic>>.paused(
          reason: result?.endedReason ?? 'cancelled',
        ),
        toJson: (r) => r,
      );
    }
    final adapters = taskResultAdapters;
    if (result != null && adapters != null) {
      _recordTaskResult(
        PathwayStage.speaking,
        adapters.speaking(
          context: TaskEvidenceContext(
            sessionId: session.id,
            status: result.meetsThreshold
                ? TaskResultStatus.completed
                : TaskResultStatus.abandoned,
            occurredAt: DateTime.now(),
          ),
          contentItemId: 'describe_work',
          learnerUtteranceCount: result.learnerUtteranceCount,
          durationSeconds: result.durationSeconds,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Shared plumbing
  // ---------------------------------------------------------------------------

  /// Records a stage's outcome. Null (route dismissed without a value —
  /// should not happen once all exits pop a result, but a system-level pop
  /// must never count as done) is treated as paused-with-nothing.
  void _applyOutcome<T>(
    PathwayStage stage,
    StageOutcome<T>? outcome, {
    required Map<String, dynamic> Function(T result) toJson,
  }) {
    final record = session.stages[stage]!;
    if (outcome == null) {
      record.status = StageStatus.paused;
    } else {
      record.status = outcome.status;
      final result = outcome.result;
      if (result != null) {
        record.resultJson = {...toJson(result), 'reason': outcome.reason};
      } else if (outcome.reason != 'finished') {
        record.resultJson = {'reason': outcome.reason};
      }
    }
    session.currentStage = null;
    _maybeFinishDay();
    _save();
  }

  TaskEvidenceContext _evidenceContext<T>(StageOutcome<T> outcome) =>
      TaskEvidenceContext(
        sessionId: session.id,
        status: switch (outcome.status) {
          StageStatus.completed => TaskResultStatus.completed,
          StageStatus.skipped => TaskResultStatus.skipped,
          StageStatus.pending ||
          StageStatus.active ||
          StageStatus.paused => TaskResultStatus.abandoned,
        },
        occurredAt: DateTime.now(),
      );

  void _recordTaskResult(PathwayStage stage, TaskResult result) {
    final evidence = evidenceStore;
    if (evidence == null) return;
    evidence.insertTaskResult(result);
    final record = session.stages[stage]!;
    record.resultJson = {
      ...?record.resultJson,
      'evidenceEventIds': result.competencyEvidence
          .map((event) => event.id)
          .toList(growable: false),
      'evidenceWithheld': ?result.technicalMetadata['evidenceWithheld'],
    };
    _save();
  }

  String? _grammarContentItemId(String title, TaskResultAdapters adapters) {
    final pack = ContentService.shared.grammar();
    if (pack == null) return null;
    for (final lesson in pack.lessons) {
      if (lesson.title == title &&
          adapters.supports(
            lesson.id,
            PerformanceModality.controlledSpeaking,
          )) {
        return lesson.id;
      }
    }
    for (final topic in pack.topics) {
      if (topic.title == title &&
          adapters.supports(topic.id, PerformanceModality.controlledSpeaking)) {
        return topic.id;
      }
    }
    return null;
  }

  void _maybeFinishDay() {
    if (session.isComplete && session.completedAt == null) {
      session.completedAt = DateTime.now();
    }
  }

  VocabStageResult? _vocabResult() {
    final json = session.stages[PathwayStage.vocab]!.resultJson;
    if (json == null) return null;
    final words = _entriesByIds(
      (json['wordIds'] as List?)?.cast<String>() ?? const [],
    );
    return VocabStageResult(
      wordsCovered: words,
      reviewedCount: (json['reviewedCount'] as int?) ?? 0,
    );
  }

  ReadingPassage? _persistedPassage() {
    final json = session.readingPassageJson;
    if (json == null) return null;
    try {
      return ReadingPassage.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Writes today's scene via Flash-Lite. Scene words: today's covered vocab
  /// when there is any; otherwise (vocab skipped — a first-class flow) the
  /// learner's mixed SRS queue; last resort, the first content words. The
  /// scene ALWAYS comes from the LLM — lab exercises are never mapped in.
  Future<ReadingPassage?> _generateScene(BuildContext context) async {
    var words = _vocabResult()?.wordsCovered ?? const <VocabEntry>[];
    if (words.isEmpty) {
      try {
        words = await SRSService(store: store).dailyMixedQueue();
      } catch (_) {
        words = const [];
      }
    }
    if (words.isEmpty) {
      words = ContentService.shared.vocabPhases
          .expand((p) => p.themes.expand((t) => t.entries))
          .take(6)
          .toList();
    }
    if (words.isEmpty) return null;
    words = words.take(6).toList();

    if (!context.mounted) return null;
    // Small blocking indicator while the script is written (~1-3s).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: PSProgressIndicator(),
      ),
    );
    ReadingPassage? passage;
    try {
      passage = await LessonAgentService.shared
          .buildReadingPassageFromVocab(words: words)
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      passage = null;
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    return passage;
  }

  List<VocabEntry> _entriesByIds(List<String> ids) {
    if (ids.isEmpty) return const [];
    final wanted = ids.toSet();
    return ContentService.shared.vocabPhases
        .expand((p) => p.themes.expand((t) => t.entries))
        .where((e) => wanted.contains(e.id))
        .toList();
  }

  List<VocabEntry> _writingTargets() {
    final covered = _vocabResult()?.wordsCovered ?? const [];
    if (covered.isEmpty) return const [];
    final shuffled = [...covered]..shuffle();
    return shuffled.take(2).toList();
  }

  /// Rich context for the closing roleplay, rebuilt from the PERSISTED stage
  /// results — survives restarts, unlike the old in-memory fields.
  String _speakingContext() {
    final parts = <String>[
      "DAILY PATHWAY — CLOSING ROLEPLAY: have a short natural conversation using today's material in a real-world scenario relevant to TEF/TCF Canada prep.",
    ];
    final vocab = _vocabResult();
    if (vocab != null && vocab.wordsCovered.isNotEmpty) {
      parts.add(
        'Vocabulary covered today: ${vocab.wordsCovered.map((e) => e.fr).join(", ")}',
      );
    }
    final grammar = session.stages[PathwayStage.grammar]!.resultJson;
    if (grammar?['topicTitle'] != null) {
      parts.add('Grammar focus today: ${grammar!['topicTitle']}.');
    }
    final listening = session.stages[PathwayStage.listening]!.resultJson;
    final attempted = (listening?['attempted'] as int?) ?? 0;
    if (attempted > 0) {
      parts.add(
        "Reading & listening: went through $attempted part(s) of today's passage.",
      );
    }
    final writing = session.stages[PathwayStage.writing]!.resultJson;
    if (writing?['score'] != null) {
      parts.add(
        'Writing score today: ${(writing!['score'] as num).toStringAsFixed(1)}/10.',
      );
    }
    return parts.join('\n\n');
  }
}
