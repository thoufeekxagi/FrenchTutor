import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/adaptive_course_store.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/speak_curriculum.dart';
import '../../models/grammar_course_session_result.dart';
import '../../providers/database_provider.dart';
import '../../services/premium_access_gate.dart';
import '../../services/course_generation_test_harness.dart';
import '../../services/ai_cost_tracker.dart';
import '../../services/speak_language_profile.dart';
import '../../services/speak_roadmap_service.dart';
import '../../services/sync_service.dart';
import '../../services/subscription_gate_service.dart';
import 'speak_course_activity_screen.dart';
import '../../widgets/personalized_generation_loader.dart';
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
    // only retries a failed row once; it never changes the production
    // completion-driven flow.
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
    } else {
      // Recover a completion that happened just before an app update, force
      // quit, or network transition. Older releases left the successor row
      // queued; a roadmap reopen now safely resumes only when a generated
      // lesson is already completed and another generated row is waiting.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_recoverPendingProductionGeneration());
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
    // backgrounds the app. The next foreground/resume pass can safely retry.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _generationEpoch++;
    } else if (state == AppLifecycleState.resumed &&
        !CourseGenerationTestHarness.current.active &&
        mounted) {
      unawaited(_recoverPendingProductionGeneration());
    }
  }

  Future<void> _recoverPendingProductionGeneration() async {
    if (_preparingCourse) return;
    final sync = ref.read(syncServiceProvider);
    try {
      await sync.drainOutbox(limit: 25);
      await sync.hydrateAdaptiveCourses();
      if (!mounted) return;
      final profile = ref.read(learningStoreProvider).profile();
      final plan = ref.read(adaptiveCourseStoreProvider).currentPlan(profile);
      if (plan == null) return;
      final hasCompletedLesson = plan.sessions.any(
        (session) => session.status == 'completed',
      );
      final hasPendingGenerated = plan.sessions.any(
        (session) =>
            session.sequence > AdaptiveCourseStore.initialBatchSize &&
            session.status != 'completed' &&
            (session.generationStatus == 'queued' ||
                session.generationStatus == 'failed'),
      );
      if (!hasCompletedLesson || !hasPendingGenerated) return;
      // Force the bounded provider claim even when the queued row was already
      // persisted by a previous run. There may be no local plan diff left to
      // signal that work is still waiting.
      await _prepareCourse(forcePrepare: true);
    } catch (error, stackTrace) {
      // Recovery is best-effort. The status lane remains informative if the
      // device is offline or the endpoint is temporarily unavailable.
      debugPrint(
        'Pending Course generation recovery failed: $error\n$stackTrace',
      );
    }
  }

  /// Fills the two image-backed lessons for the first active personalized
  /// unit. The Edge Function still claims exactly one row per call; this
  /// bounded loop simply makes the vocabulary -> reading -> listening buffer
  /// available before the learner reaches the next card.
  Future<void> _prepareMediaBuffer(
    SyncService sync,
    AdaptiveCourseStore store,
    Profile profile,
    int operationEpoch,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted || operationEpoch != _generationEpoch) return;
      final plan = store.ensureMediaBuffer(profile);
      if (_mediaBufferReady(plan)) return;
      // The append above is idempotent, but explicitly await its push so a
      // second device cannot miss the newly-created Reading/Listening rows.
      await sync.syncAdaptiveCoursePlan(plan);
      if (!mounted || operationEpoch != _generationEpoch) return;
      final prepared = await sync.prepareAdaptiveCourseLessons();
      if (prepared == 0) return;
      await sync.hydrateAdaptiveCourses();
    }
  }

  bool _mediaBufferReady(AdaptiveCoursePlanSnapshot plan) {
    final units =
        plan.sessions
            .where((session) => session.unit >= 3)
            .map((session) => session.unit)
            .toSet()
            .toList()
          ..sort();
    if (units.isEmpty) return false;
    for (final unit in units) {
      final sessions = plan.sessions
          .where((session) => session.unit == unit)
          .toList(growable: false);
      final reading = sessions.where(
        (session) => session.primarySkill == SpeakSkill.reading,
      );
      final listening = sessions.where(
        (session) => session.primarySkill == SpeakSkill.listening,
      );
      if (reading.isEmpty || listening.isEmpty) return false;
      if (sessions.any((session) => session.status != 'completed')) {
        return reading.every(
              (session) =>
                  session.status == 'completed' || session.isContentReady,
            ) &&
            listening.every(
              (session) =>
                  session.status == 'completed' || session.isContentReady,
            );
      }
    }
    // Every currently-known unit is complete. ensureMediaBuffer() will have
    // appended the next unit on the next pass; keep the caller bounded here.
    return false;
  }

  /// Prepares one personalized Course lesson. Production calls this after a
  /// completed lesson (and during bounded recovery); the development harness
  /// may also call it once immediately after its selected lesson.
  Future<void> _prepareCourse({
    String? harnessSkill,
    bool onlyIfNewHarnessRow = false,
    bool reconcileQueuedHarnessRow = false,
    bool forcePrepare = false,
  }) async {
    if (_preparingCourse) return;
    _preparingCourse = true;
    final operationEpoch = _generationEpoch;
    try {
      final sync = ref.read(syncServiceProvider);
      // A completed activity writes its adaptive row and its normal session
      // record independently. Flush that tiny outbox first so the remote
      // completion is visible before we hydrate; otherwise a quick return to
      // the roadmap can pull the older `planned` snapshot back over the
      // just-completed local row and leave the next lesson queued forever.
      await sync.drainOutbox(limit: 25);
      if (!mounted || operationEpoch != _generationEpoch) return;
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
      final current = store.currentPlan(profile);
      final before = onlyIfNewHarnessRow ? current : null;
      final beforeHighest = before == null
          ? AdaptiveCourseStore.initialBatchSize
          : before.sessions.fold<int>(
              adaptiveCourseFoundationSize + adaptiveCourseBatchSize,
              (highest, session) =>
                  session.sequence > highest ? session.sequence : highest,
            );
      // Keep one fresh Reading and one fresh Listening lesson in the active
      // unit's persisted buffer. The store only appends through the
      // Listening slot; generation itself remains serial and bounded below.
      final plan = harnessSkill == null
          ? store.ensureMediaBuffer(profile)
          : store.ensureCurrentPlan(profile);
      if (reconcileQueuedHarnessRow && harnessSkill != null) {
        final queuedHarnessRow = plan.sessions.any(
          (session) =>
              session.sequence > AdaptiveCourseStore.initialBatchSize &&
              session.primarySkill.wireName == harnessSkill &&
              session.generationStatus == 'queued',
        );
        if (queuedHarnessRow) {
          unawaited(
            AiCostTracker.event(
              feature: 'course_generation_harness',
              event: 'reconcile_queued_triggered',
              extra: {'target_skill': harnessSkill},
            ),
          );
        } else {
          // A stale ready row can be just as blocked as a queued row: older
          // builds occasionally saved a Speaking artifact in a Reading row.
          // Still make the one bounded repair request so the server can
          // requeue that row instead of leaving the roadmap waiting forever.
          unawaited(
            AiCostTracker.event(
              feature: 'course_generation_harness',
              event: 'reconcile_stale_ready_triggered',
              extra: {'target_skill': harnessSkill},
            ),
          );
        }
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
          // a failed row is retried only once by the harness policy.
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
      // The debug lane must also invoke the provider when the persisted row
      // is already present but its artifact is stale for the current course
      // contract (for example an older Writing role-play artifact). In that
      // case there is no local plan diff, so gating this call on
      // `coursePersisted` makes automatic completion hand-off look like a
      // no-op forever. A completion callback is a preparation request even
      // when the queued row was already persisted by a previous callback.
      // `syncAdaptiveCoursePlan` correctly returns false for that no-op push,
      // so using only `coursePersisted` here strands the row forever in a
      // queued state. Generation never implies navigation; opening remains a
      // separate, explicit learner action.
      if (coursePersisted ||
          reconcileQueuedHarnessRow ||
          harnessSkill != null ||
          forcePrepare) {
        await sync.prepareAdaptiveCourseLessons(harnessSkill: harnessSkill);
        if (harnessSkill == null) {
          await _prepareMediaBuffer(sync, store, profile, operationEpoch);
        }
      }
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
      var refreshed = ref
          .read(adaptiveCourseStoreProvider)
          .ensureCurrentPlan(profile);
      // A failed Grammar (or other harness) artifact is requeued locally at
      // most once by AdaptiveCourseStore. Persist that explicit transition
      // and immediately spend the single bounded endpoint retry while the
      // learner is still on the roadmap, instead of leaving an hourglass that
      // only changes after a full app restart. The server still caps provider
      // repair attempts and terminal rows are never retried in a loop.
      if (harnessSkill != null &&
          refreshed.sessions.any(
            (session) =>
                session.primarySkill.wireName == harnessSkill &&
                session.generationStatus == 'queued' &&
                session.generationAttempts > 0 &&
                session.generationError == 'Retrying failed lesson once',
          )) {
        await sync.syncAdaptiveCoursePlan(refreshed);
        if (!mounted || operationEpoch != _generationEpoch) return;
        await sync.prepareAdaptiveCourseLessons(harnessSkill: harnessSkill);
        if (!mounted || operationEpoch != _generationEpoch) return;
        await sync.hydrateAdaptiveCourses();
        if (!mounted || operationEpoch != _generationEpoch) return;
        refreshed = ref
            .read(adaptiveCourseStoreProvider)
            .ensureCurrentPlan(profile);
      }
      // Deliberately do not return or open a generated row here. Completion
      // prepares and persists the next lesson, but selecting it is always an
      // explicit learner action on the roadmap or home screen.
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
    // Most course activities bubble up a boolean, while Grammar's native
    // five-step flow returns its richer result object. Treat both as a
    // completed activity so the next queued lesson is prepared in production
    // as well as in the serial debug lane.
    final completed =
        result == true ||
        (result is GrammarCourseSessionResult && result.completed);
    if (!completed) return;

    final store = ref.read(adaptiveCourseStoreProvider);
    final shouldAdvanceHarness = harness.shouldAdvanceAfter(
      sequence: session.sequence,
      primarySkill: session.primarySkill,
    );
    if (shouldAdvanceHarness) {
      // The activity wrapper normally records completion after its practice
      // route returns. Keep the harness trigger self-contained as well: a
      // short debug grammar run must advance even when the wrapper's
      // time/evidence gate has not accumulated enough seconds yet.
      store.markCompleted(session.contentKey);
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
    }

    // Production completion normally already marked the adaptive row. Read
    // the current local spec rather than trusting the projected roadmap row,
    // then explicitly await its push before `_prepareCourse` hydrates remote
    // state. This closes the race that previously left Unit 3 reading and
    // listening in `queued` forever after Unit 3 vocabulary finished.
    final completedSpec = store.sessionById(session.id);
    if (completedSpec?.status != 'completed') return;
    await ref
        .read(syncServiceProvider)
        .syncAdaptiveCourseSession(completedSpec!);
    if (!mounted) return;

    await _prepareCourse(
      harnessSkill: harness.active ? harness.targetWireName : null,
      onlyIfNewHarnessRow: shouldAdvanceHarness,
      forcePrepare: true,
    );
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

  /// The next personalized row is prepared automatically after completion.
  /// This lane is status-only: learners do not manually generate course
  /// lessons, so the UI cannot accidentally create duplicate rows or skip the
  /// one-at-a-time progression contract.
  Widget _generateNextCard(List<SpeakRoadmapSession> sessions) {
    final hasInFlight =
        _preparingCourse ||
        sessions.any((session) => session.generationStatus == 'generating');
    if (hasInFlight) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: PersonalizedGenerationLoader(
          content: 'your next lesson',
          detail: 'Building the lesson buffer…',
          icon: Icons.auto_awesome_rounded,
          compact: true,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: V3Card(
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: DesignTokens.nightAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                sessions.any((session) => session.generationStatus == 'failed')
                    ? 'We’ll retry the next lesson automatically.'
                    : 'Your next lesson is prepared automatically after you finish.',
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.nightMuted),
              ),
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
    final personalized =
        session.sequence > AdaptiveCourseStore.initialBatchSize;
    final buffered =
        personalized &&
        !session.completed &&
        session.contentReady &&
        session.generationStatus == 'ready';
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
                          ? 'Preparing automatically'
                          : failed
                          ? 'Generation failed — retrying automatically'
                          : 'Preparing automatically',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                  if (buffered) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Ready in your lesson buffer',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.nightAccent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (preparing || (_preparingCourse && queued))
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
    SpeakSkill.grammar => Icons.spellcheck_rounded,
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
