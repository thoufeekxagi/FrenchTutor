import 'dart:async';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../data/database/generated_story_store.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/personalized_generation_loader.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/responsive_card_grid.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../exam/exam_practice_screen.dart';
import '../lessons/listening_practice_screen.dart';
import '../lessons/story_reader_screen.dart';

// Fixed topic categories the learner can tap to steer generation, alongside
// "Surprise me" (no topic supplied) — kept short since these are also chip
// labels. Surprise mode does not inject onboarding interests.
const _storyTopicCategories = [
  'Travel',
  'Food',
  'Music',
  'Technology',
  'Environment',
];

/// The learner's personal library of AI-generated stories — the "Read a new
/// story" tile at top always generates a fresh one (Story + Quiz + Keywords +
/// Grammar, all AI-generated together) and opens it immediately; every story
/// generated this way is saved below so it can be reopened later, replacing
/// the old browsable list of hardcoded listening.json exercises.
class ListeningLabScreen extends ConsumerStatefulWidget {
  const ListeningLabScreen({
    super.key,
    this.topic,
    this.readingMode = false,
    this.autoStart = false,
    this.examName,
    this.examLevel,
    this.examMode = false,
  });

  final String? topic;
  final bool readingMode;
  final bool autoStart;
  final String? examName;
  final String? examLevel;
  final bool examMode;

  @override
  ConsumerState<ListeningLabScreen> createState() => _ListeningLabScreenState();
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
    unawaited(_refreshStories());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_generateStory());
      });
    }
  }

  void _loadStories() {
    if (!mounted) return;
    if (widget.examMode) return;
    final store = ref.read(generatedStoryStoreProvider);
    setState(
      () => _stories = store.list(
        practiceMode: widget.readingMode ? 'reading' : 'listening',
      ),
    );
  }

  Future<void> _refreshStories() async {
    if (widget.examMode) return;
    try {
      await ref.read(syncServiceProvider).hydrateGeneratedStories();
    } catch (error, stackTrace) {
      debugPrint('Listening story hydration failed: $error\n$stackTrace');
    }
    if (mounted) _loadStories();
  }

  Future<void> _generateStory() async {
    if (_generatingStory) return;
    setState(() => _generatingStory = true);
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final levelBand = _cefrLevelFor(profile.level).toUpperCase();
      final existingStories = ref.read(generatedStoryStoreProvider).list();
      final package = await LessonAgentService.shared.buildListeningStoryBook(
        topic: _topicFor(),
        levelBand: widget.examLevel ?? levelBand,
        examName: widget.examMode ? widget.examName : null,
        examLevel: widget.examMode ? widget.examLevel : null,
        avoidTitles: existingStories.map((story) => story.title),
        avoidOpenings: existingStories.map(
          (story) => story.passage.segments.isEmpty
              ? ''
              : story.passage.segments.first.fr,
        ),
      );
      final story = GeneratedStory(
        id: newGeneratedStoryId(),
        passage: package.passage,
        quiz: package.quiz,
        keywords: package.keywords,
        createdAt: DateTime.now(),
        levelBand: package.levelBand,
        summary: package.summary,
        topic: package.topic,
        readTimeMinutes: package.readTimeMinutes,
        practiceMode: 'listening',
      );
      final examAttempt = widget.examMode
          ? ref
                .read(examPracticeStoreProvider)
                .startStory(
                  examName: widget.examName ?? 'Exam practice',
                  levelBand: widget.examLevel ?? story.levelBand,
                  skill: 'listening',
                  story: story,
                )
          : null;
      final store = ref.read(generatedStoryStoreProvider);
      if (!widget.examMode) {
        store.insert(story);
        unawaited(_prewarmNarration(story));
      }
      if (!mounted) return;
      if (!widget.examMode) _loadStories();
      // Start artwork before entering the lesson. The open lesson watches
      // the shared story store and replaces its placeholder live.
      if (!widget.examMode) {
        unawaited(_generateCover(story, package.coverPrompt));
      }
      final result = await AppRouter.push<Object?>(
        context,
        (_) => _lessonScreen(story),
        fullscreenDialog: widget.autoStart,
      );
      if (widget.examMode &&
          result is ExamPracticeResult &&
          examAttempt != null) {
        ref
            .read(examPracticeStoreProvider)
            .complete(
              id: examAttempt.id,
              score: result.correct,
              total: result.total,
            );
      }
      if (widget.autoStart && mounted) {
        Navigator.of(context).pop(result ?? false);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'ListeningLabScreen: story generation failed: $error\n$stackTrace',
      );
      if (mounted) {
        if (widget.autoStart) {
          Navigator.of(context).pop(false);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Story generation failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingStory = false);
    }
  }

  /// Synthesizes and caches this story's narration right after it's
  /// written, so opening it to read plays instantly from the cache instead
  /// of opening a Live socket sentence-by-sentence (the on-demand path
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
      for (var i = 0; i < story.keywords.length; i++)
        SpeechItem(
          text: story.keywords[i].fr,
          language: 'fr-FR',
          contentItemId: '${story.id}_kw_${story.keywords[i].id}',
        ),
    ]);
  }

  Future<void> _generateCover(GeneratedStory story, String? coverPrompt) async {
    final sync = ref.read(syncServiceProvider);
    final store = ref.read(generatedStoryStoreProvider);
    try {
      final bytes = await LessonAgentService.shared.generateStoryCover(
        title: story.title,
        summary: story.summary,
        topic: story.topic,
        levelBand: story.levelBand,
        coverPrompt: coverPrompt,
      );
      final url = await sync.uploadStoryCover(storyId: story.id, bytes: bytes);
      if (url == null) return;
      store.updateCoverUrl(story.id, url);
      if (mounted) _loadStories();
    } catch (error, stackTrace) {
      debugPrint(
        'ListeningLabScreen: cover generation failed: $error\n$stackTrace',
      );
    }
  }

  /// If the learner tapped a topic chip, use that directly. Otherwise return
  /// null so the model can choose a natural premise at the learner's level.
  String? _topicFor() {
    if (widget.topic != null && widget.topic!.trim().isNotEmpty) {
      return 'a short everyday story connected to ${widget.topic}';
    }
    if (_selectedTopic != null) {
      return 'something related to ${_selectedTopic!.toLowerCase()} that could happen in daily life';
    }
    // Null is intentional: Surprise me must not inherit onboarding interests
    // or a fixed fallback topic. The model chooses a new premise instead.
    return null;
  }

  String _cefrLevelFor(String level) {
    final normalized = level.toLowerCase();
    return const {'a1', 'a2', 'b1', 'b2'}.contains(normalized)
        ? normalized
        : 'a2';
  }

  Widget _lessonScreen(GeneratedStory story) {
    if (widget.examMode) {
      return ExamPracticeScreen(
        story: story,
        examName: widget.examName ?? 'Exam practice',
        levelBand: widget.examLevel ?? story.levelBand,
        skill: 'listening',
      );
    }
    return widget.readingMode
        ? StoryReaderScreen(story: story, showFinishButton: widget.autoStart)
        : ListeningPracticeScreen(
            story: story,
            showFinishButton: widget.autoStart,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return _DirectCourseLoading(
        title: widget.readingMode ? 'Reading' : 'Listening',
        message: widget.readingMode
            ? 'Building your course story…'
            : 'Building your course listening…',
      );
    }
    final stories = _stories ?? const [];
    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        title: Text(
          widget.readingMode ? 'Reading' : 'Listening',
          style: DesignTokens.display(20),
        ),
        backgroundColor: DesignTokens.canvasDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          children: [
            if (_generatingStory)
              PersonalizedGenerationLoader(
                content: widget.readingMode
                    ? 'reading story'
                    : 'listening lesson',
                detail: widget.readingMode
                    ? 'Shaping a short story around your level and interests.'
                    : 'Preparing bilingual audio practice for your current level.',
                icon: CupertinoIcons.book_fill,
              )
            else
              _GenerateStoryTile(
                generating: false,
                selectedTopic: _selectedTopic,
                listening: !widget.readingMode,
                onTap: _generateStory,
              ),
            const SizedBox(height: 10),
            _TopicChipRow(
              selected: _selectedTopic,
              onSelect: (topic) => setState(() => _selectedTopic = topic),
            ),
            const SizedBox(height: 20),
            if (stories.isNotEmpty) ...[
              _ContinueStoryCard(
                story: stories.first,
                listening: !widget.readingMode,
                onTap: () => AppRouter.push(
                  context,
                  (_) => _lessonScreen(stories.first),
                ),
              ),
              const SizedBox(height: 20),
              const KickerText(
                'Your short books',
                color: DesignTokens.mutedDim,
              ),
              const SizedBox(height: 10),
              ResponsiveCardGrid(
                itemCount: stories.length,
                itemBuilder: (context, index) => _StoryBookCard(
                  story: stories[index],
                  onTap: () => AppRouter.push(
                    context,
                    (_) => _lessonScreen(stories[index]),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ] else
              _EmptyLibraryNote(),
          ],
        ),
      ),
    );
  }
}

class _DirectCourseLoading extends StatelessWidget {
  const _DirectCourseLoading({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        title: Text(title, style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvasDim,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: PersonalizedGenerationLoader(
            content: title.toLowerCase() == 'reading'
                ? 'reading story'
                : 'listening lesson',
            detail: message,
            icon: CupertinoIcons.book_fill,
          ),
        ),
      ),
    );
  }
}

class _GenerateStoryTile extends StatelessWidget {
  const _GenerateStoryTile({
    required this.generating,
    required this.onTap,
    this.selectedTopic,
    required this.listening,
  });

  final bool generating;
  final VoidCallback onTap;
  final String? selectedTopic;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
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
          listening ? 'Generate listening practice' : 'Generate a new story',
          style: DesignTokens.body(15, weight: FontWeight.w600),
        ),
        subtitle: Text(
          generating
              ? 'Writing your profile-level lesson…'
              : selectedTopic != null
              ? 'A fresh bilingual ${listening ? 'listening lesson' : 'story'} with a $selectedTopic twist'
              : 'A fresh bilingual ${listening ? 'listening lesson' : 'story'}, generated for you',
          style: DesignTokens.body(12.5).copyWith(color: DesignTokens.mutedDim),
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
                color: isSelected
                    ? DesignTokens.primary
                    : DesignTokens.canvasDim,
                borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
              ),
              alignment: Alignment.center,
              child: Text(
                option ?? 'Surprise me',
                style: DesignTokens.body(12.5, weight: FontWeight.w600)
                    .copyWith(
                      color: isSelected ? Colors.white : DesignTokens.mutedDim,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContinueStoryCard extends StatelessWidget {
  const _ContinueStoryCard({
    required this.story,
    required this.onTap,
    required this.listening,
  });

  final GeneratedStory story;
  final VoidCallback onTap;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ModernCard(
        padding: 0,
        child: SizedBox(
          height: 180,
          child: Row(
            children: [
              _StoryCover(story: story, width: 122, height: 180),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        listening ? 'CONTINUE LISTENING' : 'CONTINUE READING',
                        style: DesignTokens.mono(10, weight: FontWeight.w700)
                            .copyWith(
                              color: DesignTokens.primary,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        story.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesignTokens.display(18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${story.levelBand}  •  ${story.readTimeMinutes} min',
                        style: DesignTokens.mono(
                          10.5,
                        ).copyWith(color: DesignTokens.mutedDim),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(CupertinoIcons.play_fill, size: 13),
                          const SizedBox(width: 6),
                          Text(
                            listening ? 'Open practice' : 'Open book',
                            style: DesignTokens.body(
                              12.5,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryBookCard extends StatelessWidget {
  const _StoryBookCard({required this.story, required this.onTap});

  final GeneratedStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        height: 244,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
              child: _StoryCover(
                story: story,
                width: double.infinity,
                height: 174,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              story.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(13.5, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${story.levelBand}  •  ${story.readTimeMinutes} min',
              style: DesignTokens.mono(
                10,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryCover extends StatelessWidget {
  const _StoryCover({
    required this.story,
    required this.width,
    required this.height,
  });

  final GeneratedStory story;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = story.coverUrl;
    return SizedBox(
      width: width,
      height: height,
      child: url != null && url.startsWith('asset:')
          ? Image.asset(
              url.substring('asset:'.length),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                decoration: const BoxDecoration(
                  gradient: DesignTokens.heroGradient,
                ),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.book_fill,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            )
          : url == null || url.isEmpty
          ? Container(
              decoration: const BoxDecoration(
                gradient: DesignTokens.heroGradient,
              ),
              child: const Center(
                child: Icon(
                  CupertinoIcons.book_fill,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                decoration: const BoxDecoration(
                  gradient: DesignTokens.heroGradient,
                ),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.book_fill,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
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
            color: DesignTokens.mutedDim,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'No stories yet. Generate one above to build your library.',
            textAlign: TextAlign.center,
            style: DesignTokens.body(13).copyWith(color: DesignTokens.mutedDim),
          ),
        ],
      ),
    );
  }
}
