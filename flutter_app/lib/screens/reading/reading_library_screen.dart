import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/generated_story_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../lessons/story_reader_screen.dart';

const _readingTopics = ['Travel', 'Food', 'Music', 'Technology', 'Environment'];

const _readingSeeds = [
  'a small-town bakery with a surprising new recipe',
  'a weekend trip that goes slightly wrong',
  'a mix-up on the first day of a new job',
  'a new neighbour with an unusual hobby',
  'a lost pet found in an unexpected place',
  'a cooking mistake that turns into something good',
];

/// The reading shelf is deliberately separate from ListeningLabScreen. The
/// two practices may share the generated-story storage and cover pipeline,
/// but they do not share their teaching prompt or lesson flow.
class ReadingLibraryScreen extends ConsumerStatefulWidget {
  const ReadingLibraryScreen({super.key, this.topic});

  final String? topic;

  @override
  ConsumerState<ReadingLibraryScreen> createState() =>
      _ReadingLibraryScreenState();
}

class _ReadingLibraryScreenState extends ConsumerState<ReadingLibraryScreen> {
  List<GeneratedStory>? _stories;
  String? _selectedTopic;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _stories = ref.read(generatedStoryStoreProvider).list();
  }

  String _levelFor(String raw) {
    final level = raw.toLowerCase();
    return const {'a1', 'a2', 'b1', 'b2'}.contains(level) ? level : 'a2';
  }

  String _topicFor(String? profileTopic) {
    if (widget.topic != null && widget.topic!.trim().isNotEmpty) {
      return 'a short everyday story connected to ${widget.topic}';
    }
    if (profileTopic != null) {
      return 'something related to ${profileTopic.toLowerCase()} that could happen in daily life';
    }
    final profile = ref.read(learningStoreProvider).profile();
    final pool = [
      ..._readingTopics.map(
        (topic) =>
            'something related to ${topic.toLowerCase()} that could happen in daily life',
      ),
      ...profile.interests.map(
        (interest) =>
            'something related to $interest that could happen in daily life',
      ),
      ..._readingSeeds,
    ];
    return pool[Random().nextInt(pool.length)];
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final package = await LessonAgentService.shared.buildReadingStoryBook(
        topic: _topicFor(_selectedTopic),
        levelBand: _levelFor(profile.level),
      );
      var story = GeneratedStory(
        id: newGeneratedStoryId(),
        passage: package.passage,
        quiz: package.quiz,
        keywords: package.keywords,
        createdAt: DateTime.now(),
        levelBand: package.levelBand,
        summary: package.summary,
        topic: package.topic,
        readTimeMinutes: package.readTimeMinutes,
      );

      // Reading gets one cover call after the one text call. If artwork or
      // storage is unavailable, the story still saves and uses the editorial
      // cover treatment below instead of disappearing behind a blank box.
      try {
        final bytes = await LessonAgentService.shared.generateStoryCover(
          title: story.title,
          summary: story.summary,
          topic: story.topic,
          levelBand: story.levelBand,
          coverPrompt: package.coverPrompt,
        );
        final url = await ref
            .read(syncServiceProvider)
            .uploadStoryCover(storyId: story.id, bytes: bytes);
        if (url != null) story = story.copyWith(coverUrl: url);
      } catch (error, stackTrace) {
        debugPrint('Reading cover generation failed: $error\n$stackTrace');
      }

      ref.read(generatedStoryStoreProvider).insert(story);
      unawaited(_prewarmNarration(story));
      if (!mounted) return;
      setState(() {
        _stories = ref.read(generatedStoryStoreProvider).list();
        _generating = false;
      });
      AppRouter.push(context, (_) => StoryReaderScreen(story: story));
    } catch (error, stackTrace) {
      debugPrint('Reading story generation failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create the story. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _prewarmNarration(GeneratedStory story) {
    return LessonSpeechService.shared.prewarmNarration([
      for (var i = 0; i < story.passage.segments.length; i++)
        SpeechItem(
          text: story.passage.segments[i].fr,
          language: 'fr-FR',
          contentItemId: story.segmentContentId(i),
        ),
    ]);
  }

  void _open(GeneratedStory story) {
    AppRouter.push(context, (_) => StoryReaderScreen(story: story));
  }

  @override
  Widget build(BuildContext context) {
    final stories = [...?_stories]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        title: Text('Reading', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvasDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            _GenerateReadingTile(
              generating: _generating,
              selectedTopic: _selectedTopic,
              onTap: _generate,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _readingTopics.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final topic = index == 0 ? null : _readingTopics[index - 1];
                  final selected = topic == _selectedTopic;
                  return GestureDetector(
                    onTap: () => setState(
                      () => _selectedTopic = selected ? null : topic,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? DesignTokens.primary : Colors.white,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        topic ?? 'Surprise me',
                        style: DesignTokens.body(12.5, weight: FontWeight.w600)
                            .copyWith(
                              color: selected
                                  ? Colors.white
                                  : DesignTokens.mutedDim,
                            ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            if (stories.isNotEmpty) ...[
              GestureDetector(
                onTap: () => _open(stories.first),
                child: _ContinueReadingCard(story: stories.first),
              ),
              const SizedBox(height: 24),
              const KickerText(
                'Your short books',
                color: DesignTokens.mutedDim,
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 22,
                  childAspectRatio: 0.62,
                ),
                itemBuilder: (context, index) => _ReadingBookCard(
                  story: stories[index],
                  onTap: () => _open(stories[index]),
                ),
              ),
            ] else ...[
              const KickerText(
                'Your short books',
                color: DesignTokens.mutedDim,
              ),
              const SizedBox(height: 10),
              ModernCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.book,
                      color: DesignTokens.primary,
                      size: 28,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your shelf is ready for its first book.',
                      style: DesignTokens.display(18),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose a theme above, then create a short story matched to your profile level.',
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _GenerateReadingTile extends StatelessWidget {
  const _GenerateReadingTile({
    required this.generating,
    required this.selectedTopic,
    required this.onTap,
  });

  final bool generating;
  final String? selectedTopic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: DesignTokens.primarySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: generating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(DesignTokens.primary),
                  ),
                )
              : const Icon(
                  CupertinoIcons.book_fill,
                  color: DesignTokens.primary,
                ),
        ),
        title: Text(
          'Create a reading story',
          style: DesignTokens.body(15, weight: FontWeight.w700),
        ),
        subtitle: Text(
          generating
              ? 'Writing your next short book…'
              : selectedTopic == null
              ? 'A fresh story shaped to your course level'
              : 'A fresh story about ${selectedTopic!.toLowerCase()}',
          style: DesignTokens.body(12.5).copyWith(color: DesignTokens.mutedDim),
        ),
        trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
        onTap: generating ? null : onTap,
      ),
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard({required this.story});

  final GeneratedStory story;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      padding: 0,
      child: SizedBox(
        height: 190,
        child: Row(
          children: [
            _ReadingCover(story: story, width: 126, height: 190),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTINUE READING',
                      style: DesignTokens.label(10).copyWith(
                        color: DesignTokens.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      story.displayTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.display(18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${story.passage.segments.length} short scenes · ${story.readTimeMinutes} min',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.mutedDim),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        Icon(CupertinoIcons.play_fill, size: 13),
                        SizedBox(width: 6),
                        Text('Open book'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingBookCard extends StatelessWidget {
  const _ReadingBookCard({required this.story, required this.onTap});

  final GeneratedStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 158,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
              child: _ReadingCover(story: story, width: 158, height: 184),
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
              '${story.passage.segments.length} scenes · ${story.readTimeMinutes} min',
              style: DesignTokens.body(
                11,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingCover extends StatelessWidget {
  const _ReadingCover({
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
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: DesignTokens.heroGradient,
            ),
          ),
          Positioned(
            right: -24,
            top: -18,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: DesignTokens.secondary.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -28,
            bottom: 26,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: DesignTokens.info.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.book_fill,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(height: 12),
                Text(
                  story.passage.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.display(15).copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'FRENCH READING',
                  style: DesignTokens.label(
                    9,
                  ).copyWith(color: Colors.white70, letterSpacing: 1.1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
