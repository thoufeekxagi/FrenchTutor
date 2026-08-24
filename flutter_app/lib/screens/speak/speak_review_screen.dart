import 'dart:async';

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
import '../../services/review_material_service.dart';
import '../../widgets/speaking_transcript_strip.dart';
import '../lessons/listening_practice_screen.dart';
import '../lessons/story_reader_screen.dart';
import 'speak_ui.dart';
import 'speaking_practice_screen.dart';

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
              child: Padding(
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
                        color: SpeakColors.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.bolt_rounded, color: SpeakColors.accent),
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
                    if (i > 0) Divider(height: 1, color: SpeakColors.line),
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
    final isSpeaking = const {
      'Speaking',
      'Roleplay',
      'Exam speaking',
    }.contains(session.skill);
    return Semantics(
      button: isSpeaking,
      label: isSpeaking
          ? 'Open saved transcript for ${session.displayTitle}'
          : '${session.skill} ${session.displayTitle}',
      child: InkWell(
        onTap: isSpeaking
            ? () => AppRouter.push(
                context,
                (_) => SavedSpeakingTranscriptScreen(session: session),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.summary,
                style: DesignTokens.body(14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${session.skill} · ${session.displayTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: SpeakColors.inkSoft),
                    ),
                  ),
                  if (isSpeaking)
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: SpeakColors.inkSoft,
                    ),
                ],
              ),
            ],
          ),
        ),
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

/// Read-only history surface for a completed speaking call.
///
/// Opening a recent speaking item must never create another AI session. The
/// learner sees the persisted transcript first and can explicitly choose
/// "Practice again" when they want a new call.
class SavedSpeakingTranscriptScreen extends ConsumerStatefulWidget {
  const SavedSpeakingTranscriptScreen({super.key, required this.session});

  final ReviewSessionSummary session;

  @override
  ConsumerState<SavedSpeakingTranscriptScreen> createState() =>
      _SavedSpeakingTranscriptScreenState();
}

class _SavedSpeakingTranscriptScreenState
    extends ConsumerState<SavedSpeakingTranscriptScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref
        .watch(storageServiceProvider)
        .getSessionMessages(sessionId: widget.session.sessionId);
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Close saved transcript',
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: DesignTokens.nightText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Saved transcript',
                      style: DesignTokens.display(
                        21,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                  ),
                  Text(
                    widget.session.skill,
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightAccent),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.display(
                        25,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      messages.isEmpty
                          ? 'No transcript was saved for this session.'
                          : '${messages.length} saved turns · Read-only history',
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SpeakingTranscriptStrip(
                  messages: messages,
                  controller: _scrollController,
                  tutorName: 'Tutor',
                  dark: true,
                  height: constraints.maxHeight > 8
                      ? constraints.maxHeight - 8
                      : 0,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => AppRouter.push(
                    context,
                    (_) =>
                        SpeakingPracticeScreen(request: _practiceAgainRequest),
                    fullscreenDialog: true,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesignTokens.nightAccent,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Practice again',
                    style: DesignTokens.body(
                      15,
                      weight: FontWeight.w800,
                    ).copyWith(color: Colors.black),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SpeakingPracticeRequest get _practiceAgainRequest {
    final mode = switch (widget.session.skill) {
      'Roleplay' => SpeakingMode.roleplay,
      'Exam speaking' => SpeakingMode.tefSectionA,
      'Speaking' => SpeakingMode.guidedConversation,
      _ => throw StateError(
        'Saved transcript ${widget.session.sessionId} is not a speaking session.',
      ),
    };
    return SpeakingPracticeRequest(
      mode: mode,
      topic: widget.session.displayTitle,
      goal: 'Fluency',
    );
  }
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
      final url = await PracticeArtworkService.generateAndUpload(
        sync: ref.read(syncServiceProvider),
        id: story.id,
        title: story.title,
        summary: story.summary,
        topic: story.topic,
        levelBand: story.levelBand,
        coverPrompt: prompt,
      );
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
    final profile = ref.read(learningStoreProvider).profile();
    final level = _levelFor(profile.level);
    await AppRouter.push(
      context,
      (_) => SpeakingPracticeScreen(
        autoStart: true,
        request: SpeakingPracticeRequest(
          mode: SpeakingMode.roleplay,
          topic: 'Recent conversations',
          level: level,
          goal: 'Fluency',
          stage: 'speaking',
          sessionTopic: 'Personalized speaking review',
          contentKey:
              'review_speaking_${DateTime.now().microsecondsSinceEpoch}',
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
              child: Padding(
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
                  color: SpeakColors.accentSoft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _modeIcon(widget.mode),
                        color: SpeakColors.accent,
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
