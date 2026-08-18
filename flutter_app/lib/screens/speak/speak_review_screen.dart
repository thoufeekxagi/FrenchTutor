import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../data/database/generated_story_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/practice_artwork_service.dart';
import '../../services/review_material_service.dart';
import '../lessons/listening_practice_screen.dart';
import '../lessons/story_reader_screen.dart';
import '../session/session_screen.dart';
import 'speak_ui.dart';

/// The only three outputs a learner can request from a cross-app review.
/// Reading, listening, and speaking all use the same recent-history source;
/// only the generated activity changes.
enum SpeakReviewMode { speaking, reading, listening }

class SpeakReviewScreen extends ConsumerStatefulWidget {
  const SpeakReviewScreen({super.key});

  @override
  ConsumerState<SpeakReviewScreen> createState() => _SpeakReviewScreenState();
}

class _SpeakReviewScreenState extends ConsumerState<SpeakReviewScreen> {
  var _mode = SpeakReviewMode.speaking;

  @override
  Widget build(BuildContext context) {
    final sessions = ReviewMaterialService.recentSessions(
      ref.watch(storageServiceProvider),
    );
    final canStart = sessions.isNotEmpty;

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
                            'Built from your 15 most recent practice sessions.',
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
                SpeakProgressBar(value: sessions.length / 10),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${sessions.length} ${sessions.length == 1 ? 'session' : 'sessions'} ready',
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
                            sessions: sessions,
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
          if (sessions.isEmpty)
            const SpeakCard(
              child: Text(
                'Finish a practice session and its summary will appear here.',
              ),
            )
          else
            SpeakCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < sessions.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: SpeakColors.line),
                    _materialRow(sessions[i]),
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

  Widget _materialRow(ReviewSessionSummary session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.summary,
            style: DesignTokens.body(14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${session.skill} · ${session.displayTitle}',
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
    SpeakReviewMode.reading => 'Reading',
  };

  IconData _modeIcon(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.speaking => Icons.mic_rounded,
    SpeakReviewMode.listening => Icons.headphones_rounded,
    SpeakReviewMode.reading => Icons.menu_book_rounded,
  };
}

/// Generates the selected review format from completed-session summaries,
/// then hands off to the same lesson screens used everywhere else.
class SpeakReviewLaunchScreen extends ConsumerStatefulWidget {
  const SpeakReviewLaunchScreen({
    super.key,
    required this.mode,
    required this.sessions,
  });

  final SpeakReviewMode mode;
  final List<ReviewSessionSummary> sessions;

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
          await _startSpeakingReview();
        case SpeakReviewMode.listening:
          final story = await _generateStory(listening: true);
          if (!mounted) return;
          await AppRouter.push(
            context,
            (_) => ListeningPracticeScreen(story: story),
            fullscreenDialog: true,
          );
        case SpeakReviewMode.reading:
          final story = await _generateStory(listening: false);
          if (!mounted) return;
          await AppRouter.push(
            context,
            (_) => StoryReaderScreen(story: story),
            fullscreenDialog: true,
          );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Review launch failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _running = false;
          _error = 'Review generation failed: $error';
        });
      }
    }
  }

  Future<GeneratedStory> _generateStory({required bool listening}) async {
    final profile = ref.read(learningStoreProvider).profile();
    final level = _levelFor(profile.level);
    final topic = _reviewTopic();
    final existingStories = ref.read(generatedStoryStoreProvider).list();
    final avoidTitles = existingStories.map((story) => story.title);
    final avoidOpenings = existingStories.map(
      (story) =>
          story.passage.segments.isEmpty ? '' : story.passage.segments.first.fr,
    );
    final package = listening
        ? await LessonAgentService.shared.buildListeningStoryBook(
            topic: topic,
            levelBand: level,
            avoidTitles: avoidTitles,
            avoidOpenings: avoidOpenings,
          )
        : await LessonAgentService.shared.buildReadingStoryBook(
            topic: topic,
            levelBand: level,
            avoidTitles: avoidTitles,
            avoidOpenings: avoidOpenings,
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

  Future<void> _attachStoryCover(GeneratedStory story, String prompt) async {
    try {
      final bytes = await PracticeArtworkService.generate(
        id: story.id,
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

  String _reviewTopic() {
    final profile = ref.read(learningStoreProvider).profile();
    return ReviewMaterialService.modePrompt(
      _modeLabel(widget.mode),
      widget.sessions,
      level: _levelFor(profile.level),
    );
  }

  Future<void> _startSpeakingReview() async {
    if (!await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        ) ||
        !mounted) {
      return;
    }
    LessonSpeechService.shared.deactivate();
    final profile = ref.read(learningStoreProvider).profile();
    final level = _levelFor(profile.level);
    await AppRouter.push(
      context,
      (_) => SessionScreen(
        apiKey: ApiKeys.geminiKey,
        stage: 'speaking',
        sessionTopic: 'Personalized speaking review',
        contentKey: 'review_speaking_${DateTime.now().microsecondsSinceEpoch}',
        lessonContext:
            '''
${_reviewTopic()}

SPEAKING REVIEW CONTRACT
- Keep the interaction in a realistic French situation chosen from the recent history.
- Start with one short, level-appropriate prompt; do not dump a lesson or a list of questions.
- Let the learner answer before correcting.
- After each answer, give one concise correction and one stronger reusable phrase.
- Use English support only for A1/A2 when it prevents confusion. For B1/B2, keep the review in French.
- Finish with a short spoken recap of the learner's strongest improvement and next priority.
''',
        kickoffMessage:
            '(App instruction, not the student: begin a personalized $level speaking review from the learner history. Ask one short question in French and wait for the learner.)',
      ),
      fullscreenDialog: true,
    );
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
                            ? 'Your recent session summaries are being woven into a fresh lesson.'
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
    SpeakReviewMode.reading => 'Reading',
  };

  IconData _modeIcon(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.speaking => Icons.mic_rounded,
    SpeakReviewMode.listening => Icons.headphones_rounded,
    SpeakReviewMode.reading => Icons.menu_book_rounded,
  };
}
