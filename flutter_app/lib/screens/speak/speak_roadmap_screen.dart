import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/adaptive_course_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/course_artifact_codec.dart';
import '../../services/lesson_asset_prefetch_service.dart';
import '../../services/premium_access_gate.dart';
import '../../services/speak_language_profile.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/subscription_gate_service.dart';
import '../../services/sync_service.dart';
import 'speak_course_activity_screen.dart';
import '../../widgets/v3/v3_surface.dart';

class SpeakRoadmapScreen extends ConsumerStatefulWidget {
  const SpeakRoadmapScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<SpeakRoadmapScreen> createState() => _SpeakRoadmapScreenState();
}

class _SpeakRoadmapScreenState extends ConsumerState<SpeakRoadmapScreen> {
  bool _preparingCourse = false;
  Timer? _retryTimer;
  String? _stuckOnContentKey;
  int _noProgressAttempts = 0;

  // A stuck lesson (e.g. a real, non-transient backend conflict) must never
  // turn into a tight infinite request loop, but it must also never be
  // abandoned for good — this widget is kept alive for the whole app session
  // (Course sits in an IndexedStack), so "stop retrying" here would mean
  // "never try again until the app restarts". Back off instead: a real
  // generation normally finishes in a handful of seconds, so keep checking
  // quickly at first — the ceiling only exists for a genuinely stuck row,
  // and even then it is never more than 20 seconds stale.
  static const _retryBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 12),
    Duration(seconds: 20),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareCourse());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  /// Course must drive its own personalized-lesson generation instead of
  /// relying on the learner having visited Home first. Generation is still
  /// exactly one lesson at a time (`prepareAdaptiveCourseLessons` enforces
  /// that server-side); this only makes sure that one-at-a-time work keeps
  /// happening while the learner is looking at Course, and again right after
  /// they finish a lesson, without ever running two calls in parallel.
  Future<void> _prepareCourse() async {
    if (_preparingCourse) return;
    _preparingCourse = true;
    try {
      final profile = ref.read(learningStoreProvider).profile();
      final plan = ref.read(adaptiveCourseStoreProvider).ensureCurrentPlan(profile);
      final sync = ref.read(syncServiceProvider);
      final coursePersisted = await sync.syncAdaptiveCoursePlan(plan);
      if (coursePersisted) await sync.prepareAdaptiveCourseLessons();
      _prefetchUpcomingListeningAudio(profile, sync);
    } finally {
      _preparingCourse = false;
      if (mounted) setState(() {});
      _scheduleRetryIfStillPreparing();
    }
  }

  /// A Listening lesson's audio is a full-track download, not a quick TTS
  /// line — waiting for it only once the learner taps the card is exactly
  /// the "opening this takes forever" complaint. As soon as a Listening
  /// lesson's artifact is ready, start pulling its durable clip in the
  /// background so it is usually already cached by the time it is opened.
  void _prefetchUpcomingListeningAudio(Profile profile, SyncService sync) {
    final plan = ref.read(adaptiveCourseStoreProvider).ensureCurrentPlan(profile);
    for (final session in plan.sessions) {
      if (session.status == 'completed' ||
          session.primarySkill != SpeakSkill.listening ||
          !session.isContentReady ||
          session.artifact == null) {
        continue;
      }
      final story = CourseArtifactCodec.listening(session.artifact!);
      unawaited(
        LessonAssetPrefetchService.shared
            .prefetchListening(story: story, sync: sync)
            .catchError((_) => null),
      );
    }
  }

  /// While any personalized row is still `queued`/`generating`/`failed`,
  /// gently keep asking the server for the next one so a learner who stays
  /// on this tab sees lessons unlock without needing to background/
  /// foreground the app or bounce through Home. The same lesson staying
  /// stuck for a while backs the check off up to once a minute instead of
  /// hammering the backend every 4 seconds, but it never stops for good.
  void _scheduleRetryIfStillPreparing() {
    _retryTimer?.cancel();
    if (!mounted) return;
    final profile = ref.read(learningStoreProvider).profile();
    final plan = ref.read(adaptiveCourseStoreProvider).ensureCurrentPlan(profile);
    final pending = plan.sessions
        .cast<AdaptiveCourseSessionSpec?>()
        .firstWhere(
          (session) =>
              session != null &&
              session.status != 'completed' &&
              !session.isContentReady,
          orElse: () => null,
        );
    if (pending == null) {
      _stuckOnContentKey = null;
      _noProgressAttempts = 0;
      return;
    }
    if (pending.contentKey == _stuckOnContentKey) {
      _noProgressAttempts += 1;
    } else {
      _stuckOnContentKey = pending.contentKey;
      _noProgressAttempts = 1;
    }
    final delay =
        _retryBackoff[(_noProgressAttempts - 1).clamp(0, _retryBackoff.length - 1)];
    _retryTimer = Timer(delay, () {
      if (mounted) _prepareCourse();
    });
  }

  Future<void> _openSession(SpeakRoadmapSession session) async {
    await AppRouter.push(context, (_) => _screenFor(session));
    if (mounted) {
      setState(() {});
      unawaited(_prepareCourse());
    }
  }

  /// Tapping a subscription-locked Unit 2+ lesson must show the paywall,
  /// the same as every other premium area — never a silent no-op.
  Future<void> _openPaywall(SpeakRoadmapSession session) async {
    final unlocked = await requirePremiumArea(
      context,
      ref,
      PremiumArea.course,
      source: 'course_roadmap',
    );
    if (unlocked) {
      setState(() {});
      await _openSession(session);
    }
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
    return _buildRoadmap(
      context,
      ref,
      profile,
      completedContentKeys,
      adaptivePlan.sessions,
    );
  }

  Widget _buildRoadmap(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
    Set<String> completedContentKeys,
    List<AdaptiveCourseSessionSpec> adaptiveSessions,
  ) {
    final roadmap = SpeakRoadmapService.build(
      profile,
      // History includes free talk, onboarding demos, and legacy sessions.
      // Only stable course content keys are allowed to unlock this path.
      // There is no safe legacy index fallback: keys from another level
      // must not unlock this level's path.
      completedContentKeys: completedContentKeys,
      adaptiveSessions: adaptiveSessions,
    );
    final language = SpeakLanguageProfile.forLevel(roadmap.level);
    final courseLocked = ref
        .watch(subscriptionGateServiceProvider)
        .isAreaLocked(PremiumArea.course);
    final units =
        roadmap.sessions.map((session) => session.unit).toSet().toList()
          ..sort();
    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          V3Header(
            title: 'Your course',
            subtitle:
                '${roadmap.level.toUpperCase()} · ${roadmap.trackLabel} · ${roadmap.sessions.length} sessions · ${language.shortLabel}',
            leading: widget.embedded ? null : const V3BackButton(),
            trailing: V3IconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Course options',
              onPressed: () => showV3Picker<String>(
                context: context,
                title: 'Course view',
                selected: 'all',
                options: const [
                  V3PickerOption(
                    value: 'all',
                    label: 'All sessions',
                    description: 'See the complete adaptive path.',
                    icon: Icons.route_rounded,
                  ),
                  V3PickerOption(
                    value: 'current',
                    label: 'Current unit',
                    description: 'Keep the next lesson close at hand.',
                    icon: Icons.flag_outlined,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              language.roadmapHint,
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.nightMuted),
            ),
          ),
          const SizedBox(height: 20),
          V3Card(
            raised: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.route_rounded, color: DesignTokens.nightAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${roadmap.completedCount} of ${roadmap.sessions.length} sessions complete · ${units.length} units',
                        style: DesignTokens.body(
                          14,
                          weight: FontWeight.w700,
                        ).copyWith(color: DesignTokens.nightText),
                      ),
                    ),
                    Text(
                      '${(roadmap.progress * 100).round()}%',
                      style: DesignTokens.body(
                        12,
                        weight: FontWeight.w700,
                      ).copyWith(color: DesignTokens.nightAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: roadmap.progress,
                    minHeight: 8,
                    backgroundColor: DesignTokens.nightHairline,
                    valueColor: AlwaysStoppedAnimation(
                      DesignTokens.nightAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final unit in units) ...[
            _unitHeader(roadmap, unit),
            const SizedBox(height: 10),
            // Unit 1 is the free foundation every new learner needs to try
            // Course at all; the subscription gate only ever applies from
            // Unit 2 onward.
            _unitPath(
              context,
              roadmap,
              unit,
              locked: courseLocked && unit > 1,
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _unitHeader(SpeakRoadmap roadmap, int unit) {
    final session = roadmap.sessions.firstWhere((item) => item.unit == unit);
    return Row(
      children: [
        Text(
          'UNIT $unit',
          style: DesignTokens.label(
            10,
          ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            session.unitTitle,
            style: DesignTokens.display(
              20,
            ).copyWith(color: DesignTokens.nightText),
          ),
        ),
      ],
    );
  }

  Widget _unitPath(
    BuildContext context,
    SpeakRoadmap roadmap,
    int unit, {
    required bool locked,
  }) {
    final sessions = roadmap.sessions
        .where((session) => session.unit == unit)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth * 0.84;
        return Stack(
          children: [
            Column(
              children: [
                for (var index = 0; index < sessions.length; index++) ...[
                  Align(
                    alignment: index.isEven
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: SizedBox(
                      width: cardWidth,
                      child: _sessionTile(
                        context,
                        sessions[index],
                        featured:
                            sessions[index].index == roadmap.nextSession?.index,
                        locked: locked,
                      ),
                    ),
                  ),
                  if (index != sessions.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _sessionTile(
    BuildContext context,
    SpeakRoadmapSession session, {
    required bool featured,
    required bool locked,
  }) {
    final preparing = !session.contentReady && !session.completed;
    // A subscription-locked lesson must still be tappable: tapping it is
    // exactly what should show the paywall, matching Practice's behavior.
    // Only "not generated yet" truly disables the tap.
    final unavailable = preparing;
    final active = featured && !session.completed && !preparing;
    final statusLabel = preparing
        ? 'preparing'
        : locked
        ? 'locked'
        : session.completed
        ? 'completed'
        : 'available';
    final stateIcon = locked
        ? Icons.lock_outline_rounded
        : session.completed
        ? Icons.check_circle_rounded
        : Icons.arrow_forward_ios_rounded;
    final stateColor = active
        ? DesignTokens.nightAccent
        : DesignTokens.nightMuted;
    return Semantics(
      button: true,
      label: '${session.title}, ${session.primarySkill.label}, $statusLabel',
      child: V3Card(
        raised: active,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        borderColor: active
            ? DesignTokens.nightAccent
            : DesignTokens.nightHairline,
        onTap: unavailable
            ? null
            : () => locked ? _openPaywall(session) : _openSession(session),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active
                    ? DesignTokens.nightAccentSoft
                    : DesignTokens.nightSurfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(
                session.completed
                    ? Icons.check_rounded
                    : _iconFor(session.primarySkill),
                size: 19,
                color: active
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.display(
                      15,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                  if (preparing) ...[
                    const SizedBox(height: 3),
                    Text(
                      session.generationStatus == 'failed'
                          ? 'Retrying your complete lesson package'
                          : 'Creating your personalized lesson',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (preparing)
              const _LessonPreparationIndicator()
            else
              Icon(stateIcon, size: 19, color: stateColor),
          ],
        ),
      ),
    );
  }

  Widget _screenFor(SpeakRoadmapSession session) =>
      SpeakCourseActivityScreen(session: session);

  IconData _iconFor(SpeakSkill skill) => switch (skill) {
    SpeakSkill.alphabet => Icons.abc_rounded,
    SpeakSkill.vocabulary => Icons.style_outlined,
    SpeakSkill.reading => Icons.menu_book_outlined,
    SpeakSkill.listening => Icons.headphones_outlined,
    SpeakSkill.grammar => Icons.auto_fix_high_outlined,
    SpeakSkill.connectors => Icons.link_rounded,
    SpeakSkill.liaison => Icons.record_voice_over_outlined,
    SpeakSkill.writing => Icons.edit_note_rounded,
    SpeakSkill.speaking => Icons.mic_none_rounded,
    SpeakSkill.roleplay => Icons.forum_outlined,
    SpeakSkill.review => Icons.replay_rounded,
    SpeakSkill.freeTalk => Icons.people_alt_outlined,
  };
}

class _LessonPreparationIndicator extends StatefulWidget {
  const _LessonPreparationIndicator();

  @override
  State<_LessonPreparationIndicator> createState() =>
      _LessonPreparationIndicatorState();
}

class _LessonPreparationIndicatorState
    extends State<_LessonPreparationIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Creating lesson',
    child: SizedBox.square(
      dimension: 22,
      child: RotationTransition(
        turns: _controller,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          strokeCap: StrokeCap.round,
          backgroundColor: DesignTokens.nightHairline,
          valueColor: AlwaysStoppedAnimation(DesignTokens.nightAccent),
        ),
      ),
    ),
  );
}
