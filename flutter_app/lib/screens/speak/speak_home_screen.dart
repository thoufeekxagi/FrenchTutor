import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/app_tour.dart';
import '../../services/speak_language_profile.dart';
import '../../services/speak_roadmap_service.dart';
import 'speak_course_activity_screen.dart';
import 'speak_roadmap_screen.dart';
import 'speak_ui.dart';

class SpeakHomeScreen extends ConsumerStatefulWidget {
  const SpeakHomeScreen({super.key});

  @override
  ConsumerState<SpeakHomeScreen> createState() => _SpeakHomeScreenState();
}

class _SpeakHomeScreenState extends ConsumerState<SpeakHomeScreen> {
  bool _tourRequested = false;
  // Keep the first five visible after the foundation is complete, then reveal
  // the course in the same five-session batches as the learner taps Next.
  int _revealedNextCount = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded) {
        return;
      }
      final requested =
          AppTour.pendingHomeReplay || !await AppTour.hasSeenHome();
      if (!mounted) return;
      if (AppTour.pendingHomeReplay) AppTour.pendingHomeReplay = false;
      setState(() => _tourRequested = requested);
    });
  }

  Future<void> _openSession(SpeakRoadmapSession session) async {
    await AppRouter.push(
      context,
      (_) => SpeakCourseActivityScreen(session: session),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final completedContentKeys = ref
        .watch(storageServiceProvider)
        .completedContentKeys();
    final catalog = ref.watch(speakCurriculumProvider(profile.level));
    if (catalog.isLoading && catalog.valueOrNull == null) {
      return const SpeakScaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final roadmap = SpeakRoadmapService.build(
      profile,
      // Only course sessions may advance the course. Counting every saved
      // conversation here made unrelated free-talk/history rows unlock the
      // roadmap and made the progress card disagree with the path.
      // There is no safe legacy index fallback: keys from another level
      // must not unlock this level's path.
      completedSessions: 0,
      completedContentKeys: completedContentKeys,
      catalog: catalog.valueOrNull,
    );
    final language = SpeakLanguageProfile.forLevel(roadmap.level);
    final next = roadmap.nextSession ?? roadmap.sessions.last;
    final firstUnit = roadmap.sessions
        .map((session) => session.unit)
        .reduce((a, b) => a < b ? a : b);
    final featured = roadmap.sessions.firstWhere(
      (session) => session.unit == firstUnit,
    );
    final foundationLessons = roadmap.sessions
        .where((session) => session.unit == featured.unit)
        .take(5)
        .toList(growable: false);
    final foundationComplete =
        foundationLessons.isNotEmpty &&
        foundationLessons.every((session) => session.completed);
    final foundationEndIndex = foundationLessons.isEmpty
        ? -1
        : foundationLessons.last.index;
    final followingLessons = roadmap.sessions
        .where((session) => session.index > foundationEndIndex)
        .toList(growable: false);
    final visibleFollowingLessons = followingLessons
        .take(math.min(_revealedNextCount, followingLessons.length))
        .toList(growable: false);
    final hasMoreFollowingLessons =
        visibleFollowingLessons.length < followingLessons.length;
    if (_tourRequested) {
      _tourRequested = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppTour.playHome(context);
      });
    }

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          Row(
            children: [
              SpeakPill(label: roadmap.level.toUpperCase(), selected: true),
              const Spacer(),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: SpeakColors.line),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: SpeakColors.orange,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UNIT ${featured.unit}',
                      style: DesignTokens.label(
                        10,
                      ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(featured.unitTitle, style: DesignTokens.display(25)),
                  ],
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: SpeakColors.blueSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: SpeakColors.blue,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SpeakProgressBar(value: roadmap.progress),
          const SizedBox(height: 8),
          Text(
            language.roadmapHint,
            style: DesignTokens.body(12).copyWith(color: SpeakColors.inkSoft),
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 24),
          _lessonPath(foundationLessons, onLessonTap: _openSession),
          if (foundationComplete && followingLessons.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SpeakSectionTitle(title: 'Next lessons'),
            const SizedBox(height: 12),
            _lessonPath(
              visibleFollowingLessons,
              startIndex: foundationLessons.length,
              onLessonTap: _openSession,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: SpeakPill(
                label: hasMoreFollowingLessons ? 'Next' : 'See all',
                icon: Icons.arrow_forward_rounded,
                onTap: hasMoreFollowingLessons
                    ? () {
                        setState(() {
                          _revealedNextCount = math.min(
                            _revealedNextCount + 5,
                            followingLessons.length,
                          );
                        });
                      }
                    : () => AppRouter.push(
                        context,
                        (_) => const SpeakRoadmapScreen(),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 26),
          SpeakSectionTitle(
            title: 'Your roadmap',
            action: 'See all',
            onTap: () =>
                AppRouter.push(context, (_) => const SpeakRoadmapScreen()),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: AppTour.nextSessionKey,
            child: SpeakCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: SpeakColors.blueSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: SpeakColors.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next session',
                          style: DesignTokens.body(15, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          next.title,
                          style: DesignTokens.body(
                            12,
                          ).copyWith(color: SpeakColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _openSession(next),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: SpeakColors.blue,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lessonPath(
    List<SpeakRoadmapSession> lessons, {
    int startIndex = 0,
    required ValueChanged<SpeakRoadmapSession> onLessonTap,
  }) {
    return Column(
      children: [
        for (var index = 0; index < lessons.length; index++) ...[
          _LessonBubble(
            title: lessons[index].title,
            subtitle: lessons[index].completed
                ? 'Completed'
                : 'Session ${lessons[index].index + 1}',
            active: lessons[index].unlocked && !lessons[index].completed,
            alignRight: (index + startIndex).isOdd,
            onTap: () => onLessonTap(lessons[index]),
          ),
          if (index != lessons.length - 1)
            Padding(
              padding: EdgeInsets.only(
                left: index.isOdd ? 48 : 32,
                right: index.isOdd ? 32 : 48,
              ),
              child: Container(height: 22, width: 1, color: SpeakColors.line),
            ),
        ],
      ],
    );
  }
}

class _LessonBubble extends StatelessWidget {
  const _LessonBubble({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.alignRight,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool active;
  final bool alignRight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 250),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: active ? SpeakColors.blue : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? SpeakColors.blue : SpeakColors.line,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: DesignTokens.primary.withValues(alpha: 0.1),
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: active ? Colors.white24 : SpeakColors.blueSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  active
                      ? Icons.play_arrow_rounded
                      : Icons.chat_bubble_outline_rounded,
                  color: active ? Colors.white : SpeakColors.blue,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(14, weight: FontWeight.w700)
                          .copyWith(
                            color: active ? Colors.white : SpeakColors.navy,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: DesignTokens.body(11).copyWith(
                        color: active ? Colors.white70 : SpeakColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
