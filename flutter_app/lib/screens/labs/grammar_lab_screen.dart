import 'dart:async';

import '../../design/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/generated_grammar_story_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../widgets/personalized_generation_loader.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/practice_artwork_service.dart';
import '../../services/session_recorder.dart';
import '../lessons/grammar_workshop_screen.dart';
import '../grammar/grammar_curriculum_home_screen.dart';

/// The Grammar lab — fully replaced the old static Lessons/Topics browsing
/// list with the same "generate, save, review later" pattern the Story and
/// Listening labs already use: "Practice a tense" generates a level-
/// calibrated story built around the chosen tense, saved to a personal
/// library the moment it's ready (never lost when the screen closes), with
/// a quiz gated at 80% to mark that tense complete for the day's mission.
class GrammarLabScreen extends ConsumerStatefulWidget {
  const GrammarLabScreen({super.key, this.topic, this.autoStart = false});

  final String? topic;
  final bool autoStart;

  @override
  ConsumerState<GrammarLabScreen> createState() => _GrammarLabScreenState();
}

class _GrammarLabScreenState extends ConsumerState<GrammarLabScreen> {
  String? _selectedTense;
  bool _isGenerating = false;
  String? _errorText;
  List<GeneratedGrammarStory>? _history;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    unawaited(_refreshHistory());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_practiceTense());
      });
    }
  }

  /// All tenses, always — a learner can deliberately choose to get ahead of
  /// their level. What stays bounded to their level is the story's own
  /// sentence/vocabulary simplicity, not which tenses are offered (see the
  /// "TENSE OVERRIDE" note in `LessonAgentService.buildGrammarStory`).
  List<String> get _availableTenses => LessonAgentService.grammarPracticePoints;

  void _loadHistory() {
    if (!mounted) return;
    final store = ref.read(generatedGrammarStoryStoreProvider);
    setState(() => _history = store.list());
  }

  Future<void> _refreshHistory() async {
    try {
      await ref.read(syncServiceProvider).hydrateGeneratedGrammarStories();
    } catch (error, stackTrace) {
      debugPrint('Grammar story hydration failed: $error\n$stackTrace');
    }
    if (mounted) _loadHistory();
  }

  /// Story leads: generates a story built around [_selectedTense] first,
  /// then builds the grammar explanation FROM that specific story (its own
  /// verbs, its own sentences) rather than a generic textbook explanation
  /// unrelated to what the student just read. The reader opens on the Story
  /// tab with a cue card pointing at Grammar, not the other way around.
  /// Saves to the grammar library the moment both are generated (so it has
  /// real history, even if the learner never finishes the quiz), logs a
  /// 'grammar' stage session so it counts toward the day's mission, then
  /// gates completion at 80% — the same threshold the old static drills used.
  Future<void> _practiceTense() async {
    final available = _availableTenses;
    final tense = (_selectedTense != null && available.contains(_selectedTense))
        ? _selectedTense!
        : available.first;
    setState(() {
      _isGenerating = true;
      _errorText = null;
    });
    final recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'grammar',
      topic: tense,
    );
    try {
      final learningStore = ref.read(learningStoreProvider);
      final agent = ref.read(lessonAgentServiceProvider);
      final level = learningStore.profile().level;
      // Story first, then the explanation is built FROM it — grounds the
      // grammar teaching in the story's own verbs/sentences instead of
      // generic textbook examples (see buildGrammarExplanationFromStory).
      final passage = await agent.buildGrammarStory(
        grammarPoint: tense,
        levelBand: level,
        contextTopic: widget.topic,
      );
      // Start the dependent lesson assets together as soon as the story exists.
      // The explanation and quiz both use the same frozen passage, while the
      // cover only needs the passage title. This removes the old waterfall
      // where each asset made the learner wait for the previous one.
      final explanationFuture = agent.buildGrammarExplanationFromStory(
        grammarPoint: tense,
        levelBand: level,
        passage: passage,
      );
      final quizFuture = agent.buildGrammarQuiz(
        passage: passage,
        grammarPoint: tense,
        levelBand: level,
      );
      final storyId = newGeneratedGrammarStoryId();
      final coverFuture = PracticeArtworkService.generateAndUpload(
        sync: ref.read(syncServiceProvider),
        id: storyId,
        title: passage.displayTitle,
        summary: 'A short French grammar story about $tense.',
        topic: 'French grammar: $tense',
        levelBand: level,
        coverPrompt:
            'A grounded realistic 4:3 image for a short French grammar story about ${passage.displayTitle}. Show the setting, objects, and action as the primary subject; no people, faces, animals, or characters. Render no text, letters, numbers, logos, signs, captions, labels, or typography.',
      );
      final explanation = await explanationFuture;
      final generated = await quizFuture;
      if (!mounted) return;

      final grammarStory = GeneratedGrammarStory(
        id: storyId,
        grammarPoint: tense,
        levelBand: level,
        explanation: explanation,
        passage: passage,
        quiz: generated.quiz,
        keywords: generated.keywords,
        createdAt: DateTime.now(),
      );

      // Warm all sentence audio while the cover is being uploaded. Opening the
      // workshop should normally be an instant read from the shared cache.
      unawaited(
        LessonSpeechService.shared.prewarmNarration([
          for (
            var index = 0;
            index < grammarStory.passage.segments.length;
            index++
          )
            SpeechItem(
              text: grammarStory.passage.segments[index].fr,
              language: 'fr-FR',
              contentItemId: grammarStory.segmentContentId(index),
            ),
        ]),
      );

      // Saved immediately — a session the learner never finishes the quiz
      // for still has to exist afterward, same as the Story library.
      final grammarStore = ref.read(generatedGrammarStoryStoreProvider);
      grammarStore.insert(grammarStory);
      unawaited(_saveGrammarCover(grammarStory, coverFuture));
      // Start warming the sentence clips before the learner reaches the
      // notice step. The workshop still shows a spinner on a cache miss, but
      // normal opens now play immediately from the persistent TTS cache.
      _loadHistory();
      setState(() => _isGenerating = false);

      final result = await AppRouter.push<GrammarWorkshopResult>(
        context,
        (_) =>
            GrammarWorkshopScreen(story: grammarStory, showFinishButton: true),
        fullscreenDialog: true,
      );
      if (!mounted) return;
      final score = result != null && result.attempted > 0
          ? result.correct / result.attempted
          : null;
      if (score != null) grammarStore.updateScore(grammarStory.id, score);
      final passed = score != null && score >= 0.8;
      final lessonId =
          'grammar_story_${tense.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
      learningStore.setLessonStatus(
        lessonId,
        passed ? 'completed' : 'in_progress',
        score: score,
      );
      // autoNote: false — there's no live conversation here to summarize
      // (this flow is generate-a-story-then-quiz, not a back-and-forth), so
      // SessionRecorder's usual "summarize the transcript" path would just
      // bail with nothing to say. The note comes from the session's actual
      // content instead — see below.
      recorder.finish(
        summary: score != null
            ? 'Practiced $tense, scored ${(score * 100).round()}% on the quiz.'
            : 'Practiced $tense without finishing the quiz.',
        autoNote: false,
      );
      unawaited(
        _saveGrammarNote(
          tense: tense,
          explanation: explanation,
          keywords: generated.keywords,
          score: score,
          sessionId: recorder.sessionId,
        ),
      );
      if (mounted) {
        setState(() {});
        if (widget.autoStart) Navigator.of(context).pop(result != null);
      }
    } catch (e) {
      if (!mounted) return;
      if (widget.autoStart) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _isGenerating = false;
        _errorText = "Couldn't generate that practice, try again.";
      });
    }
  }

  Future<void> _saveGrammarCover(
    GeneratedGrammarStory story,
    Future<String?> coverFuture,
  ) async {
    final store = ref.read(generatedGrammarStoryStoreProvider);
    try {
      final url = await coverFuture;
      if (url == null) return;
      store.updateCoverUrl(story.id, url);
      if (mounted) _loadHistory();
    } catch (error, stackTrace) {
      debugPrint('Grammar cover generation failed: $error\n$stackTrace');
    }
  }

  /// Builds the same kind of short AI recap every conversational session
  /// gets, but from this session's actual CONTENT (what was taught, what
  /// the story used, the quiz score) rather than a transcript — there's no
  /// back-and-forth to summarize here, so `summarizeSessionForNotes` is fed
  /// a synthetic description instead. Best-effort, never throws.
  Future<void> _saveGrammarNote({
    required String tense,
    required GrammarExplanation explanation,
    required List<VocabEntry> keywords,
    required double? score,
    required String sessionId,
  }) async {
    try {
      final buf = StringBuffer()
        ..writeln('Tutor: Taught the grammar point "$tense".')
        ..writeln('Tutor: ${explanation.summary}')
        ..writeln('Tutor: ${explanation.tenseContrast}')
        ..writeln(
          'Tutor: Then told a short story using $tense, with key words: '
          '${keywords.map((k) => '${k.fr} (${k.en})').join(', ')}.',
        )
        ..writeln(
          score != null
              ? 'Student: Took the quiz and scored ${(score * 100).round()}%.'
              : 'Student: Read the story but did not finish the quiz.',
        );
      final note = await ref
          .read(lessonAgentServiceProvider)
          .summarizeSessionForNotes(transcript: buf.toString(), topic: tense);
      if (note.isEmpty || !mounted) return;
      ref
          .read(storageServiceProvider)
          .saveNote(
            tag: SessionRecorder.tagForStage('grammar'),
            text: note,
            source: 'ai',
            sessionId: sessionId,
          );
    } catch (_) {
      // Ambient recap, not the graded path — a failure here is silent.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return Scaffold(
        backgroundColor: DesignTokens.canvasDim,
        appBar: AppBar(
          title: Text('Grammar', style: DesignTokens.display(20)),
          backgroundColor: DesignTokens.canvasDim,
          elevation: 0,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: PersonalizedGenerationLoader(
              content: 'grammar class',
              detail: 'Matching the lesson to your level and learning goals.',
            ),
          ),
        ),
      );
    }
    final history = _history ?? const [];
    return GrammarCurriculumHomeScreen(
      generatedHistory: history,
      isGenerating: _isGenerating,
      generationError: _errorText,
      onGenerateAdvanced: (lesson) async {
        setState(() => _selectedTense = lesson.generationPoint);
        await _practiceTense();
      },
      onOpenGenerated: (story) {
        AppRouter.push(context, (_) => GrammarWorkshopScreen(story: story));
      },
    );
  }
}
