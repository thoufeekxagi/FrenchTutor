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
import '../../services/serial_request_queue.dart';
import '../../services/speak_language_profile.dart';
import '../../services/speak_roadmap_service.dart';
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
  static const _manualGenerationSkills = <SpeakSkill>[
    SpeakSkill.vocabulary,
    SpeakSkill.reading,
    SpeakSkill.listening,
    SpeakSkill.writing,
    SpeakSkill.speaking,
    SpeakSkill.grammar,
  ];

  bool _preparingCourse = false;
  bool _manualGenerationInFlight = false;
  bool _appIsForeground = true;
  bool _recoveringPendingGeneration = false;
  bool _refreshingRoadmapFromCloud = false;
  String? _automaticRetrySessionId;
  SpeakSkill? _manualGenerationSkill;
  int _generationEpoch = 0;
  Timer? _generationStatusRefreshTimer;
  final SerialRequestQueue<String, void> _coursePreparationQueue =
      SerialRequestQueue<String, void>();

  static const _recoverableVocabularyBalanceError =
      'Vocabulary must balance reviewed and new lexical items';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Recover queued work regardless of build mode or the optional generation
    // harness. A persisted successor is real learner work, not harness-only
    // work, and must never be stranded by a debug configuration.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_recoverPendingProductionGeneration());
    });
  }

  @override
  void dispose() {
    _generationEpoch++;
    _generationStatusRefreshTimer?.cancel();
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
      _appIsForeground = false;
      _generationEpoch++;
    } else if (state == AppLifecycleState.resumed) {
      _appIsForeground = true;
      if (mounted) unawaited(_recoverPendingProductionGeneration());
    }
  }

  Future<void> _refreshRoadmapFromCloud() async {
    if (!mounted || _refreshingRoadmapFromCloud) return;
    _refreshingRoadmapFromCloud = true;
    try {
      await ref.read(syncServiceProvider).hydrateAdaptiveCourses();
      if (mounted) {
        // Hydration writes through a separate store instance, so it does not
        // emit this screen's provider notifications.
        setState(() {});
        _syncGenerationStatusRefreshTimer();
      }
    } catch (error, stackTrace) {
      debugPrint('Course roadmap refresh failed: $error\n$stackTrace');
    } finally {
      _refreshingRoadmapFromCloud = false;
    }
  }

  void _syncGenerationStatusRefreshTimer() {
    final profile = ref.read(learningStoreProvider).profile();
    final plan = ref.read(adaptiveCourseStoreProvider).currentPlan(profile);
    final hasGeneratingSession =
        plan?.sessions.any(
          (session) => session.generationStatus == 'generating',
        ) ??
        false;
    if (!hasGeneratingSession) {
      _generationStatusRefreshTimer?.cancel();
      _generationStatusRefreshTimer = null;
      return;
    }
    _generationStatusRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (mounted && _appIsForeground) {
          unawaited(_refreshRoadmapFromCloud());
        }
      },
    );
  }

  Future<void> _recoverPendingProductionGeneration() async {
    await _coursePreparationQueue.waitForIdle();
    if (!mounted || !_appIsForeground) return;
    if (_recoveringPendingGeneration) return;
    _recoveringPendingGeneration = true;
    final sync = ref.read(syncServiceProvider);
    try {
      await sync.drainOutbox(limit: 25);
      await _refreshRoadmapFromCloud();
      if (!mounted) return;
      final profile = ref.read(learningStoreProvider).profile();
      final plan = ref.read(adaptiveCourseStoreProvider).currentPlan(profile);
      if (plan == null) return;
      final pendingIds =
          plan.sessions
              .where(
                (session) =>
                    session.sequence > AdaptiveCourseStore.initialBatchSize &&
                    session.status != 'replaced' &&
                    session.status != 'completed' &&
                    (session.generationStatus == 'queued' ||
                        (session.generationStatus == 'failed' &&
                            session.generationAttempts == 2 &&
                            session.generationError ==
                                _recoverableVocabularyBalanceError)),
              )
              .toList(growable: false)
            ..sort((left, right) => left.sequence.compareTo(right.sequence));
      // Recovery is bounded so a resume can never fan out an unbounded set
      // of model calls. Every lesson still goes through the same single-row
      // preparation path as automatic completion and the manual button.
      const recoveryBatchLimit = 8;
      for (final candidate in pendingIds.take(recoveryBatchLimit)) {
        if (!mounted || !_appIsForeground) return;
        final store = ref.read(adaptiveCourseStoreProvider);
        var latest = store.sessionById(candidate.id);
        if (latest?.generationStatus == 'failed' &&
            latest?.generationAttempts == 2 &&
            latest?.generationError == _recoverableVocabularyBalanceError) {
          latest = store.requeueFailedSession(
            candidate.id,
            generationError: 'Retrying vocabulary after validator fix',
          );
          if (latest != null) {
            await sync.syncAdaptiveCourseSession(latest);
          }
        }
        if (latest?.generationStatus != 'queued' ||
            latest?.status == 'replaced' ||
            latest?.status == 'completed') {
          continue;
        }
        await _prepareCourse(targetSessionId: candidate.id);
      }
    } catch (error, stackTrace) {
      // Recovery is best-effort. The status lane remains informative if the
      // device is offline or the endpoint is temporarily unavailable.
      debugPrint(
        'Pending Course generation recovery failed: $error\n$stackTrace',
      );
    } finally {
      _recoveringPendingGeneration = false;
    }
  }

  /// Prepares one exact persisted Course lesson after completion, recovery,
  /// or an explicit learner request. The skill lane is chosen by the session
  /// row, so debug settings cannot redirect a Reading completion to Grammar.
  Future<void> _prepareCourse({
    required String targetSessionId,
    bool allowAutomaticRetry = true,
  }) {
    final requestKey = 'session:$targetSessionId';
    if (_preparingCourse) {
      debugPrint(
        '[COURSE_AUTO] queued preparation behind active request: $requestKey',
      );
    }
    return _coursePreparationQueue.run(requestKey, () async {
      if (!mounted || !_appIsForeground) return;
      await _runCoursePreparation(
        targetSessionId: targetSessionId,
        allowAutomaticRetry: allowAutomaticRetry,
      );
    });
  }

  Future<void> _runCoursePreparation({
    required String targetSessionId,
    bool allowAutomaticRetry = true,
  }) async {
    _preparingCourse = true;
    if (mounted) setState(() {});
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
      final plan = store.ensureCurrentPlan(profile);
      await sync.syncAdaptiveCoursePlan(plan);
      if (!mounted || operationEpoch != _generationEpoch) return;
      // Even when the row was already persisted by a previous attempt, this
      // completion/recovery is an explicit provider-claim request. Never gate
      // it on whether syncing produced a new plan diff.
      await sync.prepareAdaptiveCourseLessons(sessionId: targetSessionId);
      if (!mounted || operationEpoch != _generationEpoch) return;
      await sync.hydrateAdaptiveCourses();
      if (!mounted || operationEpoch != _generationEpoch) return;

      // Production gets one delayed automatic retry of the exact same row.
      // A second failure is terminal until the learner taps the retry icon;
      // lifecycle recovery and rebuilds never retry failed rows.
      if (allowAutomaticRetry) {
        final firstResult = store.sessionById(targetSessionId);
        if (firstResult?.generationStatus == 'failed' &&
            firstResult?.generationAttempts == 1) {
          _automaticRetrySessionId = targetSessionId;
          if (mounted) setState(() {});
          await Future<void>.delayed(const Duration(seconds: 5));
          if (!mounted || operationEpoch != _generationEpoch) return;
          await sync.prepareAdaptiveCourseLessons(sessionId: targetSessionId);
          if (!mounted || operationEpoch != _generationEpoch) return;
          await sync.hydrateAdaptiveCourses();
          _automaticRetrySessionId = null;
          if (mounted) setState(() {});
        }
      }
      // Deliberately do not return or open a generated row here. Completion
      // prepares and persists the next lesson, but selecting it is always an
      // explicit learner action on the roadmap or home screen.
    } finally {
      _automaticRetrySessionId = null;
      _preparingCourse = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openSession(SpeakRoadmapSession session) async {
    await AppRouter.push<Object?>(context, (_) => _screenFor(session));
    if (!mounted) return;
    setState(() {});
    // The activity starts successor preparation in the background so the
    // learner stays in the lesson. Pull its persisted state on return and
    // resume only queued work; this makes the same visible roadmap buffer
    // report automatic preparation without opening the next lesson.
    unawaited(_recoverPendingProductionGeneration());
  }

  Future<void> _retryFailedSession(SpeakRoadmapSession session) async {
    if (_preparingCourse) return;
    final store = ref.read(adaptiveCourseStoreProvider);
    final failed = store.sessionById(session.id);
    if (failed?.generationStatus != 'failed') return;
    final queued = store.requeueFailedSession(session.id);
    if (queued == null || queued.generationStatus != 'queued') return;
    setState(() {});
    await ref.read(syncServiceProvider).syncAdaptiveCourseSession(queued);
    if (!mounted) return;
    await _prepareCourse(
      targetSessionId: session.id,
      allowAutomaticRetry: false,
    );
  }

  SpeakSkill _suggestManualGenerationSkill(List<SpeakRoadmapSession> sessions) {
    SpeakRoadmapSession? latest;
    for (final session in sessions) {
      if (!_manualGenerationSkills.contains(session.primarySkill) ||
          session.unit < 2) {
        continue;
      }
      if (latest == null || session.sequence > latest.sequence) {
        latest = session;
      }
    }
    return latest?.primarySkill ?? SpeakSkill.vocabulary;
  }

  Future<void> _chooseManualGenerationSkill(
    List<SpeakRoadmapSession> sessions,
  ) async {
    final selected =
        _manualGenerationSkill ?? _suggestManualGenerationSkill(sessions);
    final value = await showV3Picker<SpeakSkill>(
      context: context,
      title: 'Choose the next lesson skill',
      selected: selected,
      options: _manualGenerationSkills
          .map(
            (skill) => V3PickerOption<SpeakSkill>(
              value: skill,
              label: skill.label,
              description:
                  'Prepare the next ${skill.label.toLowerCase()} lesson.',
              icon: _iconFor(skill),
            ),
          )
          .toList(growable: false),
    );
    if (!mounted || value == null) return;
    setState(() => _manualGenerationSkill = value);
  }

  Future<void> _generateNextForSkill(SpeakSkill skill) async {
    if (_preparingCourse || _manualGenerationInFlight) return;
    _manualGenerationInFlight = true;
    setState(() {});
    try {
      final unlocked = await requirePremiumArea(
        context,
        ref,
        PremiumArea.course,
        source: 'course_roadmap_manual_generation',
      );
      if (!mounted || !unlocked) return;

      final profile = ref.read(learningStoreProvider).profile();
      final store = ref.read(adaptiveCourseStoreProvider);
      final before = store.ensureCurrentPlan(profile);
      AdaptiveCourseSessionSpec? latestInLane;
      for (final session in before.sessions) {
        if (session.primarySkill != skill ||
            session.unit < 2 ||
            session.status == 'replaced') {
          continue;
        }
        if (latestInLane == null || session.sequence > latestInLane.sequence) {
          latestInLane = session;
        }
      }
      if (latestInLane == null) {
        _showGenerationMessage(
          'This skill is not available in your Course yet.',
        );
        return;
      }

      final targetUnit = latestInLane.unit + 1;
      var expanded = store.ensureSuccessorForSkill(profile, skill);
      AdaptiveCourseSessionSpec? successor;
      for (final session in expanded.sessions) {
        if (session.unit == targetUnit &&
            session.primarySkill == skill &&
            session.status != 'replaced') {
          successor = session;
          break;
        }
      }
      if (successor == null) {
        _showGenerationMessage(
          'The next ${skill.label.toLowerCase()} lesson could not be queued.',
        );
        return;
      }
      if (successor.isContentReady) {
        _showGenerationMessage(
          'Your next ${skill.label.toLowerCase()} lesson is already ready.',
        );
        return;
      }
      if (successor.generationStatus == 'generating') {
        _showGenerationMessage(
          'Your next ${skill.label.toLowerCase()} lesson is already being prepared.',
        );
        return;
      }

      if (successor.generationStatus == 'failed') {
        final requeued = store.requeueFailedSession(successor.id);
        if (requeued == null) return;
        successor = requeued;
        await ref.read(syncServiceProvider).syncAdaptiveCourseSession(requeued);
        if (!mounted) return;
        expanded = store.currentPlan(profile) ?? expanded;
      }

      final planSynced = await ref
          .read(syncServiceProvider)
          .syncAdaptiveCoursePlan(expanded);
      if (!mounted) return;
      if (!planSynced) {
        _showGenerationMessage(
          'Your lesson is saved on this device and will sync when you are online.',
        );
        return;
      }
      await _prepareCourse(targetSessionId: successor.id);
      if (!mounted) return;
      final refreshed = store.sessionById(successor.id);
      if (refreshed?.isContentReady == true) {
        _showGenerationMessage(
          'Your next ${skill.label.toLowerCase()} lesson is ready.',
        );
      } else if (refreshed?.generationStatus == 'failed') {
        _showGenerationMessage(
          'Preparation did not finish. You can retry this lesson from its row.',
        );
      }
    } finally {
      _manualGenerationInFlight = false;
      if (mounted) setState(() {});
    }
  }

  void _showGenerationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Tapping a subscription-locked Unit 3+ lesson must show the paywall,
  /// the same as every other premium area — never a silent no-op.
  Future<void> _openPaywall(SpeakRoadmapSession session) async {
    final unlocked = await requireCourseUnitAccess(
      context,
      ref,
      session.unit,
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
    final courseGate = ref.watch(subscriptionGateServiceProvider);
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
            // Units 1–2 are the permanent free onboarding path. Unit 3+
            // remains generated/visible but cannot be opened without Pro.
            _unitPath(
              context,
              roadmap,
              unit,
              locked: courseGate.isCourseUnitLocked(unit),
            ),
            const SizedBox(height: 14),
          ],
          _generateNextCard(roadmap.sessions),
        ],
      ),
    );
  }

  /// Automatic completion and this optional learner trigger both add slots
  /// to the same Course path and use the same preparation pipeline.
  Widget _generateNextCard(List<SpeakRoadmapSession> sessions) {
    final hasInFlight =
        _manualGenerationInFlight ||
        _preparingCourse ||
        sessions.any(
          (session) =>
              session.sequence > AdaptiveCourseStore.initialBatchSize &&
              !session.completed &&
              (session.generationStatus == 'generating' ||
                  session.generationStatus == 'queued'),
        );
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
    final selected =
        _manualGenerationSkill ?? _suggestManualGenerationSkill(sessions);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: V3Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: DesignTokens.nightAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generate next lesson',
                        style: DesignTokens.body(
                          15,
                          weight: FontWeight.w700,
                        ).copyWith(color: DesignTokens.nightText),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Add an upcoming lesson to your Course path.',
                        style: DesignTokens.body(
                          12,
                        ).copyWith(color: DesignTokens.nightMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Selected skill ${selected.label}. Change skill.',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _chooseManualGenerationSkill(sessions),
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: DesignTokens.nightSurfaceRaised,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: DesignTokens.nightHairline),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _iconFor(selected),
                              size: 20,
                              color: DesignTokens.nightAccent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selected.label,
                                style: DesignTokens.body(
                                  14,
                                  weight: FontWeight.w700,
                                ).copyWith(color: DesignTokens.nightText),
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: DesignTokens.nightAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  button: true,
                  label: 'Generate next ${selected.label} lesson',
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: DesignTokens.nightAccent,
                        foregroundColor: DesignTokens.ink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _generateNextForSkill(selected),
                      child: const Icon(Icons.add_rounded, size: 28),
                    ),
                  ),
                ),
              ],
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
    final automaticallyRetrying = _automaticRetrySessionId == session.id;
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
                          : automaticallyRetrying
                          ? 'Trying once more…'
                          : failed
                          ? 'Couldn’t prepare this lesson. Tap retry.'
                          : 'Preparing automatically',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                  if (buffered) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Your next lesson is ready',
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.nightAccent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (preparing || automaticallyRetrying || (personalized && queued))
              const _LessonPreparationIndicator()
            else if (failed)
              IconButton(
                tooltip: 'Retry lesson preparation',
                onPressed: _preparingCourse
                    ? null
                    : () => _retryFailedSession(session),
                icon: const Icon(Icons.refresh_rounded),
                iconSize: 21,
                color: DesignTokens.nightAccent,
              )
            else if (queued)
              Icon(
                Icons.schedule_rounded,
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
