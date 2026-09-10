import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/generated_story_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/content_models.dart';
import '../../models/writing_course.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_agent_service.dart';
import '../../services/lesson_audio_deck_service.dart';
import '../../services/practice_artwork_service.dart';
import '../../services/review_material_service.dart';
import '../../widgets/speaking_transcript_strip.dart';
import '../lessons/listening_practice_screen.dart';
import '../lessons/story_reader_screen.dart';
import '../lessons/writing_course_lesson_screen.dart';
import 'speak_ui.dart';
import 'speaking_lesson_flow_screen.dart';
import 'speaking_practice_screen.dart';
import 'smart_review_lesson_screen.dart';

/// The output formats a learner can request from a cross-app plan.
/// Every mode uses the same universal learner evidence; only the activity
/// format changes.
enum SpeakReviewMode { smart, speaking, reading, listening, writing }

class SpeakReviewScreen extends ConsumerStatefulWidget {
  const SpeakReviewScreen({super.key, this.kind = 'review', this.initialMode});

  final String kind;
  final SpeakReviewMode? initialMode;

  @override
  ConsumerState<SpeakReviewScreen> createState() => _SpeakReviewScreenState();
}

class _SpeakReviewScreenState extends ConsumerState<SpeakReviewScreen> {
  var _mode = SpeakReviewMode.smart;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? SpeakReviewMode.smart;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ReviewMaterialService.recentSessions(
      ref.watch(storageServiceProvider),
    );
    final plan = widget.kind == 'warmup'
        ? ReviewMaterialService.buildWarmupPlan(
            db: ref.watch(databaseProvider),
            profile: ref.watch(learningStoreProvider).profile(),
            mode: _modeLabel(_mode),
          )
        : ReviewMaterialService.buildPersonalizedPlan(
            db: ref.watch(databaseProvider),
            profile: ref.watch(learningStoreProvider).profile(),
            mode: _modeLabel(_mode),
          );
    final canStart = widget.kind == 'warmup'
        ? plan.futureContext != null || plan.hasEvidence
        : plan.hasEvidence || sessions.isNotEmpty;
    final isWarmup = widget.kind == 'warmup';

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
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
            title: isWarmup ? 'Warm-up' : 'Review',
            subtitle: isWarmup
                ? 'A quick start before your next lesson.'
                : 'Keep the French you have already learned active.',
          ),
          const SizedBox(height: 24),
          _formatSection(),
          const SizedBox(height: 18),
          _planCard(context, plan, sessions, canStart, isWarmup),
          const SizedBox(height: 28),
          _recentPractice(sessions),
          if (sessions.isNotEmpty) ...[
            const SizedBox(height: 22),
            _retrySavedPractice(sessions),
          ],
        ],
      ),
    );
  }

  Widget _formatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRACTICE FORMAT',
          style: DesignTokens.body(
            11,
            weight: FontWeight.w800,
          ).copyWith(color: SpeakColors.accent, letterSpacing: 1.6),
        ),
        const SizedBox(height: 5),
        Text('How do you want to practise?', style: DesignTokens.display(22)),
        const SizedBox(height: 12),
        Container(
          height: 58,
          decoration: BoxDecoration(
            color: SpeakColors.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: SpeakColors.line),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: SpeakColors.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<SpeakReviewMode>(
                  value: _mode,
                  isExpanded: true,
                  padding: const EdgeInsets.only(left: 17),
                  icon: Padding(
                    padding: const EdgeInsets.only(right: 15),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: SpeakColors.accent,
                      size: 24,
                    ),
                  ),
                  dropdownColor: SpeakColors.surface,
                  borderRadius: BorderRadius.circular(15),
                  selectedItemBuilder: (context) => [
                    for (final mode in SpeakReviewMode.values)
                      _formatMenuItem(mode, selected: true, showCheck: false),
                  ],
                  items: [
                    for (final mode in SpeakReviewMode.values)
                      DropdownMenuItem<SpeakReviewMode>(
                        value: mode,
                        child: _formatMenuItem(mode),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) setState(() => _mode = mode);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formatMenuItem(
    SpeakReviewMode mode, {
    bool selected = false,
    bool showCheck = true,
  }) {
    return Row(
      children: [
        Icon(
          _modeIcon(mode),
          size: 19,
          color: selected ? SpeakColors.accent : SpeakColors.inkSoft,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _modeLabel(mode),
            style: DesignTokens.body(14, weight: FontWeight.w700).copyWith(
              color: selected ? SpeakColors.accent : SpeakColors.inkSoft,
            ),
          ),
        ),
        if (selected && showCheck)
          Icon(Icons.check_rounded, color: SpeakColors.accent, size: 18),
      ],
    );
  }

  Widget _planCard(
    BuildContext context,
    PersonalizedReviewPlan plan,
    List<ReviewSessionSummary> sessions,
    bool canStart,
    bool isWarmup,
  ) {
    final focusItems = _focusItems(plan);
    return Container(
      decoration: BoxDecoration(
        color: SpeakColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SpeakColors.line),
      ),
      // The accent is an attached edge of the card, as in the smart-review
      // generation state; clipping keeps it inside the rounded surface.
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: SpeakColors.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 19, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isWarmup
                              ? Icons.auto_awesome_rounded
                              : Icons.replay_rounded,
                          size: 18,
                          color: SpeakColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isWarmup
                              ? 'COURSE WINDOW PREVIEW'
                              : 'PERSONAL REVIEW',
                          style: DesignTokens.body(10, weight: FontWeight.w800)
                              .copyWith(
                                color: SpeakColors.accent,
                                letterSpacing: 1.35,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${plan.durationMinutes} min',
                          style: DesignTokens.body(
                            12,
                            weight: FontWeight.w700,
                          ).copyWith(color: SpeakColors.inkSoft),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Text(
                      isWarmup
                          ? 'Get ready for what’s next'
                          : 'Review what matters',
                      style: DesignTokens.display(24),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isWarmup
                          ? 'A short preview built from the next available Course lessons.'
                          : 'A focused lesson built from your recent Course and Practice history.',
                      style: DesignTokens.body(
                        13,
                      ).copyWith(color: SpeakColors.inkSoft, height: 1.35),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      isWarmup ? 'YOU’LL PREVIEW' : 'YOU’LL REVISIT',
                      style: DesignTokens.body(10, weight: FontWeight.w800)
                          .copyWith(
                            color: SpeakColors.inkSoft,
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in focusItems) ...[
                      _focusRow(item),
                      if (item != focusItems.last) const SizedBox(height: 7),
                    ],
                    if (focusItems.isEmpty)
                      Text(
                        plan.focusLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: SpeakColors.inkSoft),
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(
                          Icons.layers_outlined,
                          size: 16,
                          color: SpeakColors.inkSoft,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            isWarmup
                                ? 'Based on ${plan.futureSessionIds.length} upcoming Course lesson${plan.futureSessionIds.length == 1 ? '' : 's'}'
                                : '${sessions.length} recent sessions available',
                            style: DesignTokens.body(
                              11,
                            ).copyWith(color: SpeakColors.inkSoft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SpeakPrimaryButton(
                      label: isWarmup ? 'Start warm-up' : 'Start review',
                      icon: Icons.arrow_forward_rounded,
                      onTap: canStart
                          ? () => AppRouter.push(
                              context,
                              (_) => SpeakReviewLaunchScreen(
                                mode: _mode,
                                plan: plan,
                              ),
                              fullscreenDialog: true,
                            )
                          : null,
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

  List<String> _focusItems(PersonalizedReviewPlan plan) {
    if (plan.kind == 'warmup' && plan.futureLessonSummaries.isNotEmpty) {
      return plan.futureLessonSummaries.take(3).toList(growable: false);
    }
    final targetItems = plan.targets
        .map((target) => target.text.trim())
        .where((text) => text.isNotEmpty)
        .take(3)
        .toList(growable: false);
    if (targetItems.isNotEmpty) return targetItems;
    return [...plan.retrievalTargets, ...plan.hardSignals]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
  }

  Widget _focusRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.check_rounded, size: 15, color: SpeakColors.accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DesignTokens.body(13, weight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _recentPractice(List<ReviewSessionSummary> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Recent practice', style: DesignTokens.display(20)),
            ),
            if (sessions.isNotEmpty)
              Text(
                '${sessions.length} saved',
                style: DesignTokens.body(
                  11,
                  weight: FontWeight.w700,
                ).copyWith(color: SpeakColors.inkSoft),
              ),
          ],
        ),
        const SizedBox(height: 11),
        if (sessions.isEmpty)
          const SpeakCard(
            child: Text('Finish a practice session to build your review list.'),
          )
        else
          _sessionListCard(sessions, label: 'Open saved practice'),
      ],
    );
  }

  Widget _retrySavedPractice(List<ReviewSessionSummary> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Retry a saved session', style: DesignTokens.display(20)),
        const SizedBox(height: 6),
        Text(
          'Open the exercise details, then practise the same skill again.',
          style: DesignTokens.body(13).copyWith(color: SpeakColors.inkSoft),
        ),
        const SizedBox(height: 11),
        _sessionListCard(sessions, label: 'Open and practise again'),
      ],
    );
  }

  Widget _sessionListCard(
    List<ReviewSessionSummary> sessions, {
    required String label,
  }) {
    final visible = sessions.take(20).toList(growable: false);
    final height = visible.length <= 4 ? visible.length * 78.0 : 320.0;
    return Semantics(
      label: '$label, ${visible.length} sessions',
      child: SpeakCard(
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: height,
          child: ListView.separated(
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: visible.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: SpeakColors.line),
            itemBuilder: (context, index) => _materialRow(visible[index]),
          ),
        ),
      ),
    );
  }

  Widget _materialRow(ReviewSessionSummary session) {
    final isSpeaking = const {
      'Speaking',
      'Roleplay',
      'Exam speaking',
    }.contains(session.skill);
    return Semantics(
      button: true,
      label: 'Open saved ${session.skill} practice for ${session.displayTitle}',
      child: InkWell(
        onTap: () => AppRouter.push(
          context,
          (_) => isSpeaking
              ? SavedSpeakingTranscriptScreen(session: session)
              : SavedPracticeSessionScreen(session: session),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.displaySummary,
                style: DesignTokens.body(14, weight: FontWeight.w700),
              ),
              if (session.details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  session.details.first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ],
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
    SpeakReviewMode.smart => 'Smart',
    SpeakReviewMode.speaking => 'Speaking',
    SpeakReviewMode.listening => 'Listening',
    SpeakReviewMode.reading => 'Reading',
    SpeakReviewMode.writing => 'Writing',
  };

  IconData _modeIcon(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.smart => Icons.auto_awesome_rounded,
    SpeakReviewMode.speaking => Icons.mic_rounded,
    SpeakReviewMode.listening => Icons.headphones_rounded,
    SpeakReviewMode.reading => Icons.menu_book_rounded,
    SpeakReviewMode.writing => Icons.edit_rounded,
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

/// Read-only history surface for every non-speaking session.  Course rows
/// used to be headings only; the Review projection now supplies the saved
/// turns and generated activity payload so a learner can verify what they
/// actually practised before choosing to retry it.
class SavedPracticeSessionScreen extends ConsumerWidget {
  const SavedPracticeSessionScreen({super.key, required this.session});

  final ReviewSessionSummary session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageServiceProvider);
    final messages = storage.getSessionMessages(sessionId: session.sessionId);
    final details = session.details;
    final turnsAlreadyIncluded = details.any(
      (value) => value.startsWith('Learner:') || value.startsWith('Tutor:'),
    );
    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: DesignTokens.nightText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Saved practice',
                      style: DesignTokens.display(
                        21,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                  ),
                  Text(
                    session.skill,
                    style: DesignTokens.body(
                      12,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightAccent),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(
                    session.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.display(
                      25,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.displaySummary,
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.nightMuted),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'WHAT YOU PRACTISED',
                    style: DesignTokens.body(11, weight: FontWeight.w800)
                        .copyWith(
                          color: DesignTokens.nightAccent,
                          letterSpacing: 1.4,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (details.isEmpty && messages.isEmpty)
                    _detailCard('No saved exercise details for this session.')
                  else ...[
                    for (final detail in details) ...[
                      _detailCard(detail),
                      const SizedBox(height: 8),
                    ],
                    if (messages.isNotEmpty && !turnsAlreadyIncluded) ...[
                      const SizedBox(height: 4),
                      Text(
                        'SAVED TURNS',
                        style: DesignTokens.body(11, weight: FontWeight.w800)
                            .copyWith(
                              color: DesignTokens.nightAccent,
                              letterSpacing: 1.4,
                            ),
                      ),
                      const SizedBox(height: 8),
                      for (final message in messages.take(20)) ...[
                        _detailCard(
                          '${message.isUser ? 'Learner' : 'Tutor'}: ${message.content}',
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => AppRouter.push(
                        context,
                        (_) => SpeakReviewScreen(
                          initialMode: _modeFor(session.skill),
                        ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: DesignTokens.nightSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: DesignTokens.nightHairline),
    ),
    child: Text(
      text,
      style: DesignTokens.body(13).copyWith(color: DesignTokens.nightText),
    ),
  );

  SpeakReviewMode _modeFor(String skill) => switch (skill.toLowerCase()) {
    'reading' || 'exam reading' => SpeakReviewMode.reading,
    'listening' || 'exam listening' => SpeakReviewMode.listening,
    'writing' || 'exam writing' => SpeakReviewMode.writing,
    'speaking' || 'roleplay' || 'exam speaking' => SpeakReviewMode.speaking,
    _ => SpeakReviewMode.smart,
  };
}

/// Generates the selected review format from the universal learner snapshot,
/// then hands off to the same lesson screens used everywhere else.
class SpeakReviewLaunchScreen extends ConsumerStatefulWidget {
  const SpeakReviewLaunchScreen({
    super.key,
    required this.mode,
    required this.plan,
  });

  final SpeakReviewMode mode;
  final PersonalizedReviewPlan plan;

  @override
  ConsumerState<SpeakReviewLaunchScreen> createState() =>
      _SpeakReviewLaunchScreenState();
}

class _SpeakReviewLaunchScreenState
    extends ConsumerState<SpeakReviewLaunchScreen> {
  String? _error;
  bool _running = false;
  String? _planId;
  String? _attemptId;

  @override
  void initState() {
    super.initState();
    unawaited(_launch());
  }

  Future<void> _launch() async {
    if (_running) return;
    _running = true;
    try {
      final store = ref.read(reviewStoreProvider);
      _planId ??= store.createPlan(
        kind: widget.plan.kind,
        requestedMode: widget.plan.requestedMode,
        resolvedMode: widget.plan.mode,
        levelBand: widget.plan.levelBand,
        goal: widget.plan.learnerGoal,
        durationMinutes: widget.plan.durationMinutes,
        topic: widget.plan.topic,
        sourceFingerprint: widget.plan.snapshot.fingerprint,
        brief: widget.plan.briefJson,
      );
      // Review-only intelligence runs after the durable plan exists. If the
      // model call fails, the Review route reports the failure, while Course,
      // Practice, and their already-saved evidence remain untouched.
      final blueprint = await LessonAgentService.shared.composeReviewBlueprint(
        plan: widget.plan,
      );
      final effectiveMode = _resolvedMode(widget.mode);
      final teachingContext = _teachingContext(blueprint);
      store.updateResolvedMode(_planId!, blueprint.mode);
      store.markGenerated(_planId!, {
        'kind': widget.plan.kind,
        'mode': blueprint.mode,
        'composer': blueprint.toJson(),
        'composerInput': {
          'provider': 'openrouter',
          'model': 'openai/gpt-5.6-luna',
          'requestedMode': widget.plan.requestedMode,
          'resolvedModeBeforeComposer': widget.plan.mode,
          'sourceFingerprint': widget.plan.snapshot.fingerprint,
          'sourceSessionIds': widget.plan.sourceSessionIds
              .take(24)
              .toList(growable: false),
          'recentSessionCount': widget.plan.snapshot.evidence.length,
          'transcriptExcerptCount':
              widget.plan.snapshot.transcriptExcerpts.length,
          'vocabularySignalCount':
              widget.plan.snapshot.vocabularySignals.length,
          'performanceSignalCount':
              widget.plan.snapshot.performanceSignals.length,
          'repeatedMistakeCount': widget.plan.snapshot.repeatedMistakes.length,
          'dossierPolicy': 'recent-session-scoped; optional evidence trimmed',
        },
        'sourceFingerprint': widget.plan.snapshot.fingerprint,
      });
      _attemptId ??= store.startAttempt(planId: _planId!, mode: blueprint.mode);
      switch (effectiveMode) {
        case SpeakReviewMode.smart:
          await _startSmartReview(
            blueprint: blueprint,
            teachingContext: teachingContext,
          );
        case SpeakReviewMode.speaking:
          await _startSpeakingReview(blueprint: blueprint);
        case SpeakReviewMode.listening:
          final story = await _generateStory(
            listening: true,
            teachingContext: teachingContext,
            topic: blueprint.topic,
          );
          if (!mounted) return;
          await AppRouter.push(
            context,
            (_) => ListeningPracticeScreen(story: story),
            fullscreenDialog: true,
          );
        case SpeakReviewMode.reading:
          final story = await _generateStory(
            listening: false,
            teachingContext: teachingContext,
            topic: blueprint.topic,
          );
          if (!mounted) return;
          await AppRouter.push(
            context,
            (_) => StoryReaderScreen(story: story),
            fullscreenDialog: true,
          );
        case SpeakReviewMode.writing:
          await _openWritingReview(
            blueprint: blueprint,
            teachingContext: teachingContext,
          );
      }
      if (_attemptId != null) {
        store.completeAttempt(_attemptId!);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Review launch failed: $error\n$stackTrace');
      if (_planId != null) {
        ref.read(reviewStoreProvider).markPlanFailed(_planId!, error);
      }
      if (mounted) {
        setState(() {
          _running = false;
          _error = 'Review generation failed: $error';
        });
      }
    }
  }

  Future<void> _startSmartReview({
    required ReviewBlueprint blueprint,
    required String teachingContext,
  }) async {
    // Smart Review is one transaction. Prepare each child lesson once, then
    // pass the immutable artifacts into the sequence screen. Tapping a block
    // later can only open an existing artifact; it can never generate another
    // story or listening lesson.
    final readingFuture = _generateStory(
      listening: false,
      teachingContext: teachingContext,
      topic: blueprint.topic,
    );
    final listeningFuture = _generateStory(
      listening: true,
      teachingContext: teachingContext,
      topic: blueprint.topic,
    );
    final writingFuture = _generateWritingReview(
      blueprint: blueprint,
      teachingContext: teachingContext,
    );
    final reading = await readingFuture;
    final listening = await listeningFuture;
    final writing = await writingFuture;
    if (!mounted) return;
    await AppRouter.push(
      context,
      (_) => SmartReviewLessonScreen(
        blueprint: blueprint,
        reading: reading,
        listening: listening,
        writing: writing,
        onSpeaking: () => _openGuidedSpeaking(blueprint),
        onReading: () => _openReadingStory(reading),
        onListening: () => _openListeningStory(listening),
        onWriting: () => _openWritingLesson(writing),
      ),
      fullscreenDialog: true,
    );
  }

  Future<bool> _openWritingReview({
    required ReviewBlueprint blueprint,
    required String teachingContext,
  }) async {
    final lesson = await _generateWritingReview(
      blueprint: blueprint,
      teachingContext: teachingContext,
    );
    return _openWritingLesson(lesson);
  }

  Future<WritingCourseLesson> _generateWritingReview({
    required ReviewBlueprint blueprint,
    required String teachingContext,
  }) async {
    final profile = ref.read(learningStoreProvider).profile();
    final level = _levelFor(profile.level);
    final learningStore = ref.read(learningStoreProvider);
    final content = ref.read(contentServiceProvider);
    final currentLessons = ref
        .read(writingLessonStoreProvider)
        .list(level: level);
    final lesson = await ref
        .read(lessonAgentServiceProvider)
        .generateWritingCourseLesson(
          mode: WritingCourseMode.guided,
          levelBand: level,
          learnerGoal: profile.goal,
          interests: profile.interests,
          knownVocab: content.knownVocabWords(learningStore.allSRSStates()),
          mistakeTags: [
            for (final mistake in learningStore.topMistakeTags(limit: 5))
              (
                tag: mistake.tag,
                description: mistake.description,
                count: mistake.count,
              ),
          ],
          avoidTitles: [
            ...currentLessons.map((item) => item.title),
            blueprint.title,
          ],
          contextPrompt: teachingContext,
        );
    // Keep the validated Course lesson in the same durable Writing catalog as
    // every other generated Course lesson. The review ledger separately
    // records that this artifact was created for this Review attempt.
    ref.read(writingLessonStoreProvider).insertGenerated(lesson);
    if (_planId != null) {
      ref.read(reviewStoreProvider).markGenerated(_planId!, {
        'kind': widget.plan.kind,
        'mode': 'writing',
        'topic': blueprint.topic,
        'activityId': lesson.id,
        'courseLesson': lesson.toJson(),
        'sourceFingerprint': widget.plan.snapshot.fingerprint,
      });
    }
    return lesson;
  }

  Future<bool> _openWritingLesson(WritingCourseLesson lesson) async {
    if (!mounted) return false;
    final result = await AppRouter.push<bool>(
      context,
      (_) => WritingCourseLessonScreen(lesson: lesson),
      fullscreenDialog: true,
    );
    return result == true;
  }

  Future<bool> _openReadingStory(GeneratedStory story) async {
    if (!mounted) return false;
    final result = await AppRouter.push<StoryReaderResult>(
      context,
      (_) => StoryReaderScreen(
        story: story,
        showFinishButton: true,
        generateCoverIfMissing: true,
      ),
      fullscreenDialog: true,
    );
    return result != null;
  }

  Future<bool> _openListeningStory(GeneratedStory story) async {
    if (!mounted) return false;
    final result = await AppRouter.push<bool>(
      context,
      (_) => ListeningPracticeScreen(
        story: story,
        showFinishButton: true,
        courseContentKey: 'review_listening_${story.id}',
      ),
      fullscreenDialog: true,
    );
    return result == true;
  }

  Future<bool> _openGuidedSpeaking(ReviewBlueprint blueprint) async {
    final profile = ref.read(learningStoreProvider).profile();
    final level = _levelFor(profile.level);
    final steps = speakingStepsForReviewTargets(
      blueprint.speakingTargets.map(
        (target) =>
            (french: target.french, english: target.english, tip: target.tip),
      ),
      level: level,
    );
    if (!mounted) return false;
    final result = await AppRouter.push<SpeakingResult>(
      context,
      (_) => SpeakingLessonFlowScreen(
        title: blueprint.title,
        topic: blueprint.topic,
        level: level,
        contentKey: 'review_speaking_${DateTime.now().microsecondsSinceEpoch}',
        steps: steps,
      ),
      fullscreenDialog: true,
    );
    return result?.connected == true;
  }

  String _teachingContext(ReviewBlueprint blueprint) {
    return '''
${widget.plan.contextPrompt}

${blueprint.teachingContext}
''';
  }

  Future<GeneratedStory> _generateStory({
    required bool listening,
    required String teachingContext,
    required String topic,
  }) async {
    final profile = ref.read(learningStoreProvider).profile();
    final level = _levelFor(profile.level);
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
            contextPrompt: teachingContext,
            avoidTitles: avoidTitles,
            avoidOpenings: avoidOpenings,
          )
        : await LessonAgentService.shared.buildReadingStoryBook(
            topic: topic,
            levelBand: level,
            contextPrompt: teachingContext,
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
    if (_planId != null) {
      ref.read(reviewStoreProvider).markGenerated(_planId!, {
        'kind': widget.plan.kind,
        'mode': listening ? 'listening' : 'reading',
        'activityId': story.id,
        'title': story.title,
        'topic': story.topic,
        'sourceFingerprint': widget.plan.snapshot.fingerprint,
      });
    }
    unawaited(_prewarmStory(story));
    unawaited(_attachStoryCover(story, package.coverPrompt));
    return story;
  }

  Future<void> _prewarmStory(GeneratedStory story) async {
    // This runs only inside the explicit “generate review” transaction. It
    // creates the durable sentence deck once; opening/replaying the story is
    // cache-only and never reaches Gemini.
    await LessonAudioDeckService.shared.prepare(
      story: story,
      db: ref.read(databaseProvider),
    );
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

  Future<void> _startSpeakingReview({
    required ReviewBlueprint blueprint,
  }) async {
    if (_planId != null) {
      ref.read(reviewStoreProvider).markGenerated(_planId!, {
        'kind': widget.plan.kind,
        'mode': 'speaking',
        'topic': widget.plan.topic,
        'sourceFingerprint': widget.plan.snapshot.fingerprint,
      });
    }
    await _openGuidedSpeaking(blueprint);
  }

  SpeakReviewMode _resolvedMode(SpeakReviewMode requested) {
    // The local planner owns the route. In particular, Smart must never be
    // reinterpreted as Speaking merely because the model included speaking
    // targets in the mixed blueprint.
    if (requested == SpeakReviewMode.smart) return SpeakReviewMode.smart;
    return requested;
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
            title: widget.plan.kind == 'warmup'
                ? 'Building warm-up'
                : 'Building review',
            subtitle: widget.plan.kind == 'warmup'
                ? 'Previewing the next Course lesson.'
                : 'Using your recent practice material.',
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: SpeakColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: SpeakColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 5, color: SpeakColors.accent),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
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
                                      'Preparing ${_modeLabel(widget.mode).toLowerCase()} ${widget.plan.kind == 'warmup' ? 'warm-up' : 'review'}…',
                                  style: DesignTokens.display(22),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _error == null
                                      ? 'Hard spots and recent language are being woven into a fresh lesson.'
                                      : 'Your recent practice is still safe. You can retry this review.',
                                  style: DesignTokens.body(13).copyWith(
                                    color: SpeakColors.inkSoft,
                                    height: 1.35,
                                  ),
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
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
    SpeakReviewMode.smart => 'Smart',
    SpeakReviewMode.speaking => 'Speaking',
    SpeakReviewMode.listening => 'Listening',
    SpeakReviewMode.reading => 'Reading',
    SpeakReviewMode.writing => 'Writing',
  };

  IconData _modeIcon(SpeakReviewMode mode) => switch (mode) {
    SpeakReviewMode.smart => Icons.auto_awesome_rounded,
    SpeakReviewMode.speaking => Icons.mic_rounded,
    SpeakReviewMode.listening => Icons.headphones_rounded,
    SpeakReviewMode.reading => Icons.menu_book_rounded,
    SpeakReviewMode.writing => Icons.edit_rounded,
  };
}
