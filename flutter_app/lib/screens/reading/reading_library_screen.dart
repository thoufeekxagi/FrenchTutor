import 'dart:async';

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
import '../../services/practice_artwork_service.dart';
import '../../widgets/personalized_generation_loader.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../exam/exam_practice_screen.dart';
import '../lessons/story_reader_screen.dart';

const _readingTopics = ['Travel', 'Food', 'Music', 'Technology', 'Environment'];

/// The reading shelf is deliberately separate from ListeningLabScreen. The
/// two practices may share the generated-story storage and cover pipeline,
/// but they do not share their teaching prompt or lesson flow.
class ReadingLibraryScreen extends ConsumerStatefulWidget {
  const ReadingLibraryScreen({
    super.key,
    this.topic,
    this.autoStart = false,
    this.examName,
    this.examLevel,
    this.examMode = false,
  });

  final String? topic;
  final bool autoStart;
  final String? examName;
  final String? examLevel;
  final bool examMode;

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
    if (!widget.examMode) {
      _stories = ref
          .read(generatedStoryStoreProvider)
          .list(practiceMode: 'reading');
      unawaited(_refreshStories());
    }
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_generate());
      });
    }
  }

  Future<void> _refreshStories() async {
    if (widget.examMode) return;
    try {
      await ref.read(syncServiceProvider).hydrateGeneratedStories();
    } catch (error, stackTrace) {
      debugPrint('Reading story hydration failed: $error\n$stackTrace');
    }
    if (!mounted) return;
    setState(() {
      _stories = ref
          .read(generatedStoryStoreProvider)
          .list(practiceMode: 'reading');
    });
  }

  String _levelFor(String raw) {
    final level = raw.toLowerCase();
    return const {'a1', 'a2', 'b1', 'b2'}.contains(level) ? level : 'a2';
  }

  String? _topicFor(String? profileTopic) {
    if (widget.topic != null && widget.topic!.trim().isNotEmpty) {
      return 'a short everyday story connected to ${widget.topic}';
    }
    if (profileTopic != null) {
      return 'something related to ${profileTopic.toLowerCase()} that could happen in daily life';
    }
    // Null is intentional: it is the true Surprise me mode. The generator
    // must choose the premise itself rather than receiving onboarding
    // interests or a small fixed topic pool.
    return null;
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final existingStories = ref.read(generatedStoryStoreProvider).list();
      final package = await LessonAgentService.shared.buildReadingStoryBook(
        topic: _topicFor(_selectedTopic),
        levelBand: widget.examLevel ?? _levelFor(profile.level),
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
        practiceMode: 'reading',
      );

      final examAttempt = widget.examMode
          ? ref
                .read(examPracticeStoreProvider)
                .startStory(
                  examName: widget.examName ?? 'Exam practice',
                  levelBand: widget.examLevel ?? story.levelBand,
                  skill: 'reading',
                  story: story,
                )
          : null;
      // Exam content lives only in the readiness store. Regular stories keep
      // using the course library and its artwork/narration pipeline.
      if (!widget.examMode) {
        ref.read(generatedStoryStoreProvider).insert(story);
        unawaited(_prewarmNarration(story));
      }
      if (!mounted) return;
      if (!widget.examMode) {
        setState(() {
          _stories = ref
              .read(generatedStoryStoreProvider)
              .list(practiceMode: 'reading');
          _generating = false;
        });
        // Start artwork before opening the reader. The reader watches the
        // saved story and can replace its placeholder as soon as the upload
        // completes.
        unawaited(_generateCover(story, package.coverPrompt));
      }
      if (widget.examMode) {
        final result = await AppRouter.push<ExamPracticeResult>(
          context,
          (_) => ExamPracticeScreen(
            story: story,
            examName: widget.examName ?? 'Exam practice',
            levelBand: widget.examLevel ?? story.levelBand,
            skill: 'reading',
          ),
          fullscreenDialog: true,
        );
        if (result != null && examAttempt != null) {
          ref
              .read(examPracticeStoreProvider)
              .complete(
                id: examAttempt.id,
                score: result.correct,
                total: result.total,
              );
        }
        if (widget.autoStart && mounted) {
          Navigator.of(context).pop(result != null);
        }
      } else {
        final result = await AppRouter.push<StoryReaderResult>(
          context,
          (_) => StoryReaderScreen(
            story: story,
            showFinishButton: widget.autoStart,
          ),
          fullscreenDialog: widget.autoStart,
        );
        if (widget.autoStart && mounted) {
          Navigator.of(context).pop(result != null);
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Reading story generation failed: $error\n$stackTrace');
      if (mounted) {
        if (widget.autoStart) {
          Navigator.of(context).pop(false);
          return;
        }
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Story generation failed: $error')),
        );
      }
    }
  }

  Future<void> _generateCover(GeneratedStory story, String? coverPrompt) async {
    // Capture providers before awaiting network/image work. This task is
    // intentionally fire-and-forget, so the screen may be disposed before it
    // completes; using `ref` after that point would recreate the Sentry crash
    // seen in other async screens.
    final syncService = ref.read(syncServiceProvider);
    final storyStore = ref.read(generatedStoryStoreProvider);
    try {
      final url = await PracticeArtworkService.generateAndUpload(
        sync: syncService,
        id: story.id,
        title: story.title,
        summary: story.summary,
        topic: story.topic,
        levelBand: story.levelBand,
        coverPrompt: coverPrompt,
      );
      if (url == null) return;
      storyStore.updateCoverUrl(story.id, url);
      if (!mounted) return;
      setState(() {
        _stories = storyStore.list(practiceMode: 'reading');
      });
    } catch (error, stackTrace) {
      debugPrint('Reading cover generation failed: $error\n$stackTrace');
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
      for (var i = 0; i < story.keywords.length; i++)
        SpeechItem(
          text: story.keywords[i].fr,
          language: 'fr-FR',
          contentItemId: '${story.id}_kw_${story.keywords[i].id}',
        ),
    ]);
  }

  void _open(GeneratedStory story) {
    AppRouter.push(
      context,
      (_) => StoryReaderScreen(story: story),
      fullscreenDialog: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return const _DirectReadingLoading();
    }
    final stories = [...?_stories]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      appBar: AppBar(
        leading: const BackButton(color: DesignTokens.nightText),
        title: Text(
          'Reading',
          style: DesignTokens.display(
            21,
          ).copyWith(color: DesignTokens.nightText),
        ),
        backgroundColor: DesignTokens.nightCanvas,
        foregroundColor: DesignTokens.nightText,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 36),
          children: [
            Text(
              'Stories matched to your level',
              style: DesignTokens.body(
                13,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
            const SizedBox(height: 18),
            if (_generating)
              const PersonalizedGenerationLoader(
                content: 'reading story',
                detail: 'Shaping a short book around your level and interests.',
                icon: CupertinoIcons.book_fill,
              )
            else
              _GenerateReadingTile(
                generating: false,
                selectedTopic: _selectedTopic,
                onTap: _generate,
              ),
            const SizedBox(height: 16),
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
                        color: selected
                            ? DesignTokens.nightAccentSoft
                            : DesignTokens.nightSurface,
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusPill,
                        ),
                        border: Border.all(
                          color: selected
                              ? DesignTokens.nightAccent
                              : DesignTokens.nightHairline,
                        ),
                      ),
                      child: Text(
                        topic ?? 'Surprise me',
                        style: DesignTokens.body(12.5, weight: FontWeight.w600)
                            .copyWith(
                              color: selected
                                  ? DesignTokens.nightAccent
                                  : DesignTokens.nightMuted,
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
              const SizedBox(height: 28),
              Text(
                'Previous stories',
                style: DesignTokens.display(
                  19,
                ).copyWith(color: DesignTokens.nightText),
              ),
              const SizedBox(height: 12),
              for (final story in stories.skip(1)) ...[
                _PreviousStoryRow(story: story, onTap: () => _open(story)),
                const SizedBox(height: 12),
              ],
            ] else ...[
              Text(
                'Previous stories',
                style: DesignTokens.display(
                  19,
                ).copyWith(color: DesignTokens.nightText),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: DesignTokens.nightSurface,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
                  border: Border.all(color: DesignTokens.nightHairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      CupertinoIcons.book,
                      color: DesignTokens.nightAccent,
                      size: 28,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your shelf is ready for its first book.',
                      style: DesignTokens.display(
                        18,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose a theme above, then create a short story matched to your profile level.',
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.nightMuted, height: 1.45),
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

class _DirectReadingLoading extends StatelessWidget {
  const _DirectReadingLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      appBar: AppBar(
        title: Text(
          'Reading',
          style: DesignTokens.display(
            20,
          ).copyWith(color: DesignTokens.nightText),
        ),
        backgroundColor: DesignTokens.nightCanvas,
        foregroundColor: DesignTokens.nightText,
        elevation: 0,
      ),
      body: const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: PersonalizedGenerationLoader(
            content: 'reading story',
            detail: 'Building a short book for your course level.',
            icon: CupertinoIcons.book_fill,
          ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: DesignTokens.nightAccentSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: generating
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      DesignTokens.nightAccent,
                    ),
                  ),
                )
              : const Icon(
                  CupertinoIcons.book_fill,
                  color: DesignTokens.nightAccent,
                ),
        ),
        title: Text(
          'Create a reading story',
          style: DesignTokens.body(
            15,
            weight: FontWeight.w700,
          ).copyWith(color: DesignTokens.nightText),
        ),
        subtitle: Text(
          generating
              ? 'Writing your next short book…'
              : selectedTopic == null
              ? 'A fresh story shaped to your course level'
              : 'A fresh story about ${selectedTopic!.toLowerCase()}',
          style: DesignTokens.body(
            12.5,
          ).copyWith(color: DesignTokens.nightMuted),
        ),
        trailing: const Icon(
          CupertinoIcons.chevron_right,
          size: 18,
          color: DesignTokens.nightAccent,
        ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: SizedBox(
        height: 258,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ReadingCover(story: story, width: double.infinity, height: 258),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    DesignTokens.nightCanvas.withValues(alpha: 0.94),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTINUE READING',
                    style: DesignTokens.label(11).copyWith(
                      color: DesignTokens.nightAccent,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    story.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.display(
                      24,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${story.levelBand}  ·  ${story.passage.segments.length} scenes  ·  ${story.readTimeMinutes} min',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.nightMuted),
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

class _PreviousStoryRow extends StatelessWidget {
  const _PreviousStoryRow({required this.story, required this.onTap});

  final GeneratedStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 130,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Row(
          children: [
            _ReadingCover(story: story, width: 112, height: 130),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      story.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.display(
                        16,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${story.levelBand}  ·  ${story.readTimeMinutes} min',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: DesignTokens.nightAccent,
              ),
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
    if (url != null && url.startsWith('asset:')) {
      return Image.asset(
        url.substring('asset:'.length),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
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
