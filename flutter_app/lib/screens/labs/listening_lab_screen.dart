import 'dart:async';
import 'dart:math';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../models/profile.dart';
import '../../providers/database_provider.dart';
import '../../data/database/generated_story_store.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_card.dart';
import '../lessons/story_reader_screen.dart';

// Fixed topic categories the learner can tap to steer generation, alongside
// "Surprise me" (fully random) — kept short since these are also chip labels.
// Onboarding interests are folded into the same random pool as these, not
// treated as the default/only choice, so repeated generations don't keep
// landing on the same one or two interests picked at onboarding.
const _storyTopicCategories = [
  'Travel',
  'Food',
  'Music',
  'Technology',
  'Environment',
];

// Fallback for a profile with no onboarding interests picked (skipped the
// question, or a pre-existing profile from before it existed): a small
// rotating pool of broadly appealing topics, one picked at random each time.
const _storyTopics = [
  'a small-town bakery with a surprising new recipe',
  'a weekend trip that goes slightly wrong',
  'a mix-up on the first day of a new job',
  'a new neighbour with an unusual hobby',
  'a lost pet found in an unexpected place',
  'a cooking mistake that turns into something good',
];

/// The learner's personal library of AI-generated stories — the "Read a new
/// story" tile at top always generates a fresh one (Story + Quiz + Keywords +
/// Grammar, all AI-generated together) and opens it immediately; every story
/// generated this way is saved below so it can be reopened later, replacing
/// the old browsable list of hardcoded listening.json exercises.
class ListeningLabScreen extends ConsumerStatefulWidget {
  const ListeningLabScreen({super.key});

  @override
  ConsumerState<ListeningLabScreen> createState() =>
      _ListeningLabScreenState();
}

class _ListeningLabScreenState extends ConsumerState<ListeningLabScreen> {
  bool _generatingStory = false;
  List<GeneratedStory>? _stories;
  // null = "Surprise me" (fully random pick each generation).
  String? _selectedTopic;

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  void _loadStories() {
    final store = ref.read(generatedStoryStoreProvider);
    setState(() => _stories = store.list());
  }

  Future<void> _generateStory() async {
    if (_generatingStory) return;
    setState(() => _generatingStory = true);
    try {
      final profile = ref.read(learningStoreProvider).profile();
      // Only the passage blocks the UI — the story is shown the moment it's
      // ready, not after a second Gemini round-trip for quiz/keywords too.
      // That second call still runs, just in the background; the reader
      // screen fills in the Quiz/Keywords tabs itself once it resolves.
      final passage = await LessonAgentService.shared.buildPersonalStory(
        topic: _topicFor(profile),
        levelBand: profile.level,
      );
      final story = GeneratedStory(
        id: newGeneratedStoryId(),
        passage: passage,
        quiz: const [],
        keywords: const [],
        createdAt: DateTime.now(),
      );
      final store = ref.read(generatedStoryStoreProvider);
      store.insert(story);
      unawaited(_prewarmNarration(story));
      if (!mounted) return;
      _loadStories();
      AppRouter.push(
        context,
        (_) => StoryReaderScreen(
          story: story,
          enrichment: LessonAgentService.shared.buildStoryQuizAndKeywords(passage),
          onEnriched: (quiz, keywords) => store.updateEnrichment(
            GeneratedStory(
              id: story.id,
              passage: passage,
              quiz: quiz,
              keywords: keywords,
              createdAt: story.createdAt,
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate a story. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingStory = false);
    }
  }

  /// Synthesizes and caches this story's narration right after it's
  /// written, so opening it to read plays instantly from the cache instead
  /// of calling the TTS endpoint live sentence-by-sentence (the live path
  /// is exactly what used to run out of rate-limit budget partway through a
  /// fresh story). Fire-and-forget: a partial or total failure here just
  /// means those lines fall back to live synthesis on first play, same as
  /// before this existed.
  Future<void> _prewarmNarration(GeneratedStory story) {
    final segments = story.passage.segments;
    return LessonSpeechService.shared.prewarmNarration([
      for (var i = 0; i < segments.length; i++)
        SpeechItem(
          text: segments[i].fr,
          language: 'fr-FR',
          contentItemId: story.segmentContentId(i),
        ),
    ]);
  }

  /// If the learner tapped a topic chip, use that directly. Otherwise pick
  /// fully at random from a pool that mixes the fixed categories, the
  /// onboarding interests, and the generic fallback topics as equal
  /// citizens — onboarding interests are just part of the pool, never the
  /// deciding factor, so two generations in a row rarely land on the same
  /// thing even for a profile with only one or two interests picked.
  String _topicFor(Profile profile) {
    if (_selectedTopic != null) {
      return 'something related to ${_selectedTopic!.toLowerCase()} that could happen in daily life';
    }
    final pool = [
      ..._storyTopicCategories.map(
        (c) => 'something related to ${c.toLowerCase()} that could happen in daily life',
      ),
      ...profile.interests.map(
        (i) => 'something related to $i that could happen in daily life',
      ),
      ..._storyTopics,
    ];
    return pool[Random().nextInt(pool.length)];
  }

  @override
  Widget build(BuildContext context) {
    final stories = _stories ?? const [];
    final starterStories = ref.watch(contentServiceProvider).starterStories();

    return Scaffold(
      backgroundColor: DesignTokens.parchmentDim,
      appBar: AppBar(
        title: Text('Listening', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          _GenerateStoryTile(
            generating: _generatingStory,
            selectedTopic: _selectedTopic,
            onTap: _generateStory,
          ),
          const SizedBox(height: 10),
          _TopicChipRow(
            selected: _selectedTopic,
            onSelect: (topic) => setState(() => _selectedTopic = topic),
          ),
          const SizedBox(height: 20),
          if (stories.isNotEmpty) ...[
            const KickerText('Your stories', color: DesignTokens.slateDim),
            const SizedBox(height: 10),
            for (final story in stories)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StoryTile(
                  story: story,
                  onTap: () => AppRouter.push(
                    context,
                    (_) => StoryReaderScreen(story: story),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ] else
            _EmptyLibraryNote(),
          if (starterStories.isNotEmpty) ...[
            const SizedBox(height: 8),
            const KickerText('Starter stories', color: DesignTokens.slateDim),
            const SizedBox(height: 10),
            for (final story in starterStories)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _StoryTile(
                  story: story,
                  isStarter: true,
                  onTap: () => AppRouter.push(
                    context,
                    (_) => StoryReaderScreen(story: story),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _GenerateStoryTile extends StatelessWidget {
  const _GenerateStoryTile({
    required this.generating,
    required this.onTap,
    this.selectedTopic,
  });

  final bool generating;
  final VoidCallback onTap;
  final String? selectedTopic;

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: DesignTokens.infoSoft,
            borderRadius: BorderRadius.circular(13),
          ),
          child: generating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.book_fill, color: DesignTokens.info),
        ),
        title: Text(
          'Generate a new story',
          style: DesignTokens.body(15, weight: FontWeight.w600),
        ),
        subtitle: Text(
          generating
              ? 'Writing your story…'
              : selectedTopic != null
              ? 'A fresh bilingual story with a $selectedTopic twist'
              : 'A fresh bilingual story, generated for you',
          style: DesignTokens.body(12.5).copyWith(color: DesignTokens.slateDim),
        ),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
        onTap: generating ? null : onTap,
      ),
    );
  }
}

/// "Surprise me" (random pick, the default) plus the fixed topic categories —
/// tapping one steers the next generation toward it without making every
/// sentence literally about that word; tapping it again (or "Surprise me")
/// clears the pick back to fully random.
class _TopicChipRow extends StatelessWidget {
  const _TopicChipRow({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <String?>[null, ..._storyTopicCategories];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option == selected;
          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : option),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? DesignTokens.primary : DesignTokens.canvasDim,
                borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              ),
              alignment: Alignment.center,
              child: Text(
                option ?? 'Surprise me',
                style: DesignTokens.body(12.5, weight: FontWeight.w600).copyWith(
                  color: isSelected ? Colors.white : DesignTokens.slateDim,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.story,
    required this.onTap,
    this.isStarter = false,
  });

  final GeneratedStory story;
  final VoidCallback onTap;
  final bool isStarter;

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
                isStarter
                    ? 'Ready to read'
                    : DateFormat('MMM d, HH:mm').format(story.createdAt),
                style: DesignTokens.mono(
                  10.5,
                ).copyWith(color: DesignTokens.slateDim),
              ),
              if (story.quiz.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${story.quiz.length} questions',
                  style: DesignTokens.mono(
                    10.5,
                  ).copyWith(color: DesignTokens.slateDim),
                ),
              ],
              if (story.keywords.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${story.keywords.length} keywords',
                  style: DesignTokens.mono(
                    10.5,
                  ).copyWith(color: DesignTokens.slateDim),
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

class _EmptyLibraryNote extends StatelessWidget {
  const _EmptyLibraryNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.book,
            color: DesignTokens.slateDim,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'No stories of your own yet, generate one above, or try a starter story below',
            textAlign: TextAlign.center,
            style: DesignTokens.body(13).copyWith(color: DesignTokens.slateDim),
          ),
        ],
      ),
    );
  }
}
