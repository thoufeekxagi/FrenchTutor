import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/generated_roleplay_store.dart';
import '../../data/database/generated_story_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/review_material_service.dart';
import '../lessons/listening_practice_screen.dart';
import '../lessons/story_reader_screen.dart';
import '../pathway/agent_led_listening_screen.dart';
import 'speak_review_detail_screen.dart';
import 'speak_ui.dart';

class SpeakReviewScreen extends ConsumerStatefulWidget {
  const SpeakReviewScreen({super.key});

  @override
  ConsumerState<SpeakReviewScreen> createState() => _SpeakReviewScreenState();
}

class _SpeakReviewScreenState extends ConsumerState<SpeakReviewScreen> {
  var _mode = SpeakReviewMode.speaking;

  @override
  Widget build(BuildContext context) {
    final material = ReviewMaterialService.recent(
      ref.watch(storageServiceProvider),
    );
    final canStart = material.isNotEmpty;

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          SpeakHeader(
            leading: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: SpeakColors.inkSoft,
                  size: 25,
                ),
              ),
            ),
            title: 'Review',
            subtitle: 'Revisit the French from your latest practice.',
          ),
          const SizedBox(height: 20),
          const SpeakSectionTitle(title: 'Choose how to review'),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: SpeakReviewMode.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final mode = SpeakReviewMode.values[index];
                return _modePill(mode, _modeLabel(mode), _modeIcon(mode));
              },
            ),
          ),
          const SizedBox(height: 16),
          SpeakCard(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: SpeakColors.blueSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: SpeakColors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Smart Review',
                            style: DesignTokens.body(
                              16,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Built from your ten most recent transcript turns.',
                            style: DesignTokens.body(
                              12,
                            ).copyWith(color: SpeakColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SpeakProgressBar(value: material.length / 10),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${material.length} ${material.length == 1 ? 'phrase' : 'phrases'} ready',
                      style: DesignTokens.body(12, weight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      canStart ? '5 min' : 'Practice first',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SpeakPrimaryButton(
                  label: 'Start review',
                  icon: Icons.arrow_forward_rounded,
                  onTap: canStart
                      ? () => AppRouter.push(
                          context,
                          (_) => SpeakReviewLaunchScreen(
                            mode: _mode,
                            material: material,
                          ),
                          fullscreenDialog: true,
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const SpeakSectionTitle(title: 'Recent practice'),
          const SizedBox(height: 12),
          if (material.isEmpty)
            const SpeakCard(
              child: Text(
                'Finish a speaking, listening, story, or roleplay session and its transcript will appear here.',
              ),
            )
          else
            SpeakCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < material.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: SpeakColors.line),
                    _materialRow(material[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _modePill(SpeakReviewMode mode, String label, IconData icon) {
    return SpeakPill(
      label: label,
      icon: icon,
      selected: _mode == mode,
      onTap: () => setState(() => _mode = mode),
    );
  }

  Widget _materialRow(ReviewPhrase phrase) {
    final speaker = phrase.role == 'assistant' ? 'Tutor' : 'You';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phrase.text,
            style: DesignTokens.body(14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '$speaker · ${phrase.source}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesignTokens.body(11).copyWith(color: SpeakColors.inkSoft),
          ),
        ],
      ),
    );
  }

  String _modeLabel(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.speaking => 'Speaking',
    SpeakReviewMode.listening => 'Listening',
    SpeakReviewMode.stories => 'Stories',
    SpeakReviewMode.roleplay => 'Roleplay',
  };

  IconData _modeIcon(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.speaking => Icons.mic_rounded,
    SpeakReviewMode.listening => Icons.headphones_rounded,
    SpeakReviewMode.stories => Icons.auto_stories_outlined,
    SpeakReviewMode.roleplay => Icons.forum_outlined,
  };
}

/// Generates the selected review format from the learner's real recent
/// material, then hands off to the same lesson screens used everywhere else.
class SpeakReviewLaunchScreen extends ConsumerStatefulWidget {
  const SpeakReviewLaunchScreen({
    super.key,
    required this.mode,
    required this.material,
  });

  final SpeakReviewMode mode;
  final List<ReviewPhrase> material;

  @override
  ConsumerState<SpeakReviewLaunchScreen> createState() =>
      _SpeakReviewLaunchScreenState();
}

class _SpeakReviewLaunchScreenState
    extends ConsumerState<SpeakReviewLaunchScreen> {
  String? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_launch());
  }

  Future<void> _launch() async {
    if (_running) return;
    _running = true;
    try {
      switch (widget.mode) {
        case SpeakReviewMode.speaking:
          await AppRouter.push(
            context,
            (_) => SpeakReviewDetailScreen(phrases: widget.material),
            fullscreenDialog: true,
          );
        case SpeakReviewMode.listening:
          final story = await _generateStory(listening: true);
          if (!mounted) return;
          await AppRouter.push(
            context,
            (_) => ListeningPracticeScreen(story: story),
            fullscreenDialog: true,
          );
        case SpeakReviewMode.stories:
          final story = await _generateStory(listening: false);
          if (!mounted) return;
          await AppRouter.push(
            context,
            (_) => StoryReaderScreen(story: story),
            fullscreenDialog: true,
          );
        case SpeakReviewMode.roleplay:
          final roleplay = await _generateRoleplay();
          if (!mounted) return;
          await AppRouter.push(
            context,
            (_) => AgentLedListeningScreen(
              passage: roleplay.passage,
              noteContext: 'Roleplay review',
              sessionStage: 'roleplay',
              sessionTopic: roleplay.displayTitle,
            ),
            fullscreenDialog: true,
          );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Review launch failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _running = false;
          _error = 'We could not build this review. Try again.';
        });
      }
    }
  }

  Future<GeneratedStory> _generateStory({required bool listening}) async {
    final profile = ref.read(learningStoreProvider).profile();
    final level = _levelFor(profile.level);
    final topic = _reviewTopic();
    final package = listening
        ? await LessonAgentService.shared.buildListeningStoryBook(
            topic: topic,
            levelBand: level,
          )
        : await LessonAgentService.shared.buildReadingStoryBook(
            topic: topic,
            levelBand: level,
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
      practiceMode: listening ? 'listening' : 'reading',
    );
    ref.read(generatedStoryStoreProvider).insert(story);
    unawaited(_prewarmStory(story));
    unawaited(_attachStoryCover(story, package.coverPrompt));
    return story;
  }

  Future<GeneratedRoleplay> _generateRoleplay() async {
    final profile = ref.read(learningStoreProvider).profile();
    final passage = await LessonAgentService.shared.buildStandaloneRoleplay(
      scenario: _reviewTopic(),
      levelBand: _levelFor(profile.level),
    );
    final roleplay = GeneratedRoleplay(
      id: newGeneratedRoleplayId(),
      passage: passage,
      createdAt: DateTime.now(),
    );
    ref.read(generatedRoleplayStoreProvider).insert(roleplay);
    unawaited(_prewarmRoleplay(roleplay));
    unawaited(_attachRoleplayCover(roleplay));
    return roleplay;
  }

  Future<void> _prewarmStory(GeneratedStory story) {
    return LessonSpeechService.shared.prewarmNarration([
      for (var i = 0; i < story.passage.segments.length; i++)
        SpeechItem(
          text: story.passage.segments[i].fr,
          language: 'fr-FR',
          contentItemId: story.segmentContentId(i),
        ),
    ]);
  }

  Future<void> _prewarmRoleplay(GeneratedRoleplay roleplay) {
    final items = <SpeechItem>[];
    for (var i = 0; i < roleplay.passage.segments.length; i++) {
      final segment = roleplay.passage.segments[i];
      if (segment.characterFr?.isNotEmpty ?? false) {
        items.add(
          SpeechItem(
            text: segment.characterFr!,
            language: 'fr-FR',
            contentItemId: '${roleplay.id}_seg${i}_char',
          ),
        );
      }
      if (segment.fr.isNotEmpty) {
        items.add(
          SpeechItem(
            text: segment.fr,
            language: 'fr-FR',
            contentItemId: '${roleplay.id}_seg${i}_learner',
          ),
        );
      }
    }
    return LessonSpeechService.shared.prewarmNarration(items);
  }

  Future<void> _attachStoryCover(GeneratedStory story, String prompt) async {
    try {
      final bytes = await LessonAgentService.shared.generateStoryCover(
        title: story.title,
        summary: story.summary,
        topic: story.topic,
        levelBand: story.levelBand,
        coverPrompt: prompt,
      );
      final url = await ref
          .read(syncServiceProvider)
          .uploadStoryCover(storyId: story.id, bytes: bytes);
      if (url != null && url.isNotEmpty) {
        ref.read(generatedStoryStoreProvider).updateCoverUrl(story.id, url);
      }
    } catch (error, stackTrace) {
      debugPrint('Review story cover failed: $error\n$stackTrace');
    }
  }

  Future<void> _attachRoleplayCover(GeneratedRoleplay roleplay) async {
    try {
      final bytes = await LessonAgentService.shared.generateStoryCover(
        title: roleplay.title,
        summary: roleplay.passage.segments
            .take(2)
            .map((segment) => segment.en.isNotEmpty ? segment.en : segment.fr)
            .join(' '),
        topic: roleplay.title,
        levelBand: 'A1',
        coverPrompt:
            'A premium editorial cover for a French language roleplay scene. '
            'Show one cinematic real-life moment that matches the title and dialogue. '
            'Use realistic publishing photography or editorial realism, never cartoon art.',
      );
      final url = await ref
          .read(syncServiceProvider)
          .uploadStoryCover(storyId: roleplay.id, bytes: bytes);
      if (url != null && url.isNotEmpty) {
        ref
            .read(generatedRoleplayStoreProvider)
            .updateCoverUrl(roleplay.id, url);
      }
    } catch (error, stackTrace) {
      debugPrint('Review roleplay cover failed: $error\n$stackTrace');
    }
  }

  String _reviewTopic() {
    final context = widget.material
        .map(
          (phrase) =>
              '${phrase.role == 'assistant' ? 'Tutor' : 'Learner'}: ${phrase.text}',
        )
        .join('\n');
    final clipped = context.length > 1200
        ? context.substring(0, 1200)
        : context;
    return 'Create a fresh review lesson that naturally reuses these recent practice lines:\n$clipped';
  }

  String _levelFor(String raw) {
    final normalized = raw.toLowerCase();
    return const {'a1', 'a2', 'b1', 'b2'}.contains(normalized)
        ? normalized.toUpperCase()
        : 'A2';
  }

  @override
  Widget build(BuildContext context) {
    return SpeakScaffold(
      child: Column(
        children: [
          SpeakHeader(
            leading: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: SpeakColors.inkSoft,
                  size: 25,
                ),
              ),
            ),
            title: 'Building review',
            subtitle: 'Using your recent practice material.',
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SpeakCard(
                  color: SpeakColors.blueSoft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _modeIcon(widget.mode),
                        color: SpeakColors.blue,
                        size: 36,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _error ??
                            'Preparing ${_modeLabel(widget.mode).toLowerCase()} review…',
                        style: DesignTokens.display(22),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error == null
                            ? 'Your latest transcript turns are being woven into a fresh lesson.'
                            : 'Your recent practice is still safe. You can retry this review.',
                        style: DesignTokens.body(
                          13,
                        ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        SpeakPrimaryButton(
                          label: 'Try again',
                          icon: Icons.refresh_rounded,
                          onTap: _launch,
                        ),
                      ] else ...[
                        const SizedBox(height: 18),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _modeLabel(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.speaking => 'Speaking',
    SpeakReviewMode.listening => 'Listening',
    SpeakReviewMode.stories => 'Stories',
    SpeakReviewMode.roleplay => 'Roleplay',
  };

  IconData _modeIcon(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.speaking => Icons.mic_rounded,
    SpeakReviewMode.listening => Icons.headphones_rounded,
    SpeakReviewMode.stories => Icons.auto_stories_outlined,
    SpeakReviewMode.roleplay => Icons.forum_outlined,
  };
}
