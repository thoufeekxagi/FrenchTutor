import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/adaptive_course_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../providers/database_provider.dart';
import '../../services/premium_access_gate.dart';
import '../../services/course_artifact_codec.dart';
import '../../services/course_generation_test_harness.dart';
import '../../services/lesson_audio_deck_service.dart';
import '../../services/ai_cost_tracker.dart';
import '../../services/speak_language_profile.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/subscription_gate_service.dart';
import 'speak_course_activity_screen.dart';
import '../../widgets/v3/v3_surface.dart';

class SpeakRoadmapScreen extends ConsumerStatefulWidget {
  const SpeakRoadmapScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<SpeakRoadmapScreen> createState() => _SpeakRoadmapScreenState();
}

class _SpeakRoadmapScreenState extends ConsumerState<SpeakRoadmapScreen>
    with WidgetsBindingObserver {
  bool _preparingCourse = false;
  int _generationEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A debug harness run can be interrupted after the Unit 2 completion has
    // already been persisted (for example by a hot restart or a device
    // reconnect). In that case the queued target row is still valid work, but
    // there is no Navigator result left to trigger preparation. Reconcile it
    // once when the roadmap opens. This path is compile-time/debug-only and
    // never retries a failed row or changes the production Generate flow.
    final harness = CourseGenerationTestHarness.current;
    debugPrint(
      '[COURSE_HARNESS] active=${harness.active} enabled=${harness.enabled} '
      'target=${harness.targetWireName}',
    );
    if (harness.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _prepareCourse(
            harnessSkill: harness.targetWireName,
            reconcileQueuedHarnessRow: true,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _generationEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A provider request already in flight cannot be recalled safely, but its
    // continuation must not start the next PCM/Live request after the learner
    // backgrounds the app. A new explicit Generate tap can resume later.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generationEpoch++;
    }
  }

  /// Prepares one personalized Course lesson. Production calls this only from
  /// the explicit Generate action. The development harness may call it once
  /// immediately after the selected lesson is completed.
  Future<void> _prepareCourse({
    String? harnessSkill,
    bool onlyIfNewHarnessRow = false,
    bool reconcileQueuedHarnessRow = false,
  }) async {
    if (_preparingCourse) return;
    _preparingCourse = true;
    final operationEpoch = _generationEpoch;
    try {
      final sync = ref.read(syncServiceProvider);
      // hydrateAdaptiveCourses() otherwise only ever runs as a side effect
      // of a successful generation call below. If every row this device
      // knows about already looks 'ready' locally, that call finds nothing
      // to do and returns immediately — so a device whose local rows
      // drifted out of sync with the server (e.g. a batch that was pushed
      // successfully but never fully reflected back locally) never
      // self-heals just by reopening Course, no matter how many times the
      // learner does it. Pull the real remote state down first, every time,
      // before this screen decides what (if anything) it still needs.
      await sync.hydrateAdaptiveCourses();
      if (!mounted || operationEpoch != _generationEpoch) return;
      final profile = ref.read(learningStoreProvider).profile();
      final store = ref.read(adaptiveCourseStoreProvider);
      final before = onlyIfNewHarnessRow ? store.currentPlan(profile) : null;
      final beforeHighest = before == null
          ? AdaptiveCourseStore.initialBatchSize
          : before.sessions.fold<int>(
              adaptiveCourseFoundationSize + adaptiveCourseBatchSize,
              (highest, session) =>
                  session.sequence > highest ? session.sequence : highest,
            );
      final plan = store.ensureCurrentPlan(profile);
      if (reconcileQueuedHarnessRow && harnessSkill != null) {
        final queuedHarnessRow = plan.sessions.any(
          (session) =>
              session.sequence > AdaptiveCourseStore.initialBatchSize &&
              session.primarySkill.wireName == harnessSkill &&
              session.generationStatus == 'queued',
        );
        if (!queuedHarnessRow) return;
        unawaited(
          AiCostTracker.event(
            feature: 'course_generation_harness',
            event: 'reconcile_queued_triggered',
            extra: {'target_skill': harnessSkill},
          ),
        );
      }
      if (onlyIfNewHarnessRow) {
        final highest = plan.sessions.fold<int>(
          adaptiveCourseFoundationSize + adaptiveCourseBatchSize,
          (current, session) =>
              session.sequence > current ? session.sequence : current,
        );
        if (highest <= beforeHighest) {
          // The roadmap can rebuild between Navigator.pop and this callback.
          // In that case ensureCurrentPlan may already have appended the one
          // queued row locally, even though no provider request has started.
          // Completion is still the explicit trigger, so prepare that row;
          // never reopen a ready or failed row automatically.
          final queuedHarnessRow = plan.sessions.any(
            (session) =>
                session.sequence > AdaptiveCourseStore.initialBatchSize &&
                session.primarySkill ==
                    CourseGenerationTestHarness.current.targetSkill &&
                session.generationStatus == 'queued',
          );
          if (!queuedHarnessRow) return;
        }
      }
      final coursePersisted = await sync.syncAdaptiveCoursePlan(plan);
      if (!mounted || operationEpoch != _generationEpoch) return;
      // A reconcile can legitimately have no local plan diff: the queued row
      // was already persisted by an earlier run. It still needs the one
      // explicit provider claim. Production keeps the existing persisted-plan
      // gate; only the debug harness may prepare an unchanged queued row.
      if (coursePersisted || reconcileQueuedHarnessRow) {
        await sync.prepareAdaptiveCourseLessons(harnessSkill: harnessSkill);
      }
      // Audio repair is still explicit, but it must not depend on the text
      // endpoint reporting `generated > 0`. A lesson can be ready after text
      // succeeded while one PCM clip timed out; the next deliberate Generate
      // action should inspect the saved lesson and repair only that missing
      // cache entry, without regenerating the lesson text.
      if (!mounted || operationEpoch != _generationEpoch) return;
      await sync.hydrateAdaptiveCourses();
      if (!mounted || operationEpoch != _generationEpoch) return;
      if (harnessSkill == 'vocabulary') {
        // Vocabulary is intentionally Live-only. Do not let this shared
        // roadmap callback repair an unrelated reading/listening deck while
        // the Vocabulary harness is being measured.
        unawaited(
          AiCostTracker.event(
            feature: 'course_generation',
            event: 'vocabulary_audio_deferred_live_only',
            extra: {'audio_generation_calls': 0},
          ),
        );
        return;
      }
      final refreshed = ref
          .read(adaptiveCourseStoreProvider)
          .ensureCurrentPlan(profile);
      for (final candidate in refreshed.sessions.reversed) {
        if (candidate.isFoundation ||
            candidate.generationStatus != 'ready' ||
            candidate.artifact == null ||
            (candidate.primarySkill != SpeakSkill.reading &&
                candidate.primarySkill != SpeakSkill.listening)) {
          continue;
        }
        try {
          if (!mounted || operationEpoch != _generationEpoch) return;
          final story = candidate.primarySkill == SpeakSkill.listening
              ? CourseArtifactCodec.listening(candidate.artifact!)
              : CourseArtifactCodec.story(candidate.artifact!);
          if (!mounted || operationEpoch != _generationEpoch) return;
          await LessonAudioDeckService.shared.prepare(
            story: story,
            db: ref.read(databaseProvider),
          );
        } catch (error, stackTrace) {
          // Text lesson generation remains persisted. The next explicit
          // Generate action can finish a missing audio deck; no silent
          // retry is scheduled here.
          debugPrint(
            'Course audio generation deferred for ${candidate.contentKey}: '
            '$error\n$stackTrace',
          );
        }
        break;
      }
    } finally {
      _preparingCourse = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openSession(SpeakRoadmapSession session) async {
    final result = await AppRouter.push<Object?>(
      context,
      (_) => _screenFor(session),
    );
    if (!mounted) return;
    setState(() {});
    final harness = CourseGenerationTestHarness.current;
    if (result == true &&
        harness.shouldAdvanceAfter(
          sequence: session.sequence,
          primarySkill: session.primarySkill,
        )) {
      unawaited(
        AiCostTracker.event(
          feature: 'course_generation_harness',
          event: 'advance_triggered',
          extra: {
            'source_sequence': session.sequence,
            'source_skill': session.primarySkill.wireName,
            'target_skill': harness.targetWireName,
          },
        ),
      );
      await _prepareCourse(
        harnessSkill: harness.targetWireName,
        onlyIfNewHarnessRow: true,
      );
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
      generationHarness: CourseGenerationTestHarness.current,
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
            _unitPath(context, roadmap, unit, locked: courseLocked && unit > 1),
            const SizedBox(height: 14),
          ],
          _generateNextCard(roadmap.sessions),
        ],
      ),
    );
  }

  /// Generation is deliberately explicit. This card gives the learner one
  /// clear action for creating the next personalized row; there is no hidden
  /// buffer timer or background retry loop to spend provider quota.
  Widget _generateNextCard(List<SpeakRoadmapSession> sessions) {
    // A queued row is deliberately idle: only the explicit Generate action
    // may claim it and call the provider. Treating every non-ready row as
    // "preparing" made an idle queued lesson look like a background request
    // forever, even though no network work was running.
    final hasInFlight =
        _preparingCourse ||
        sessions.any((session) => session.generationStatus == 'generating');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: V3Card(
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: DesignTokens.nightAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasInFlight
                    ? 'Generating one lesson…'
                    : 'Tap Generate next when you want another lesson.',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.nightMuted),
              ),
            ),
            const SizedBox(width: 10),
            V3PrimaryButton(
              label: 'Generate next',
              icon: Icons.add_rounded,
              expand: false,
              onPressed: _preparingCourse
                  ? null
                  : () {
                      final harness = CourseGenerationTestHarness.current;
                      _prepareCourse(
                        harnessSkill: harness.active
                            ? harness.targetWireName
                            : null,
                      );
                    },
            ),
          ],
        ),
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
    final preparing = session.generationStatus == 'generating';
    final queued = session.generationStatus == 'queued';
    final failed = session.generationStatus == 'failed';
    // A subscription-locked lesson must still be tappable: tapping it is
    // exactly what should show the paywall, matching Practice's behavior.
    // Only "not generated yet" truly disables the tap.
    final unavailable = !session.contentReady;
    final active = featured && !session.completed && !preparing && !queued;
    final statusLabel = preparing
        ? 'generating'
        : queued
        ? 'queued'
        : failed
        ? 'generation failed'
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
                // The leading icon identifies the lesson's skill. Completion
                // is communicated independently by the trailing status icon.
                _iconFor(session.primarySkill),
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
                  if (!session.contentReady && !session.completed) ...[
                    const SizedBox(height: 3),
                    Text(
                      preparing
                          ? 'Creating your personalized lesson'
                          : failed
                          ? 'Generation failed — tap Generate next to retry'
                          : 'Waiting for Generate next',
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
            else if (queued || failed)
              Icon(
                failed ? Icons.error_outline_rounded : Icons.schedule_rounded,
                size: 19,
                color: DesignTokens.nightMuted,
              )
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
