import 'package:intl/intl.dart';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/generated_grammar_story_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/session_recorder.dart';
import '../lessons/story_reader_screen.dart';

/// The Grammar lab — fully replaced the old static Lessons/Topics browsing
/// list with the same "generate, save, review later" pattern the Story and
/// Listening labs already use: "Practice a tense" generates a level-
/// calibrated story built around the chosen tense, saved to a personal
/// library the moment it's ready (never lost when the screen closes), with
/// a quiz gated at 80% to mark that tense complete for the day's mission.
class GrammarLabScreen extends ConsumerStatefulWidget {
  const GrammarLabScreen({super.key});

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
  }

  /// Only tenses the learner's current level is actually ready for — see
  /// `LessonAgentService.grammarPracticePointMinLevel` for why this bound
  /// exists (picking a tense above your level used to send the model two
  /// contradicting instructions in the same prompt).
  List<String> get _availableTenses => LessonAgentService.grammarPracticePointsFor(
    ref.watch(learningStoreProvider).profile().level,
  );

  void _loadHistory() {
    final store = ref.read(generatedGrammarStoryStoreProvider);
    setState(() => _history = store.list());
  }

  /// Grammar-first, not story-first: generates the teaching explanation for
  /// [_selectedTense] FIRST (what it is, how it's formed, how it changes
  /// relative to other tenses), then a story grounded in that same
  /// explanation as the vehicle that demonstrates it — reversed from the
  /// earlier "story generator" version, which taught by story alone. Saves
  /// to the grammar library the moment both are generated (so it has real
  /// history, even if the learner never finishes the quiz), logs a
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
      final explanation = await agent.buildGrammarExplanation(
        grammarPoint: tense,
        levelBand: level,
      );
      final passage = await agent.buildGrammarStory(
        grammarPoint: tense,
        levelBand: level,
        explanation: explanation,
      );
      final generated = await agent.buildGrammarQuiz(
        passage: passage,
        grammarPoint: tense,
      );
      if (!mounted) return;
      setState(() => _isGenerating = false);

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
      // Saved immediately — a session the learner never finishes the quiz
      // for still has to exist afterward, same as the Story library.
      final grammarStore = ref.read(generatedGrammarStoryStoreProvider);
      grammarStore.insert(grammarStory);
      _loadHistory();

      final story = GeneratedStory(
        id: grammarStory.id,
        passage: passage,
        quiz: generated.quiz,
        keywords: generated.keywords,
        createdAt: grammarStory.createdAt,
      );
      final result = await AppRouter.push<StoryReaderResult>(
        context,
        (_) => StoryReaderScreen(
          story: story,
          showFinishButton: true,
          grammarExplanation: explanation,
        ),
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
      recorder.finish(
        summary: score != null
            ? 'Practiced $tense, scored ${(score * 100).round()}% on the quiz.'
            : 'Practiced $tense without finishing the quiz.',
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorText = "Couldn't generate that practice, try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: DesignTokens.parchment,
      appBar: AppBar(
        title: Text('Grammar', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchment,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // --- Practice a tense (story-generator rebuild) ---
          const SizedBox(height: 8),
          const KickerText('Practice a tense'),
          const SizedBox(height: 10),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Learn it the way you learn a story — generate one built around the tense you pick, then pass the quiz at 80% or better.',
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.slateDim, height: 1.4),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tense in availableTenses)
                      _TenseChip(
                        label: tense,
                        selected: tense == effectiveTense,
                        status:
                            progress['grammar_story_${tense.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}']
                                ?.status ??
                            'not_started',
                        onTap: () => setState(() => _selectedTense = tense),
                      ),
                  ],
                ),
                if (availableTenses.length <
                    LessonAgentService.grammarPracticePoints.length) ...[
                  const SizedBox(height: 8),
                  Text(
                    'More tenses unlock as your level goes up.',
                    style: DesignTokens.mono(
                      10.5,
                    ).copyWith(color: DesignTokens.slateDim),
                  ),
                ],
                const SizedBox(height: 14),
                PasseportPrimaryButton(
                  label: _isGenerating
                      ? 'Building your story…'
                      : 'Generate practice story',
                  icon: _isGenerating ? null : CupertinoIcons.wand_stars,
                  onPressed: _isGenerating ? null : _practiceTense,
                ),
                if (_errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorText!,
                    style: DesignTokens.mono(
                      11,
                    ).copyWith(color: DesignTokens.primary),
                  ),
                ],
              ],
            ),
          ),
          // --- History ---
          const SizedBox(height: 24),
          if (history.isNotEmpty) ...[
            const KickerText('Your grammar practice', color: DesignTokens.slateDim),
            const SizedBox(height: 10),
            for (final entry in history)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GrammarHistoryTile(
                  story: entry,
                  onTap: () => AppRouter.push(
                    context,
                    (_) => StoryReaderScreen(
                      story: GeneratedStory(
                        id: entry.id,
                        passage: entry.passage,
                        quiz: entry.quiz,
                        keywords: entry.keywords,
                        createdAt: entry.createdAt,
                      ),
                      grammarExplanation: entry.explanation,
                    ),
                  ),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No grammar practice yet, generate one above.',
                textAlign: TextAlign.center,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ),
          const SizedBox(height: 32),
        ],
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
    return PasseportCard(
      padding: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          story.displayTitle,
          style: DesignTokens.body(15, weight: FontWeight.w500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                story.grammarPoint,
                style: DesignTokens.mono(
                  10.5,
                  weight: FontWeight.w500,
                ).copyWith(color: DesignTokens.info),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('MMM d, HH:mm').format(story.createdAt),
                style: DesignTokens.mono(
                  10.5,
                ).copyWith(color: DesignTokens.slateDim),
              ),
              if (story.score != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${(story.score! * 100).round()}%',
                  style: DesignTokens.mono(10.5, weight: FontWeight.w500)
                      .copyWith(
                        color: story.score! >= 0.8
                            ? DesignTokens.success
                            : DesignTokens.primary,
                      ),
                ),
              ],
            ],
          ),
        ),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _TenseChip extends StatelessWidget {
  const _TenseChip({
    required this.label,
    required this.selected,
    required this.status,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? DesignTokens.primary
              : DesignTokens.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: DesignTokens.body(12.5, weight: FontWeight.w600).copyWith(
                color: selected ? Colors.white : DesignTokens.primary,
              ),
            ),
            if (status == 'completed') ...[
              const SizedBox(width: 5),
              Icon(
                CupertinoIcons.checkmark_circle_fill,
                size: 13,
                color: selected ? Colors.white : DesignTokens.success,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
