import 'package:flutter/widgets.dart';

import '../config/api_keys.dart';
import '../data/content_service.dart';
import '../data/database/evidence_store.dart';
import '../data/database/plan_store.dart';
import '../data/database/learning_store.dart';
import '../design/app_router.dart';
import '../models/content_models.dart';
import '../orchestration/evidence/task_result_adapters.dart';
import '../orchestration/models/competency.dart';
import '../orchestration/models/mission.dart';
import '../orchestration/models/plan_task.dart';
import '../orchestration/models/task_result.dart';
import '../screens/lessons/listening_exercise_screen.dart';
import '../services/lesson_agent_service.dart';
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
  });

  final LearningStore store;
  final PlanStore planStore;
  final EvidenceStore evidenceStore;
  final TaskResultAdapters taskResultAdapters;

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
        if (_hasGrammarItem(task.contentItemId)) {
          await _runGrammar(context: context, task: task);
        } else {
          await _runSpeaking(context: context, task: task, mission: mission);
        }
      case PerformanceModality.spontaneousSpeaking:
        await _runSpeaking(context: context, task: task, mission: mission);
      case PerformanceModality.controlledWriting:
        await _runWriting(context: context, task: task);
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
    final outcome = await AppRouter.push<StageOutcome<VocabStageResult>>(
      context,
      (_) => VocabPickerScreen(preferredEntryIds: [task.contentItemId]),
      fullscreenDialog: true,
    );
    if (outcome == null || !outcome.isCompleted) return;
    final result = outcome.result;
    if (result == null) return;
    final supportedIds = result.wordsCovered
        .map((word) => word.id)
        .where(
          (id) => taskResultAdapters.supports(
            id,
            PerformanceModality.readingRecognition,
          ),
        )
        .toList(growable: false);
    evidenceStore.insertTaskResult(
      taskResultAdapters.vocabulary(
        context: _context(task, TaskResultStatus.completed),
        reviewedContentItemIds: supportedIds,
      ),
    );
    _complete(task, {'reviewedCount': result.reviewedCount});
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
    final exercise = _listeningExercise(task.contentItemId);
    if (exercise == null) {
      throw StateError('Missing listening content ${task.contentItemId}');
    }
    final result = await AppRouter.push<ListeningExerciseResult>(
      context,
      (_) => ListeningExerciseScreen(exercise: exercise),
      fullscreenDialog: true,
    );
    if (result == null) return;
    evidenceStore.insertTaskResult(
      taskResultAdapters.listening(
        context: _context(task, TaskResultStatus.completed),
        contentItemId: task.contentItemId,
        correct: result.correct,
        attempted: result.attempted,
        objectivelyGraded: true,
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
  }) async {
    final writingTask = _writingTask(task.contentItemId);
    if (writingTask == null) {
      throw StateError('Missing writing content ${task.contentItemId}');
    }
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
    final scene = await LessonAgentService.shared.buildMissionRoleplay(
      missionTitle: mission.title,
      scenario: mission.scenario,
      levelBand: mission.levelBand,
      missionContext: mission.promptContext,
      speakingPrompt: topic.promptFr,
      hints: topic.hints,
    );
    session.readingPassageJson = {...scene.toJson(), 'missionId': mission.id};
    store.saveDailySession(session);
    return scene;
  }

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
  }

  SpeakingTopic? _missionTopic(MissionDefinition mission) {
    for (final step in mission.steps) {
      final topic = _speakingTopic(step.contentItemId);
      if (topic != null) return topic;
    }
    return null;
  }

  bool _hasGrammarItem(String id) {
    final grammar = ContentService.shared.grammar();
    return grammar?.lessons.any((item) => item.id == id) == true ||
        grammar?.topics.any((item) => item.id == id) == true;
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

  ListeningExercise? _listeningExercise(String id) {
    final exercises = ContentService.shared.listening()?.exercises ?? const [];
    return exercises.where((exercise) => exercise.id == id).firstOrNull;
  }

  SpeakingTopic? _speakingTopic(String id) {
    final topics =
        ContentService.shared.resources()?.speakingTopics ?? const [];
    return topics.where((topic) => topic.id == id).firstOrNull;
  }
}
