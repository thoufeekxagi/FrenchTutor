import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speak_curriculum.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/starter_cover_resolver.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/vocab_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import '../session/session_screen.dart';
import 'speak_course_activity_screen.dart';
import 'speak_profile_screen.dart';
import 'speak_review_screen.dart';
import 'speak_settings_screen.dart';
import 'speaking_practice_screen.dart';

/// Speaking Studio: a compact next-action surface over the existing course/session
/// data flow. The redesign changes hierarchy and presentation only.
class SpeakingStudioScreen extends ConsumerStatefulWidget {
  const SpeakingStudioScreen({super.key});

  @override
  ConsumerState<SpeakingStudioScreen> createState() =>
      _SpeakingStudioScreenState();
}

class _SpeakingStudioScreenState extends ConsumerState<SpeakingStudioScreen> {
  Future<void> _openSession(SpeakRoadmapSession session) async {
    await AppRouter.push(
      context,
      (_) => SpeakCourseActivityScreen(session: session),
    );
    if (mounted) setState(() {});
  }

  Future<void> _callTutor() async {
    if (!await ensureAiSessionQuota(
          context,
          ref.read(pilotAccessServiceProvider),
        ) ||
        !mounted) {
      return;
    }
    LessonSpeechService.shared.deactivate();
    await AppRouter.push(
      context,
      (_) => const SessionScreen(
        apiKey: ApiKeys.geminiKey,
        stage: 'free_talk',
        sessionTopic: 'Free conversation',
        lessonContext:
            'Have a natural French conversation with the learner. Do not force '
            'a preset scenario or topic. Let the learner choose what to talk '
            'about, respond warmly and concisely, and offer a brief correction '
            'only when it helps.',
      ),
      fullscreenDialog: true,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final completedContentKeys = ref
        .watch(storageServiceProvider)
        .completedContentKeys();
    final adaptivePlan = ref
        .read(adaptiveCourseStoreProvider)
        .ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      completedContentKeys: completedContentKeys,
      adaptiveSessions: adaptivePlan.sessions,
    );
    final next = roadmap.nextSession ?? roadmap.sessions.first;
    final lessonCards = _lessonCards(roadmap, next);
    final upcoming = lessonCards
        .where((session) => session.contentKey != next.contentKey)
        .take(2)
        .toList(growable: false);
    final tutor = ActiveTutor.current;

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          children: [
            _header(context, roadmap.trackLabel, tutor),
            const SizedBox(height: 16),
            _continueRail(context, next),
            const SizedBox(height: 28),
            Text('GOOD MORNING', style: _eyebrow()),
            const SizedBox(height: 5),
            Text('Your next conversation', style: _display(27)),
            const SizedBox(height: 12),
            _nextConversationCard(next),
            const SizedBox(height: 24),
            Text('QUICK START', style: _eyebrow()),
            const SizedBox(height: 10),
            _quickStartRow(context, next),
            const SizedBox(height: 26),
            _progressSignal(roadmap),
            const SizedBox(height: 26),
            Text('YOUR PATH', style: _eyebrow()),
            const SizedBox(height: 10),
            _upcomingList(upcoming),
            const SizedBox(height: 26),
            Text('EXPLORE', style: _eyebrow()),
            const SizedBox(height: 10),
            _modeRail(context, next.primarySkill),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String trackLabel, TutorPersona tutor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Marcus Speak', style: _display(25)),
              const SizedBox(height: 3),
              Text(
                '$trackLabel  ·  Tutor ${tutor.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _body(12, color: DesignTokens.nightMuted),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: 'Open speaking settings',
          child: IconButton(
            tooltip: 'Speaking settings',
            onPressed: () =>
                AppRouter.push(context, (_) => const SpeakSettingsScreen()),
            icon: const Icon(
              Icons.tune_rounded,
              color: DesignTokens.nightAccent,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Semantics(
          button: true,
          label: 'Open profile',
          child: GestureDetector(
            onTap: () =>
                AppRouter.push(context, (_) => const SpeakProfileScreen()),
            child: Container(
              width: 42,
              height: 42,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: DesignTokens.nightAccent, width: 1.5),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: DesignTokens.nightAccent,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _eyebrow() => DesignTokens.body(
    11,
    weight: FontWeight.w700,
  ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.2);

  Widget _continueRail(BuildContext context, SpeakRoadmapSession next) {
    final items = [
      ('Continue', Icons.play_arrow_rounded, true, () => _openSession(next)),
      (
        'Speaking',
        Icons.mic_none_rounded,
        false,
        () => AppRouter.push(context, (_) => const SpeakingPracticeScreen()),
      ),
      (
        'Writing',
        Icons.edit_note_rounded,
        false,
        () => AppRouter.push(context, (_) => const WritingLabScreen()),
      ),
      (
        'Reading',
        Icons.menu_book_rounded,
        false,
        () => AppRouter.push(context, (_) => const ReadingLibraryScreen()),
      ),
      (
        'Listening',
        Icons.headphones_rounded,
        false,
        () => AppRouter.push(context, (_) => const ListeningLabScreen()),
      ),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, icon, selected, onTap) = items[index];
          return _ModePill(
            label: label,
            icon: icon,
            selected: selected,
            onTap: onTap,
          );
        },
      ),
    );
  }

  Widget _nextConversationCard(SpeakRoadmapSession session) {
    final goal = session.subtitle.trim().isEmpty
        ? session.primarySkill.description
        : session.subtitle;
    return Semantics(
      button: true,
      label: 'Continue ${session.title}',
      child: GestureDetector(
        onTap: () => _openSession(session),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 278,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(_coverAsset(session), fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 17, 17, 17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('NEXT UP', style: _eyebrow()),
                          const Spacer(),
                          Text(
                            '${session.estimatedMinutes} MINUTES',
                            style: _body(
                              11,
                              color: DesignTokens.nightText,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        session.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _display(28),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        goal,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _body(
                          14,
                          color: DesignTokens.nightText.withValues(alpha: 0.84),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            '${session.level}  ·  ${session.primarySkill.label}',
                            style: _body(12, color: DesignTokens.nightMuted),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: DesignTokens.nightAccent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'Continue  →',
                              style: _body(
                                12,
                                color: Colors.black,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeRail(BuildContext context, SpeakSkill selectedSkill) {
    final selected = switch (selectedSkill) {
      SpeakSkill.reading => SpeakSkill.reading,
      SpeakSkill.vocabulary => SpeakSkill.vocabulary,
      SpeakSkill.listening => SpeakSkill.listening,
      _ => null,
    };
    final modes = [
      (
        'Listening',
        SpeakSkill.listening,
        Icons.headphones_rounded,
        const ListeningLabScreen(),
      ),
      (
        'Reading',
        SpeakSkill.reading,
        Icons.menu_book_rounded,
        const ReadingLibraryScreen(),
      ),
      (
        'Vocabulary',
        SpeakSkill.vocabulary,
        Icons.style_rounded,
        const VocabLabScreen(),
      ),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: modes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, skill, icon, destination) = modes[index];
          return _ModePill(
            label: label,
            icon: icon,
            selected: skill == selected,
            onTap: () => AppRouter.push(context, (_) => destination),
          );
        },
      ),
    );
  }

  Widget _quickStartRow(BuildContext context, SpeakRoadmapSession next) {
    return Row(
      children: [
        Expanded(
          child: _QuickStartCard(
            icon: Icons.mic_none_rounded,
            label: 'Warm up',
            detail: 'One phrase',
            onTap: () => _openSession(next),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickStartCard(
            icon: Icons.phone_in_talk_rounded,
            label: 'Free talk',
            detail: 'Choose a topic',
            onTap: _callTutor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickStartCard(
            icon: Icons.replay_rounded,
            label: 'Review',
            detail: 'Bring it back',
            onTap: () =>
                AppRouter.push(context, (_) => const SpeakReviewScreen()),
          ),
        ),
      ],
    );
  }

  Widget _progressSignal(SpeakRoadmap roadmap) {
    final total = roadmap.sessions.length;
    final progress = roadmap.progress.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_rounded,
                color: DesignTokens.nightAccent,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Your speaking path',
                  style: _body(15, weight: FontWeight.w700),
                ),
              ),
              Text(
                '${roadmap.completedCount}/$total scenes',
                style: _body(12, color: DesignTokens.nightMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: DesignTokens.nightHairline,
              valueColor: const AlwaysStoppedAnimation<Color>(
                DesignTokens.nightAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingList(List<SpeakRoadmapSession> sessions) {
    if (sessions.isEmpty) {
      return Text(
        'Your next scene will appear here after this one.',
        style: _body(13, color: DesignTokens.nightMuted),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < sessions.length; index++) ...[
          _UpcomingSessionRow(
            session: sessions[index],
            onTap: () => _openSession(sessions[index]),
          ),
          if (index != sessions.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  List<SpeakRoadmapSession> _lessonCards(
    SpeakRoadmap roadmap,
    SpeakRoadmapSession next,
  ) {
    final cards = roadmap.sessions
        .where((session) => session.index >= next.index)
        .take(3)
        .toList(growable: true);
    for (final session in roadmap.sessions) {
      if (cards.length == 3) break;
      if (!cards.contains(session)) cards.add(session);
    }
    return cards;
  }

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) => DesignTokens.body(
    size,
    weight: weight,
  ).copyWith(color: color ?? DesignTokens.nightText);
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected
                ? DesignTokens.nightAccentSoft
                : DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightHairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: DesignTokens.body(12, weight: FontWeight.w600).copyWith(
                  color: selected
                      ? DesignTokens.nightAccent
                      : DesignTokens.nightMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $detail',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 94),
          padding: const EdgeInsets.fromLTRB(11, 12, 9, 11),
          decoration: BoxDecoration(
            color: DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: DesignTokens.nightAccent, size: 20),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w700,
                ).copyWith(color: DesignTokens.nightText),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  10,
                ).copyWith(color: DesignTokens.nightMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingSessionRow extends StatelessWidget {
  const _UpcomingSessionRow({required this.session, required this.onTap});

  final SpeakRoadmapSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open ${session.title}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  _coverAsset(session),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        14,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.nightText),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${session.level}  ·  ${session.primarySkill.label}  ·  ${session.estimatedMinutes} min',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: DesignTokens.nightAccent,
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _coverAsset(SpeakRoadmapSession session) {
  final resolved = StarterCoverResolver.resolve(title: session.title);
  if (resolved != null && resolved.startsWith('asset:')) {
    return resolved.substring('asset:'.length);
  }
  return switch (session.index % 4) {
    0 => 'assets/starter_covers/market.png',
    1 => 'assets/starter_covers/station.png',
    2 => 'assets/starter_covers/lantern.png',
    _ => 'assets/starter_covers/boat.png',
  };
}
