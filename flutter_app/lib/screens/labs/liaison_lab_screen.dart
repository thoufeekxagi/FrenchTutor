import 'dart:async';

import 'package:intl/intl.dart';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/generated_grammar_story_store.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/profile.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../providers/database_provider.dart';
import '../../services/session_recorder.dart';
import '../lessons/story_reader_screen.dart';

const _liaisonGrammarPoint = 'Liaison';

/// Liaison practice — same "explanation, then a story grounded in it, then a
/// quiz" shape the Grammar lab uses (reusing its exact storage/sync/reader,
/// tagged `grammarPoint: 'Liaison'`), but for the pronunciation rule
/// (a normally-silent final consonant gets pronounced because the next word
/// starts with a vowel sound), not a tense. The level picker here is a
/// SLIDER the learner sets fresh each time, deliberately independent of
/// their profile's level — practicing liaison at a level above or below
/// where they normally sit is a legitimate, deliberate choice, not a
/// permanent calibration change (that's what Settings -> Level is for).
class LiaisonLabScreen extends ConsumerStatefulWidget {
  const LiaisonLabScreen({super.key});

  @override
  ConsumerState<LiaisonLabScreen> createState() => _LiaisonLabScreenState();
}

class _LiaisonLabScreenState extends ConsumerState<LiaisonLabScreen> {
  double _levelIndex = 0;
  bool _isGenerating = false;
  String? _errorText;
  List<GeneratedGrammarStory>? _history;

  @override
  void initState() {
    super.initState();
    _levelIndex = LearnerLevel.cefrValues
        .indexOf(ref.read(learningStoreProvider).profile().level)
        .clamp(0, LearnerLevel.cefrValues.length - 1)
        .toDouble();
    _loadHistory();
  }

  String get _selectedLevel => LearnerLevel.cefrValues[_levelIndex.round()];

  void _loadHistory() {
    final store = ref.read(generatedGrammarStoryStoreProvider);
    setState(
      () => _history = store
          .list()
          .where((s) => s.grammarPoint == _liaisonGrammarPoint)
          .toList(),
    );
  }

  Future<void> _practiceLiaison() async {
    final level = _selectedLevel;
    setState(() {
      _isGenerating = true;
      _errorText = null;
    });
    final recorder = SessionRecorder(
      storage: ref.read(storageServiceProvider),
      stage: 'grammar',
      topic: _liaisonGrammarPoint,
    );
    try {
      final learningStore = ref.read(learningStoreProvider);
      final agent = ref.read(lessonAgentServiceProvider);
      final explanation = await agent.buildLiaisonExplanation(
        levelBand: level,
      );
      final passage = await agent.buildLiaisonStory(
        levelBand: level,
        explanation: explanation,
      );
      final generated = await agent.buildLiaisonQuiz(passage: passage);
      if (!mounted) return;
      setState(() => _isGenerating = false);

      final liaisonStory = GeneratedGrammarStory(
        id: newGeneratedGrammarStoryId(),
        grammarPoint: _liaisonGrammarPoint,
        levelBand: level,
        explanation: explanation,
        passage: passage,
        quiz: generated.quiz,
        keywords: generated.keywords,
        createdAt: DateTime.now(),
      );
      final grammarStore = ref.read(generatedGrammarStoryStoreProvider);
      grammarStore.insert(liaisonStory);
      _loadHistory();

      final story = GeneratedStory(
        id: liaisonStory.id,
        passage: passage,
        quiz: generated.quiz,
        keywords: generated.keywords,
        createdAt: liaisonStory.createdAt,
      );
      final result = await AppRouter.push<StoryReaderResult>(
        context,
        (_) => StoryReaderScreen(
          story: story,
          showFinishButton: true,
          grammarExplanation: explanation,
          grammarTabLabel: 'Liaison',
        ),
        fullscreenDialog: true,
      );
      if (!mounted) return;
      final score = result != null && result.attempted > 0
          ? result.correct / result.attempted
          : null;
      if (score != null) grammarStore.updateScore(liaisonStory.id, score);
      final passed = score != null && score >= 0.8;
      learningStore.setLessonStatus(
        'liaison_practice_$level',
        passed ? 'completed' : 'in_progress',
        score: score,
      );
      // autoNote: false — same reasoning as the Grammar lab: this is a
      // generate-a-story-then-quiz flow, no conversation to summarize.
      recorder.finish(
        summary: score != null
            ? 'Practiced liaison at $level, scored ${(score * 100).round()}% on the quiz.'
            : 'Practiced liaison at $level without finishing the quiz.',
        autoNote: false,
      );
      unawaited(
        _saveLiaisonNote(
          explanation: explanation,
          keywords: generated.keywords,
          score: score,
          sessionId: recorder.sessionId,
        ),
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

  /// Same "recap the content, not a transcript" note as the Grammar lab —
  /// tagged 'Liaison' specifically (not 'Grammar') so it shows as its own
  /// filter in the notes review screen, distinct but built the same way.
  Future<void> _saveLiaisonNote({
    required GrammarExplanation explanation,
    required List<VocabEntry> keywords,
    required double? score,
    required String sessionId,
  }) async {
    try {
      final buf = StringBuffer()
        ..writeln('Tutor: Taught liaison (pronunciation linking).')
        ..writeln('Tutor: ${explanation.summary}')
        ..writeln('Tutor: ${explanation.tenseContrast}')
        ..writeln(
          'Tutor: Then told a short story rich in liaison examples, with key words: '
          '${keywords.map((k) => '${k.fr} (${k.en})').join(', ')}.',
        )
        ..writeln(
          score != null
              ? 'Student: Took the quiz and scored ${(score * 100).round()}%.'
              : 'Student: Read the story but did not finish the quiz.',
        );
      final note = await ref
          .read(lessonAgentServiceProvider)
          .summarizeSessionForNotes(
            transcript: buf.toString(),
            topic: _liaisonGrammarPoint,
          );
      if (note.isEmpty || !mounted) return;
      ref
          .read(storageServiceProvider)
          .saveNote(
            tag: _liaisonGrammarPoint,
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
    final history = _history ?? const [];

    return Scaffold(
      backgroundColor: DesignTokens.parchment,
      appBar: AppBar(
        title: Text('Liaison', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchment,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          const SizedBox(height: 8),
          const KickerText('Practice liaison'),
          const SizedBox(height: 10),
          PasseportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'When a silent consonant links to the next word (like "les_amis"), it changes how a sentence sounds. Generate a story built to practice it, then pass the quiz at 80% or better.',
                  style: DesignTokens.body(
                    13,
                  ).copyWith(color: DesignTokens.slateDim, height: 1.4),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Level',
                      style: DesignTokens.body(13, weight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      LearnerLevel.displayLabel(_selectedLevel),
                      style: DesignTokens.body(
                        13,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.primary),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: DesignTokens.primary,
                    thumbColor: DesignTokens.primary,
                  ),
                  child: Slider(
                    value: _levelIndex,
                    min: 0,
                    max: (LearnerLevel.cefrValues.length - 1).toDouble(),
                    divisions: LearnerLevel.cefrValues.length - 1,
                    label: LearnerLevel.displayLabel(_selectedLevel),
                    onChanged: (v) => setState(() => _levelIndex = v),
                  ),
                ),
                const SizedBox(height: 4),
                PasseportPrimaryButton(
                  label: _isGenerating
                      ? 'Building your story…'
                      : 'Generate practice story',
                  icon: _isGenerating ? null : CupertinoIcons.wand_stars,
                  onPressed: _isGenerating ? null : _practiceLiaison,
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
          const SizedBox(height: 24),
          if (history.isNotEmpty) ...[
            const KickerText('Your liaison practice', color: DesignTokens.slateDim),
            const SizedBox(height: 10),
            for (final entry in history)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _LiaisonHistoryTile(
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
                      grammarTabLabel: 'Liaison',
                    ),
                  ),
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No liaison practice yet, generate one above.',
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

class _LiaisonHistoryTile extends StatelessWidget {
  const _LiaisonHistoryTile({required this.story, required this.onTap});

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
                LearnerLevel.displayLabel(story.levelBand),
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
