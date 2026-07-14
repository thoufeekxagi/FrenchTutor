import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/content_service.dart';
import '../data/database/learning_store.dart';
import '../design/app_router.dart';
import '../models/content_models.dart';
import '../models/daily_session.dart';
import '../screens/pathway/agent_led_listening_screen.dart';
import '../screens/pathway/agent_led_vocab_screen.dart';
import '../screens/pathway/agent_led_grammar_screen.dart';
import '../screens/pathway/grammar_picker_screen.dart';
import '../screens/pathway/pathway_writing_screen.dart';
import '../screens/pathway/post_vocab_choice_screen.dart';
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
  PathwayCoordinator({required this.store});

  final LearningStore store;

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
    final outcome = await AppRouter.push<StageOutcome<VocabStageResult>>(
      context,
      (_) => const VocabPickerScreen(),
      fullscreenDialog: true,
    );
    _applyOutcome(PathwayStage.vocab, outcome, toJson: (r) {
      // Persist the covered word ids: writing targets and the speaking
      // roleplay rebuild VocabEntry objects from these.
      return {
        'wordIds': r.wordsCovered.map((e) => e.id).toList(),
        'reviewedCount': r.reviewedCount,
      };
    });
    final result = outcome?.result;
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
    _applyOutcome(PathwayStage.grammar, outcome, toJson: (r) {
      return {
        'topicTitle': r.topicTitle,
        'drillsCorrect': r.drillResults.where((d) => d).length,
        'drillsTotal': r.drillResults.length,
      };
    });
    if (outcome?.isCompleted == true) {
      store.markHabit('reading', minutes: 8);
    }
  }

  Future<void> _runListening(BuildContext context) async {
    // The passage is chosen once (post-vocab choice screen) and then frozen in
    // the daily record — never regenerated after an interruption.
    var passage = _persistedPassage();
    if (passage == null) {
      final chosen = await AppRouter.push<PostVocabChoice>(
        context,
        (_) => PostVocabChoiceScreen(
          vocabResult: _vocabResult(),
          fallbackExercise: _fallbackListeningExercise(),
        ),
        fullscreenDialog: true,
      );
      if (chosen == null) {
        // Backed out of the choice — stage stays pending, nothing recorded.
        session.stages[PathwayStage.listening]!.status = StageStatus.pending;
        session.currentStage = null;
        _save();
        return;
      }
      passage = chosen.passage;
      if (passage == null) {
        // Nothing to read today (no vocab covered, no lab exercise): a real
        // empty state, recorded as skipped rather than invented content.
        session.stages[PathwayStage.listening]!.status = StageStatus.skipped;
        session.stages[PathwayStage.listening]!.resultJson = {'reason': 'no_content'};
        _maybeFinishDay();
        _save();
        return;
      }
      session.readingPassageJson = passage.toJson();
      _save();
    }

    if (!context.mounted) return;
    final outcome = await AppRouter.push<StageOutcome<ListeningStageResult>>(
      context,
      (_) => AgentLedListeningScreen(passage: passage!, vocabSummary: _vocabResult()),
      fullscreenDialog: true,
    );
    _applyOutcome(PathwayStage.listening, outcome, toJson: (r) {
      return {'attempted': r.listeningAttempted, 'correct': r.listeningCorrect};
    });
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
    _applyOutcome(PathwayStage.writing, outcome, toJson: (r) {
      return {if (r.score != null) 'score': r.score};
    });
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
        StageOutcome<Map<String, dynamic>>.paused(reason: result?.endedReason ?? 'cancelled'),
        toJson: (r) => r,
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

  void _maybeFinishDay() {
    if (session.isComplete && session.completedAt == null) {
      session.completedAt = DateTime.now();
    }
  }

  VocabStageResult? _vocabResult() {
    final json = session.stages[PathwayStage.vocab]!.resultJson;
    if (json == null) return null;
    final words = _entriesByIds((json['wordIds'] as List?)?.cast<String>() ?? const []);
    return VocabStageResult(wordsCovered: words, reviewedCount: (json['reviewedCount'] as int?) ?? 0);
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

  ListeningExercise? _fallbackListeningExercise() {
    final pack = ContentService.shared.listening();
    final sorted = [...(pack?.exercises ?? <ListeningExercise>[])]
      ..sort((a, b) => a.phase.compareTo(b.phase));
    for (final e in sorted) {
      if (store.lessonStatus('listening_${e.id}').status != 'completed') return e;
    }
    return sorted.isNotEmpty ? sorted.first : null;
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
      parts.add('Vocabulary covered today: ${vocab.wordsCovered.map((e) => e.fr).join(", ")}');
    }
    final grammar = session.stages[PathwayStage.grammar]!.resultJson;
    if (grammar?['topicTitle'] != null) {
      parts.add('Grammar focus today: ${grammar!['topicTitle']}.');
    }
    final listening = session.stages[PathwayStage.listening]!.resultJson;
    final attempted = (listening?['attempted'] as int?) ?? 0;
    if (attempted > 0) {
      parts.add("Reading & listening: went through $attempted part(s) of today's passage.");
    }
    final writing = session.stages[PathwayStage.writing]!.resultJson;
    if (writing?['score'] != null) {
      parts.add('Writing score today: ${(writing!['score'] as num).toStringAsFixed(1)}/10.');
    }
    return parts.join('\n\n');
  }
}
