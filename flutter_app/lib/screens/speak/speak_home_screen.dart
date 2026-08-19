import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_keys.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/speak_curriculum.dart';
import '../../models/tutor_persona.dart';
import '../../providers/database_provider.dart';
import '../../services/ai_session_gate.dart';
import '../../services/app_tour.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/starter_cover_resolver.dart';
import '../labs/listening_lab_screen.dart';
import '../labs/vocab_lab_screen.dart';
import '../reading/reading_library_screen.dart';
import '../session/session_screen.dart';
import 'speak_course_activity_screen.dart';
import 'speak_practice_screen.dart';
import 'speak_profile_screen.dart';
import 'speak_settings_screen.dart';

/// V3 Home: a compact next-action surface over the existing course/session
/// data flow. The redesign changes hierarchy and presentation only.
class SpeakHomeScreen extends ConsumerStatefulWidget {
  const SpeakHomeScreen({super.key});

  @override
  ConsumerState<SpeakHomeScreen> createState() => _SpeakHomeScreenState();
}

class _SpeakHomeScreenState extends ConsumerState<SpeakHomeScreen> {
  late final PageController _featuredController;
  var _featuredPage = 0;
  bool _tourRequested = false;

  @override
  void initState() {
    super.initState();
    _featuredController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || MediaQuery.sizeOf(context).width >= 1024) return;
      final requested =
          AppTour.pendingHomeReplay || !await AppTour.hasSeenHome();
      if (!mounted) return;
      if (AppTour.pendingHomeReplay) AppTour.pendingHomeReplay = false;
      setState(() => _tourRequested = requested);
    });
  }

  @override
  void dispose() {
    _featuredController.dispose();
    super.dispose();
  }

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
    final featuredSessions = lessonCards.take(2).toList(growable: false);
    final tutor = ActiveTutor.current;

    if (_tourRequested) {
      _tourRequested = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppTour.playHome(context);
      });
    }

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _header(context, roadmap.trackLabel, tutor),
            const SizedBox(height: 18),
            _callTutorButton(),
            const SizedBox(height: 16),
            _modeRail(context, next.primarySkill),
            const SizedBox(height: 20),
            KeyedSubtree(
              key: AppTour.nextSessionKey,
              child: _featuredCarousel(featuredSessions),
            ),
            const SizedBox(height: 10),
            _pageDots(featuredSessions.length),
            const SizedBox(height: 24),
            Text('Recent activity', style: _display(19)),
            const SizedBox(height: 12),
            _activityGrid(context, tutor, lessonCards),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String trackLabel, TutorPersona tutor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Home', style: _display(31)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            trackLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _body(16, color: DesignTokens.nightMuted),
          ),
        ),
        const SizedBox(width: 12),
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
              child: ClipOval(
                child: Image.asset(tutor.portraitAsset, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _callTutorButton() {
    return Semantics(
      button: true,
      label: 'Call tutor ${ActiveTutor.current.displayName}',
      child: GestureDetector(
        onTap: _callTutor,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          decoration: BoxDecoration(
            gradient: DesignTokens.nightGradient,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.phone_in_talk_rounded,
                color: DesignTokens.nightAccent,
                size: 21,
              ),
              const SizedBox(width: 13),
              Expanded(child: Text('Call tutor', style: _body(17))),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: DesignTokens.nightAccent,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeRail(BuildContext context, SpeakSkill selectedSkill) {
    final selected = switch (selectedSkill) {
      SpeakSkill.speaking || SpeakSkill.roleplay => SpeakSkill.speaking,
      SpeakSkill.reading => SpeakSkill.reading,
      SpeakSkill.vocabulary => SpeakSkill.vocabulary,
      _ => SpeakSkill.listening,
    };
    final modes = [
      (
        'Listening',
        SpeakSkill.listening,
        Icons.headphones_rounded,
        const ListeningLabScreen(),
      ),
      (
        'Speaking',
        SpeakSkill.speaking,
        Icons.graphic_eq_rounded,
        const SpeakPracticeScreen(),
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

  Widget _featuredCarousel(List<SpeakRoadmapSession> sessions) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 232,
      child: PageView.builder(
        controller: _featuredController,
        itemCount: sessions.length,
        onPageChanged: (page) => setState(() => _featuredPage = page),
        itemBuilder: (context, index) {
          final session = sessions[index];
          return Padding(
            padding: EdgeInsets.only(
              right: index == sessions.length - 1 ? 0 : 8,
            ),
            child: GestureDetector(
              onTap: () => _openSession(session),
              child: _FeaturedSessionCard(session: session),
            ),
          );
        },
      ),
    );
  }

  Widget _pageDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: DesignTokens.durationFast,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: index == _featuredPage ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: index == _featuredPage
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightHairline,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }

  Widget _activityGrid(
    BuildContext context,
    TutorPersona tutor,
    List<SpeakRoadmapSession> lessons,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      // Keep the activity block compact enough that both rows remain above
      // the floating navigation island on a standard iPhone viewport.
      childAspectRatio: 1.34,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _TutorActivityCard(
          tutor: tutor,
          onTap: () =>
              AppRouter.push(context, (_) => const SpeakSettingsScreen()),
        ),
        for (final lesson in lessons)
          _LessonActivityCard(
            session: lesson,
            onTap: () => _openSession(lesson),
          ),
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

class _FeaturedSessionCard extends StatelessWidget {
  const _FeaturedSessionCard({required this.session});

  final SpeakRoadmapSession session;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
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
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.88),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'CONTINUE',
                  style: DesignTokens.body(12, weight: FontWeight.w700)
                      .copyWith(
                        color: DesignTokens.nightAccent,
                        letterSpacing: 0.6,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.display(
                    24,
                  ).copyWith(color: DesignTokens.nightText),
                ),
                const SizedBox(height: 7),
                Text(
                  '${session.primarySkill.label}  ·  ${session.estimatedMinutes} min',
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorActivityCard extends StatelessWidget {
  const _TutorActivityCard({required this.tutor, required this.onTap});

  final TutorPersona tutor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ActivityCardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                tutor.portraitAsset,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Change your tutor',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _cardTitle(),
          ),
          const SizedBox(height: 3),
          Text(
            tutor.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cardMeta(),
          ),
        ],
      ),
    );
  }
}

class _LessonActivityCard extends StatelessWidget {
  const _LessonActivityCard({required this.session, required this.onTap});

  final SpeakRoadmapSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ActivityCardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: DesignTokens.nightAccentSoft,
              shape: BoxShape.circle,
              border: Border.all(color: DesignTokens.nightHairline),
            ),
            child: Icon(
              _skillIcon(session.primarySkill),
              color: DesignTokens.nightAccent,
              size: 18,
            ),
          ),
          const Spacer(),
          Text(
            session.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _cardTitle().copyWith(fontSize: 13),
          ),
          const SizedBox(height: 5),
          Text(
            session.primarySkill.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cardMeta(),
          ),
          const SizedBox(height: 2),
          const Align(
            alignment: Alignment.bottomRight,
            child: Icon(
              Icons.arrow_forward_ios_rounded,
              color: DesignTokens.nightAccent,
              size: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCardShell extends StatelessWidget {
  const _ActivityCardShell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: DesignTokens.nightGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DesignTokens.nightHairline),
          ),
          child: child,
        ),
      ),
    );
  }
}

TextStyle _cardTitle() => DesignTokens.body(
  14,
  weight: FontWeight.w600,
).copyWith(color: DesignTokens.nightText);

TextStyle _cardMeta() =>
    DesignTokens.body(11).copyWith(color: DesignTokens.nightMuted);

IconData _skillIcon(SpeakSkill skill) => switch (skill) {
  SpeakSkill.listening => Icons.headphones_rounded,
  SpeakSkill.speaking || SpeakSkill.roleplay => Icons.graphic_eq_rounded,
  SpeakSkill.reading => Icons.menu_book_rounded,
  SpeakSkill.vocabulary => Icons.style_rounded,
  SpeakSkill.grammar => Icons.spellcheck_rounded,
  SpeakSkill.writing => Icons.edit_note_rounded,
  _ => Icons.auto_awesome_rounded,
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
