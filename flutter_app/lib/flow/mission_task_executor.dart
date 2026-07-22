import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/content_service.dart';
import '../data/database/evidence_store.dart';
import '../data/database/generated_scene_cache_store.dart';
import '../data/database/generated_story_store.dart';
import '../data/database/plan_store.dart';
import '../data/database/learning_store.dart';
import '../design/app_router.dart';
import '../models/content_models.dart';
import '../orchestration/evidence/task_result_adapters.dart';
import '../orchestration/models/competency.dart';
import '../orchestration/models/mission.dart';
import '../orchestration/models/plan_task.dart';
import '../orchestration/models/task_result.dart';
import '../services/lesson_agent_service.dart';
import '../services/lesson_speech_service.dart';
import '../screens/lessons/story_reader_screen.dart';
import '../screens/pathway/agent_led_grammar_screen.dart';
import '../screens/pathway/agent_led_listening_screen.dart';
import '../screens/pathway/agent_led_vocab_screen.dart';
import '../screens/pathway/grammar_picker_screen.dart';
import '../screens/pathway/pathway_writing_screen.dart';
import '../screens/pathway/vocab_picker_screen.dart';
import '../screens/session/session_screen.dart';
import 'stage_outcome.dart';

class MissionTaskExecutor {
  MissionTaskExecutor({
    required this.store,
    required this.planStore,
    required this.evidenceStore,
    required this.taskResultAdapters,
    required this.sceneCacheStore,
  });

  final LearningStore store;
  final PlanStore planStore;
  final EvidenceStore evidenceStore;
  final TaskResultAdapters taskResultAdapters;
  final GeneratedSceneCacheStore sceneCacheStore;

  Future<void> run({
    required BuildContext context,
    required PlanTaskRecord task,
    required MissionDefinition mission,
  }) async {
    if (!_isSupported(task.modality)) {
      throw UnsupportedError(
        'Mission task ${task.contentItemId} has no exact executor yet.',
      );
    }
    planStore.startTask(task.id);
    switch (task.modality) {
      case PerformanceModality.readingRecognition:
        await _runVocabulary(context: context, task: task);
      case PerformanceModality.listeningRecognition:
        await _runListening(context: context, task: task, mission: mission);
      case PerformanceModality.controlledSpeaking:
        if (_isGrammarStep(task, mission)) {
          await _runGrammar(context: context, task: task);
        } else {
          await _runSpeaking(context: context, task: task, mission: mission);
        }
      case PerformanceModality.spontaneousSpeaking:
        await _runSpeaking(context: context, task: task, mission: mission);
      case PerformanceModality.controlledWriting:
        await _runWriting(context: context, task: task, mission: mission);
      case PerformanceModality.spontaneousWriting:
        throw UnsupportedError(
          'Mission task ${task.contentItemId} has no exact executor yet.',
        );
      case PerformanceModality.pronunciationProduction:
        await _runPronunciation(context: context, task: task, mission: mission);
    }
  }

  Future<void> _runVocabulary({
    required BuildContext context,
    required PlanTaskRecord task,
  }) async {
    // Every vocabulary word in today's plan is reviewed in ONE batched
    // screen visit, not one screen per word (that's what produced a "mission
    // with a single word" — the planner picks several readingRecognition
    // tasks, but each used to trigger its own separate push). Gather every
    // still-open sibling task of this modality in the same plan and complete
    // them all together based on what the session actually covered.
    final plan = planStore.byId(task.planId);
    final siblingTasks =
        plan?.tasks
            .where(
              (t) =>
                  t.modality == PerformanceModality.readingRecognition &&
                  (t.id == task.id ||
                      t.status == PlanTaskStatus.pending ||
                      t.status == PlanTaskStatus.active),
            )
            .toList() ??
        [task];
    final entryIds = siblingTasks
        .map((t) => t.contentItemId)
        .toSet()
        .toList(growable: false);

    final outcome = await AppRouter.push<StageOutcome<VocabStageResult>>(
      context,
      (_) => VocabPickerScreen(preferredEntryIds: entryIds),
      fullscreenDialog: true,
    );
    if (outcome == null || !outcome.isCompleted) return;
    final result = outcome.result;
    if (result == null) return;
    final coveredIds = result.wordsCovered.map((word) => word.id).toSet();

    for (final sibling in siblingTasks) {
      if (sibling.id != task.id) planStore.startTask(sibling.id);
      final covered =
          coveredIds.contains(sibling.contentItemId) &&
          taskResultAdapters.supports(
            sibling.contentItemId,
            PerformanceModality.readingRecognition,
          );
      evidenceStore.insertTaskResult(
        taskResultAdapters.vocabulary(
          context: _context(sibling, TaskResultStatus.completed),
          reviewedContentItemIds: covered
              ? [sibling.contentItemId]
              : const [],
        ),
      );
      _complete(sibling, {'reviewedCount': covered ? 1 : 0});
    }
  }

  Future<void> _runListening({
    required BuildContext context,
    required PlanTaskRecord task,
    required MissionDefinition mission,
  }) async {
    final step = mission.steps
        .where(
          (item) =>
              item.contentItemId == task.contentItemId &&
              item.modality == task.modality,
        )
        .firstOrNull;
    if (step?.generatedScenario == true) {
      await _runGeneratedListening(
        context: context,
        task: task,
        mission: mission,
      );
      return;
    }
    await _runGeneratedStoryReading(context: context, task: task, mission: mission);
  }

  /// The reading/listening step of a mission — an AI-generated bilingual
  /// story built fresh for this mission's scenario (same generator and
  /// Story/Grammar/Quiz/Keywords reader used by the learner-initiated story
  /// library, see StoryReaderScreen), replacing the old fixed-script,
  /// hardcoded-question `ListeningExerciseScreen`. Graded off the story's
  /// own generated quiz, same shape as the exercise it replaces.
  Future<void> _runGeneratedStoryReading({
    required BuildContext context,
    required PlanTaskRecord task,
    required MissionDefinition mission,
  }) async {
    // Retry-on-transient-failure already lives in one place —
    // LessonAgentService's Gemini call itself (see `_requestGeminiWithRetry`)
    // — so this call site just makes the one call it needs, once. Retrying
    // again here on top of that would mean up to 3x the actual HTTP
    // requests for a single "start mission" tap, for no added reliability.
    final passage = await LessonAgentService.shared.buildPersonalStory(
      topic: mission.scenario,
      levelBand: mission.levelBand,
    );
    // Quiz/keywords generation is a second Gemini round-trip — the story
    // itself is shown the moment its passage is ready rather than making
    // the learner wait through both calls before this step even opens; the
    // reader fills in Quiz/Keywords itself once that call resolves (best
    // effort: the Story/Grammar tabs still work without it, the mission
    // step just won't be objectively gradable this time if it never
    // resolves before the learner finishes).
    final story = GeneratedStory(
      id: newGeneratedStoryId(),
      passage: passage,
      quiz: const [],
      keywords: const [],
      createdAt: DateTime.now(),
    );
    unawaited(
      LessonSpeechService.shared.prewarmNarration([
        for (var i = 0; i < passage.segments.length; i++)
          SpeechItem(
            text: passage.segments[i].fr,
            language: 'fr-FR',
            contentItemId: story.segmentContentId(i),
          ),
      ]),
    );
    if (!context.mounted) return;
    final result = await AppRouter.push<StoryReaderResult>(
      context,
      (_) => StoryReaderScreen(
        story: story,
        showFinishButton: true,
        enrichment: LessonAgentService.shared.buildStoryQuizAndKeywords(passage),
      ),
      fullscreenDialog: true,
    );
    if (result == null) return;
    evidenceStore.insertTaskResult(
      taskResultAdapters.listening(
        context: _context(task, TaskResultStatus.completed),
        contentItemId: task.contentItemId,
        correct: result.correct,
        attempted: result.attempted,
        objectivelyGraded: result.attempted > 0,
      ),
    );
    _complete(task, {'correct': result.correct, 'attempted': result.attempted});
  }

  Future<void> _runGeneratedListening({
    required BuildContext context,
    required PlanTaskRecord task,
    required MissionDefinition mission,
  }) async {
    final topic = _missionTopic(mission);
    if (topic == null) {
      throw StateError('Mission ${mission.id} has no speaking context');
    }
    final scene = await _missionScene(mission: mission, topic: topic);
    if (!context.mounted) return;
    final outcome = await AppRouter.push<StageOutcome<ListeningStageResult>>(
      context,
      (_) => AgentLedListeningScreen(passage: scene),
      fullscreenDialog: true,
    );
    if (outcome == null || !outcome.isCompleted || outcome.result == null) {
      return;
    }
    final result = outcome.result!;
    _complete(task, {
      'correct': result.listeningCorrect,
      'attempted': result.listeningAttempted,
      'evidenceWithheld': 'generated_listening_is_not_objectively_graded',
    });
  }

  Future<void> _runGrammar({
    required BuildContext context,
    required PlanTaskRecord task,
  }) async {
    final outcome = await AppRouter.push<StageOutcome<GrammarStageResult>>(
      context,
      (_) => GrammarPickerScreen(selectedContentId: task.contentItemId),
      fullscreenDialog: true,
    );
    if (outcome == null || !outcome.isCompleted || outcome.result == null) {
      return;
    }
    final result = outcome.result!;
    evidenceStore.insertTaskResult(
      taskResultAdapters.grammar(
        context: _context(task, TaskResultStatus.completed),
        contentItemId: task.contentItemId,
        drillResults: result.drillResults,
      ),
    );
    _complete(task, {
      'drillsCorrect': result.drillResults.where((correct) => correct).length,
      'drillsTotal': result.drillResults.length,
    });
  }

  Future<void> _runWriting({
    required BuildContext context,
    required PlanTaskRecord task,
    required MissionDefinition mission,
  }) async {
    WritingTask writingTask;
    try {
      writingTask = await LessonAgentService.shared.generateWritingTask(
        levelBand: mission.levelBand,
        knownVocab: ContentService.shared.knownVocabWords(store.allSRSStates()),
      );
    } catch (_) {
      // Best-effort: fall back to the static bank rather than block the mission
      // step if generation fails (offline, API error).
      final fallback = _writingTask(task.contentItemId);
      if (fallback == null) {
        throw StateError('Missing writing content ${task.contentItemId}');
      }
      writingTask = fallback;
    }
    if (!context.mounted) return;
    final outcome = await AppRouter.push<StageOutcome<WritingStageResult>>(
      context,
      (_) =>
          PathwayWritingScreen(targetWords: const [], writingTask: writingTask),
      fullscreenDialog: true,
    );
    if (outcome == null || !outcome.isCompleted || outcome.result == null) {
      return;
    }
    final result = outcome.result!;
    evidenceStore.insertTaskResult(
      taskResultAdapters.writing(
        context: _context(task, TaskResultStatus.completed),
        contentItemId: task.contentItemId,
        scoreOutOf10: result.score,
        hintsUsed: result.hintsUsed,
      ),
    );
    _complete(task, {
      if (result.score != null) 'score': result.score,
      'hintsUsed': result.hintsUsed,
    });
  }

  Future<void> _runSpeaking({
    required BuildContext context,
    required PlanTaskRecord task,
    required MissionDefinition mission,
  }) async {
    final topic = _speakingTopic(task.contentItemId);
    if (topic == null) {
      throw StateError('Missing speaking content ${task.contentItemId}');
    }
    final scene = await _missionScene(mission: mission, topic: topic);
    if (!context.mounted) return;
    final result = await AppRouter.push<SpeakingResult>(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        lessonContext:
            '${mission.promptContext}\n\n${ContentService.shared.speakingTopicContext(topic)}\n\n${_sceneContext(scene)}',
        stage: 'speaking',
      ),
      fullscreenDialog: true,
    );
    if (result == null || !result.meetsThreshold) return;
    _complete(task, {
      'durationSeconds': result.durationSeconds,
      'learnerUtteranceCount': result.learnerUtteranceCount,
      'evidenceWithheld': 'engagement_does_not_measure_language_quality',
    });
  }

  Future<void> _runPronunciation({
    required BuildContext context,
    required PlanTaskRecord task,
    required MissionDefinition mission,
  }) async {
    final word = _vocabEntry(task.contentItemId);
    if (word == null) {
      throw StateError('Missing pronunciation content ${task.contentItemId}');
    }
    final result = await AppRouter.push<SpeakingResult>(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        lessonContext:
            '''
${mission.promptContext}

PRONUNCIATION FOCUS: ${word.fr} (${word.phonetic}) means ${word.en}. Ask the learner to repeat this word in short useful sentences. Give one short English coaching cue if needed, then let the learner try again. Do not claim pronunciation accuracy or mastery.''',
        stage: 'speaking',
      ),
      fullscreenDialog: true,
    );
    if (result == null || !result.meetsThreshold) return;
    _complete(task, {
      'durationSeconds': result.durationSeconds,
      'learnerUtteranceCount': result.learnerUtteranceCount,
      'evidenceWithheld': 'engagement_does_not_measure_pronunciation_quality',
    });
  }

  Future<ReadingPassage> _missionScene({
    required MissionDefinition mission,
    required SpeakingTopic topic,
  }) async {
    final session = store.dailySession();
    final cached = session.readingPassageJson;
    if (cached?['missionId'] == mission.id) {
      try {
        return ReadingPassage.fromJson(cached!);
      } catch (_) {}
    }
    // A mission's roleplay prompt (title/scenario/level/promptContext + speaking
    // topic) is the same for every learner who gets this mission, so the generated
    // scene is reusable across learners, not just across a single learner's re-visits.
    // A small rotating pool per mission keeps repeat visits feeling fresh without
    // calling Gemini again on every single mission visit by every learner.
    if (sceneCacheStore.needsNewVariant(mission.id)) {
      await _generateAndStoreVariant(mission: mission, topic: topic);
    }
    final resolved = sceneCacheStore.takeVariant(mission.id);
    if (resolved == null) {
      throw StateError('No roleplay scene available for ${mission.id}');
    }
    session.readingPassageJson = {
      ...resolved.toJson(),
      'missionId': mission.id,
    };
    store.saveDailySession(session);
    return resolved;
  }

  Future<void> _generateAndStoreVariant({
    required MissionDefinition mission,
    required SpeakingTopic topic,
  }) async {
    final scene = await LessonAgentService.shared.buildMissionRoleplay(
      missionTitle: mission.title,
      scenario: mission.scenario,
      levelBand: mission.levelBand,
      missionContext: mission.promptContext,
      speakingPrompt: topic.promptFr,
      hints: topic.hints,
    );
    sceneCacheStore.store(mission.id, scene);
  }

  /// Tops up [mission]'s scene pool in the background — called right after a
  String _sceneContext(ReadingPassage scene) => '''
PERSISTED MISSION ROLEPLAY, stay in this exact scenario and respond to the learner's last line in character:
${scene.segments.map((segment) => 'CHARACTER: ${segment.characterFr}\nLEARNER: ${segment.fr}').join('\n')}''';

  bool _isSupported(PerformanceModality modality) => switch (modality) {
    PerformanceModality.readingRecognition ||
    PerformanceModality.listeningRecognition ||
    PerformanceModality.controlledSpeaking ||
    PerformanceModality.spontaneousSpeaking ||
    PerformanceModality.controlledWriting ||
    PerformanceModality.pronunciationProduction => true,
    PerformanceModality.spontaneousWriting => false,
  };

  TaskEvidenceContext _context(PlanTaskRecord task, TaskResultStatus status) =>
      TaskEvidenceContext(
        sessionId: 'mission_${task.planId}',
        planId: task.planId,
        planTaskId: task.id,
        status: status,
        occurredAt: DateTime.now(),
      );

  void _complete(PlanTaskRecord task, Map<String, Object?> resultSummary) {
    planStore.completeTask(
      taskId: task.id,
      status: PlanTaskStatus.completed,
      resultSummary: resultSummary,
    );
    // The single, generic "seen" record RotationPlanner excludes from its
    // next pick — same table every modality already writes to via its own
    // screen (lesson_progress), just recorded centrally here too so the
    // rotation's exclusion works regardless of which screen a task went
    // through.
    store.setLessonStatus(task.contentItemId, 'completed');
  }

  SpeakingTopic? _missionTopic(MissionDefinition mission) {
    for (final step in mission.steps) {
      final topic = _speakingTopic(step.contentItemId);
      if (topic != null) return topic;
    }
    return null;
  }

  bool _isGrammarStep(PlanTaskRecord task, MissionDefinition mission) {
    final step = mission.steps
        .where(
          (item) =>
              item.contentItemId == task.contentItemId &&
              item.modality == task.modality,
        )
        .firstOrNull;
    return step?.isGrammarPractice == true;
  }

  WritingTask? _writingTask(String id) => ContentService.shared
      .writingTasks()
      ?.tasks
      .where((task) => task.id == id)
      .firstOrNull;

  VocabEntry? _vocabEntry(String id) => ContentService.shared.vocabPhases
      .expand((phase) => phase.themes.expand((theme) => theme.entries))
      .where((entry) => entry.id == id)
      .firstOrNull;

  SpeakingTopic? _speakingTopic(String id) {
    final topics =
        ContentService.shared.resources()?.speakingTopics ?? const [];
    return topics.where((topic) => topic.id == id).firstOrNull;
  }
}
