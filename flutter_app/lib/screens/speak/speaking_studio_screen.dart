import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/session.dart';
import '../../models/speak_curriculum.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/course_generation_test_harness.dart';
import '../../services/free_talk_session_launcher.dart';
import '../../services/learning_streak_service.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/starter_cover_resolver.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/vocab_lab_screen.dart';
import '../labs/writing_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import 'speak_course_activity_screen.dart';
import 'speak_review_screen.dart';
import 'speaking_flow_screen.dart';
import 'speak_profile_screen.dart';
import 'speak_settings_screen.dart';

/// Speaking Studio: a compact next-action surface over the existing course/session
/// data flow. The redesign changes hierarchy and presentation only.
class SpeakingStudioScreen extends ConsumerStatefulWidget {
  const SpeakingStudioScreen({super.key});

  @override
  ConsumerState<SpeakingStudioScreen> createState() =>
      _SpeakingStudioScreenState();
}

class _SpeakingStudioScreenState extends ConsumerState<SpeakingStudioScreen> {
  var _carouselPage = 0;
  List<Session> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureUpcomingMedia();
    });
  }

  void _loadSessions() {
    final sessions = ref.read(storageServiceProvider).getAllSessions();
    if (mounted) setState(() => _sessions = sessions);
  }

  /// Home is also a valid entry point to Course, so do not wait for the
  /// roadmap screen to be opened before filling the unit's Reading and
  /// Listening buffer. The work is idempotent and guarded by SyncService's
  /// single in-flight generation gate.
  Future<void> _ensureUpcomingMedia() async {
    // The debug generation harness intentionally serializes one selected
    // skill; Home must not consume that lane with ordinary media requests.
    if (CourseGenerationTestHarness.current.active) return;
    final sync = ref.read(syncServiceProvider);
    try {
      await sync.hydrateAdaptiveCourses();
      if (!mounted) return;
      final profile = ref.read(learningStoreProvider).profile();
      final store = ref.read(adaptiveCourseStoreProvider);
      var plan = store.ensureMediaBuffer(profile);
      await sync.syncAdaptiveCoursePlan(plan);
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!mounted) return;
        final sessions = plan.sessions;
        final units =
            sessions
                .where((session) => session.unit >= 3)
                .map((session) => session.unit)
                .toSet()
                .toList()
              ..sort();
        final ready = units.any((unit) {
          final unitSessions = sessions.where((s) => s.unit == unit);
          final reading = unitSessions.where(
            (s) => s.primarySkill == SpeakSkill.reading,
          );
          final listening = unitSessions.where(
            (s) => s.primarySkill == SpeakSkill.listening,
          );
          return reading.isNotEmpty &&
              listening.isNotEmpty &&
              reading.every(
                (s) => s.status == 'completed' || s.isContentReady,
              ) &&
              listening.every(
                (s) => s.status == 'completed' || s.isContentReady,
              );
        });
        if (ready) break;
        final prepared = await sync.prepareAdaptiveCourseLessons();
        if (prepared == 0) break;
        await sync.hydrateAdaptiveCourses();
        plan = store.ensureMediaBuffer(profile);
      }
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      // Home remains usable offline; the next foreground/reopen pass can
      // resume the same queued rows later.
      debugPrint('Home media buffer preparation failed: $error\n$stackTrace');
    }
  }

  Future<void> _openSession(SpeakRoadmapSession session) async {
    await AppRouter.push(
      context,
      (_) => SpeakCourseActivityScreen(session: session),
    );
    if (mounted) {
      _loadSessions();
      setState(() {});
      unawaited(_ensureUpcomingMedia());
    }
  }

  Future<void> _callTutor() async {
    await openFreeTalkSession(context, ref);
    if (mounted) {
      _loadSessions();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final completedContentKeys = ref
        .watch(storageServiceProvider)
        .completedContentKeys();
    // Home normally reads the plan prepared by onboarding/auth hydration. A
    // missing or stale plan is a recoverable startup state, though: older
    // plans use the pre-evidence fingerprint and must be refreshed before the
    // roadmap can safely be rendered.
    final adaptiveStore = ref.read(adaptiveCourseStoreProvider);
    final adaptivePlan =
        adaptiveStore.currentPlan(profile) ??
        adaptiveStore.ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      completedContentKeys: completedContentKeys,
      adaptiveSessions: adaptivePlan.sessions,
      generationHarness: CourseGenerationTestHarness.current,
    );
    final next = roadmap.nextSession;
    final lessonCards = _lessonCards(roadmap);
    final courseSessions = _courseSessions(roadmap);
    final tutor = ActiveTutor.current;

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          children: [
            _header(context, roadmap.trackLabel, tutor),
            const SizedBox(height: 28),
            Text('GOOD MORNING', style: _eyebrow()),
            const SizedBox(height: 5),
            Text('Your next session', style: _display(27)),
            const SizedBox(height: 12),
            _continueCarousel(lessonCards),
            if (lessonCards.length > 1) ...[
              const SizedBox(height: 8),
              _carouselDots(lessonCards.length),
            ],
            const SizedBox(height: 24),
            Text('QUICK START', style: _eyebrow()),
            const SizedBox(height: 10),
            _quickStartRow(context),
            const SizedBox(height: 26),
            _weeklyStreak(),
            const SizedBox(height: 26),
            Text('YOUR COURSE', style: _eyebrow()),
            const SizedBox(height: 10),
            _courseList(courseSessions),
            const SizedBox(height: 26),
            Text('EXPLORE', style: _eyebrow()),
            const SizedBox(height: 10),
            _modeRail(context, next?.primarySkill ?? SpeakSkill.speaking),
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
              Text('Home', style: _display(25)),
              const SizedBox(height: 3),
              Text(
                'French  ·  Tutor ${tutor.displayName}',
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
            icon: Icon(
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
              child: Icon(
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

  Widget _continueCarousel(List<SpeakRoadmapSession> sessions) {
    if (sessions.isEmpty) {
      return _nextConversationCard(null);
    }
    return SizedBox(
      height: 278,
      child: PageView.builder(
        itemCount: sessions.length,
        onPageChanged: (page) => setState(() => _carouselPage = page),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(right: 1),
          child: _nextConversationCard(sessions[index]),
        ),
      ),
    );
  }

  Widget _carouselDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: DesignTokens.durationFast,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: index == _carouselPage ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: index == _carouselPage
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightHairline,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }

  Widget _nextConversationCard(SpeakRoadmapSession? session) {
    if (session == null) {
      return Container(
        height: 278,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Text(
          'Your next lesson will appear here.',
          style: _body(14, color: DesignTokens.nightMuted),
        ),
      );
    }
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
      SpeakSkill.speaking => SpeakSkill.speaking,
      SpeakSkill.writing => SpeakSkill.writing,
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
      (
        'Speaking',
        SpeakSkill.speaking,
        Icons.graphic_eq_rounded,
        const SpeakingHubScreen(),
      ),
      (
        'Writing',
        SpeakSkill.writing,
        Icons.edit_note_rounded,
        const WritingLabScreen(),
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

  Widget _quickStartRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickStartCard(
            icon: Icons.rate_review_rounded,
            label: 'Review',
            detail: 'Past lessons',
            onTap: () =>
                AppRouter.push(context, (_) => const SpeakReviewScreen()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickStartCard(
            icon: Icons.auto_awesome_rounded,
            label: 'Warm-up',
            detail: 'Next lesson',
            onTap: () => AppRouter.push(
              context,
              (_) => const SpeakReviewScreen(kind: 'warmup'),
            ),
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
      ],
    );
  }

  Widget _weeklyStreak() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekDays = List.generate(
      7,
      (index) => monday.add(Duration(days: index)),
    );
    final streak = LearningStreakService.summarize(_sessions, now: now);
    final completedDays = weekDays.where(streak.isActiveOn).length;
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      // Keep the accent attached to the card edge and clipped to its rounded
      // corners. Without this, the negative inset below can paint outside the
      // surface and make the rail look detached from the model card.
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: -16,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: DesignTokens.nightAccent),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    color: DesignTokens.nightAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Keep your practice going',
                      style: _body(15, weight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '$completedDays of 7 days',
                    style: _body(12, color: DesignTokens.nightMuted),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Complete one session each day',
                style: _body(12, color: DesignTokens.nightMuted),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var index = 0; index < weekDays.length; index++)
                    _streakDay(
                      label: labels[index],
                      active: streak.isActiveOn(weekDays[index]),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _streakDay({required String label, required bool active}) {
    return Column(
      children: [
        Text(label, style: _body(11, color: DesignTokens.nightMuted)),
        const SizedBox(height: 6),
        Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: active ? DesignTokens.nightAccent : Colors.transparent,
            shape: BoxShape.circle,
            border: active
                ? null
                : Border.all(color: DesignTokens.nightMuted, width: 1.5),
          ),
          child: active
              ? const Icon(Icons.check_rounded, color: Colors.black, size: 18)
              : null,
        ),
      ],
    );
  }

  List<SpeakRoadmapSession> _courseSessions(SpeakRoadmap roadmap) {
    const imageBacked = {SpeakSkill.reading, SpeakSkill.listening};
    return roadmap.sessions
        .where(
          (session) =>
              !session.completed &&
              session.contentReady &&
              !imageBacked.contains(session.primarySkill),
        )
        .take(2)
        .toList(growable: false);
  }

  Widget _courseList(List<SpeakRoadmapSession> sessions) {
    if (sessions.isEmpty) {
      return Text(
        'Your next course lessons will appear here.',
        style: _body(13, color: DesignTokens.nightMuted),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      // Match the smart-generation card: the rail is part of the surface,
      // not a separately painted decoration around it.
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: DesignTokens.nightAccent),
          ),
          Column(
            children: [
              for (var index = 0; index < sessions.length; index++) ...[
                _CourseSessionRow(
                  session: sessions[index],
                  onTap: () => _openSession(sessions[index]),
                ),
                if (index != sessions.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 62),
                    child: Container(
                      height: 1,
                      color: DesignTokens.nightHairline,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// The hero carousel is reserved for the two image-backed lesson types.
  ///
  /// Grammar, speaking, writing, and the other generated activities remain in
  /// Course/Practice. Keeping them out of this carousel prevents a lesson
  /// without artwork from being presented as an image-led Home destination.
  List<SpeakRoadmapSession> _lessonCards(SpeakRoadmap roadmap) {
    final cards = <SpeakRoadmapSession>[];
    for (final skill in const [SpeakSkill.reading, SpeakSkill.listening]) {
      SpeakRoadmapSession? nextForSkill;
      for (final session in roadmap.sessions) {
        if (session.primarySkill == skill &&
            !session.completed &&
            session.contentReady) {
          nextForSkill = session;
          break;
        }
      }
      if (nextForSkill != null) cards.add(nextForSkill);
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
          // The card lives inside Home's vertical ListView, whose children
          // receive an unbounded height. Give the internal Spacer a finite
          // height to avoid the RenderFlex/viewport assertion cascade.
          height: 94,
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

class _CourseSessionRow extends StatelessWidget {
  const _CourseSessionRow({required this.session, required this.onTap});

  final SpeakRoadmapSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open ${session.title}',
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
          child: Row(
            children: [
              Icon(
                _courseIcon(session.primarySkill),
                color: DesignTokens.nightAccent,
                size: 23,
              ),
              const SizedBox(width: 13),
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
                    const SizedBox(height: 4),
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
              Icon(
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

IconData _courseIcon(SpeakSkill skill) => switch (skill) {
  SpeakSkill.vocabulary => Icons.style_rounded,
  SpeakSkill.grammar => Icons.bar_chart_rounded,
  SpeakSkill.writing => Icons.edit_note_rounded,
  SpeakSkill.speaking || SpeakSkill.roleplay => Icons.graphic_eq_rounded,
  SpeakSkill.connectors || SpeakSkill.liaison => Icons.link_rounded,
  SpeakSkill.alphabet => Icons.record_voice_over_rounded,
  SpeakSkill.review => Icons.rate_review_rounded,
  _ => Icons.school_rounded,
};

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
