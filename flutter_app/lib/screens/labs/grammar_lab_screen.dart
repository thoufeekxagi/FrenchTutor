import 'dart:async';
import 'dart:typed_data';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/generated_grammar_story_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/responsive_card_grid.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/session_recorder.dart';
import '../lessons/grammar_workshop_screen.dart';

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
      );
      final coverFuture = agent.generateStoryCover(
        title: passage.displayTitle,
        summary: 'A short French grammar story about $tense.',
        topic: 'French grammar: $tense',
        levelBand: level,
        coverPrompt:
            'A warm editorial portrait illustration for a short French grammar story about ${passage.displayTitle}. Show the story world and one clear everyday moment. No text, letters, logos, borders, watermarks, or UI.',
      );
      final explanation = await explanationFuture;
      final generated = await quizFuture;
      if (!mounted) return;

      final grammarStory = GeneratedGrammarStory(
        id: newGeneratedGrammarStoryId(),
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
    Future<Uint8List> coverFuture,
  ) async {
    final sync = ref.read(syncServiceProvider);
    final store = ref.read(generatedGrammarStoryStoreProvider);
    try {
      final bytes = await coverFuture;
      final url = await sync.uploadStoryCover(storyId: story.id, bytes: bytes);
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
            padding: EdgeInsets.all(28),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    final store = ref.watch(learningStoreProvider);
    final progress = store.allLessonProgress();
    final history = _history ?? const [];
    final availableTenses = _availableTenses;
    // Falls back to the first available tense both when nothing's been
    // picked yet AND when a previously-picked tense fell out of bounds
    // (e.g. the profile's level changed while this screen was open).
    final effectiveTense =
        (_selectedTense != null && availableTenses.contains(_selectedTense))
        ? _selectedTense!
        : availableTenses.first;

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Grammar', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // --- Choose a pattern, then let the AI build the lesson ---
            const SizedBox(height: 8),
            const KickerText('Choose a sentence pattern'),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: availableTenses.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                mainAxisExtent: 52,
              ),
              itemBuilder: (context, index) {
                final tense = availableTenses[index];
                return _GrammarPatternChip(
                  tense: tense,
                  selected: tense == effectiveTense,
                  status:
                      progress['grammar_story_${tense.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}']
                          ?.status ??
                      'not_started',
                  onTap: () => setState(() => _selectedTense = tense),
                );
              },
            ),
            const SizedBox(height: 14),
            PrimaryActionButton(
              label: _isGenerating
                  ? 'Generating practice…'
                  : 'Generate practice story',
              icon: CupertinoIcons.wand_stars,
              isLoading: _isGenerating,
              onPressed: _isGenerating ? null : _practiceTense,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: DesignTokens.mono(
                  11,
                ).copyWith(color: DesignTokens.primary),
              ),
            ],
            // --- History ---
            const SizedBox(height: 24),
            if (history.isNotEmpty) ...[
              const KickerText(
                'Your grammar stories',
                color: DesignTokens.mutedDim,
              ),
              const SizedBox(height: 10),
              ResponsiveCardGrid(
                mainAxisExtent: 270,
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final entry = history[index];
                  return _GrammarHistoryTile(
                    story: entry,
                    onTap: () => AppRouter.push(
                      context,
                      (_) => GrammarWorkshopScreen(story: entry),
                    ),
                  );
                },
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No grammar practice yet, generate one above.',
                  textAlign: TextAlign.center,
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.mutedDim),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _GrammarPatternChip extends StatelessWidget {
  const _GrammarPatternChip({
    required this.tense,
    required this.selected,
    required this.status,
    required this.onTap,
  });

  final String tense;
  final bool selected;
  final String status;
  final VoidCallback onTap;

  String get _label => switch (tense) {
    'Présent' => 'Present',
    'Passé composé' => 'Past',
    'Futur proche' => 'Future',
    'Imparfait' => 'Imperfect',
    'Conditionnel présent' => 'Conditional',
    'Impératif' => 'Imperative',
    _ => tense,
  };

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);
    final iconColor = status == 'completed'
        ? (selected ? Colors.white : DesignTokens.success)
        : (selected ? Colors.white : DesignTokens.primary);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? DesignTokens.primary : DesignTokens.surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: selected ? DesignTokens.primary : DesignTokens.hairline,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(12.5, weight: FontWeight.w700)
                        .copyWith(
                          color: selected ? Colors.white : DesignTokens.ink,
                        ),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  status == 'completed'
                      ? CupertinoIcons.checkmark_circle_fill
                      : selected
                      ? CupertinoIcons.checkmark_alt
                      : CupertinoIcons.arrow_up_right,
                  size: 15,
                  color: iconColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GrammarHistoryTile extends StatelessWidget {
  const _GrammarHistoryTile({required this.story, required this.onTap});

  final GeneratedGrammarStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      padding: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DesignTokens.radiusCard),
              ),
              child: _GrammarStoryCover(
                story: story,
                width: double.infinity,
                height: 164,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI grammar story',
                    style: DesignTokens.mono(
                      10,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    story.displayTitle,
                    style: DesignTokens.body(16, weight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${story.grammarPoint}  •  ${story.levelBand}',
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GrammarStoryCover extends StatelessWidget {
  const _GrammarStoryCover({
    required this.story,
    required this.width,
    required this.height,
  });

  final GeneratedGrammarStory story;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = story.coverUrl;
    if (url != null && url.startsWith('asset:')) {
      return Image.asset(
        url.substring('asset:'.length),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: url == null || url.isEmpty
          ? _fallback()
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            ),
    );
  }

  Widget _fallback() {
    return Container(
      decoration: const BoxDecoration(gradient: DesignTokens.heroGradient),
      child: const Center(
        child: Icon(CupertinoIcons.wand_stars, color: Colors.white, size: 28),
      ),
    );
  }
}
