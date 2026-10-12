import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/app_router.dart';
import '../../design/appearance_colors.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../screens/speak/speak_course_activity_screen.dart';
import '../../screens/speak/speak_review_screen.dart';
import '../../services/course_generation_test_harness.dart';
import '../../services/speak_roadmap_service.dart';
import '../lesson/v3_course.dart';
import '../lesson/v3_lesson.dart';
import '../lesson/v3_lesson_player.dart';
import '../ui/v3_ui.dart';

/// Learn tab. Screen contract:
///
/// User arrived to: open the app to study.
/// They must understand: what to do next, how long it takes, how far the exam is.
/// Primary action: Start lesson (exactly one).
/// Secondary: Review, and Path to browse units.
/// Success state: a lesson opened, or "all caught up" when nothing is ready.
/// Must not contain: tiles of skills, streak pressure, a photo hero, fake data.
///
/// Data is real: the existing roadmap and adaptive plan. Nothing is invented.
class V3LearnScreen extends ConsumerStatefulWidget {
  const V3LearnScreen({super.key});

  @override
  ConsumerState<V3LearnScreen> createState() => _V3LearnScreenState();
}

class _V3LearnScreenState extends ConsumerState<V3LearnScreen> {
  var _tab = 0;
  int? _openUnit;
  DateTime? _examDate;
  List<V3Lesson> _course = const [];
  Set<String> _done = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadCourse());
    unawaited(_loadExamDate());
    unawaited(_ensureUpcomingMedia());
  }

  Future<void> _loadCourse() async {
    final course = await V3Course.load();
    final done = await V3Progress.completed();
    if (!mounted) return;
    setState(() {
      _course = course;
      _done = done;
    });
  }

  V3Lesson? get _nextAuthored {
    for (final lesson in _course) {
      if (!_done.contains(lesson.id)) return lesson;
    }
    return null;
  }

  Future<void> _openLesson(V3Lesson lesson) async {
    await AppRouter.push<bool>(
      context,
      (_) => V3LessonPlayer(lesson: lesson),
      fullscreenDialog: true,
    );
    if (mounted) unawaited(_loadCourse());
  }

  Future<void> _loadExamDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tcf_exam_date');
    if (!mounted) return;
    setState(() => _examDate = raw == null ? null : DateTime.tryParse(raw));
  }

  /// Keeps the next lessons prepared. Idempotent and guarded by SyncService's
  /// single in-flight generation gate (same work the old Home did).
  Future<void> _ensureUpcomingMedia() async {
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
        final prepared = await sync.prepareAdaptiveCourseLessons();
        if (prepared == 0) break;
        await sync.hydrateAdaptiveCourses();
        plan = store.ensureMediaBuffer(profile);
      }
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Learn media buffer preparation failed: $error\n$stackTrace');
    }
  }

  Future<void> _open(SpeakRoadmapSession session) async {
    await AppRouter.push(
      context,
      (_) => SpeakCourseActivityScreen(session: session),
    );
    if (mounted) {
      setState(() {});
      unawaited(_ensureUpcomingMedia());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final completed = ref.watch(storageServiceProvider).completedContentKeys();
    final store = ref.read(adaptiveCourseStoreProvider);
    final plan = store.currentPlan(profile) ?? store.ensureCurrentPlan(profile);
    final roadmap = SpeakRoadmapService.build(
      profile,
      completedContentKeys: completed,
      adaptiveSessions: plan.sessions,
    );
    final level = profile.level.toLowerCase();
    final levelChip = const {'a1', 'a2', 'b1', 'b2'}.contains(level)
        ? level.toUpperCase()
        : 'A1';

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TCF CANADA', style: V3Type.eyebrow()),
                    const SizedBox(height: 6),
                    Text('Learn', style: V3Type.hero(44)),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  levelChip,
                  style: V3Type.strong(14, DesignTokens.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _segment('Today', 0),
              const SizedBox(width: 24),
              _segment('Path', 1),
            ],
          ),
          const SizedBox(height: 20),
          if (_tab == 0) ..._today(roadmap) else ..._path(roadmap),
        ],
      ),
    );
  }

  Widget _segment(String label, int index) {
    final on = _tab == index;
    return V3Pressable(
      key: ValueKey('learn.segment.${label.toLowerCase()}'),
      label: label,
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? DesignTokens.ink : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: V3Type.strong(
            17,
            on ? DesignTokens.ink : DesignTokens.inkSoft,
          ),
        ),
      ),
    );
  }

  // ---- Today -------------------------------------------------------------

  List<Widget> _today(SpeakRoadmap roadmap) {
    final next = roadmap.nextSession;
    final days = _examDate?.difference(DateTime.now()).inDays;
    return [
      if (days != null && days >= 0) ...[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: DesignTokens.hairline),
            boxShadow: DesignTokens.surfaceShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXAM IN',
                      style: V3Type.eyebrow(DesignTokens.inkSoft),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      days == 1 ? '1 day' : '$days days',
                      style: V3Type.title(30),
                    ),
                  ],
                ),
              ),
              Text(
                'Target NCLC 7',
                style: V3Type.strong(14, DesignTokens.mastery),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
      _heroFor(next),
      const SizedBox(height: 14),
      V3Pressable(
        key: const ValueKey('learn.review'),
        label: 'Time to review',
        onTap: () => AppRouter.push(context, (_) => const SpeakReviewScreen()),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: DesignTokens.hairline),
            boxShadow: DesignTokens.surfaceShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Time to review', style: V3Type.strong(18)),
                    const SizedBox(height: 4),
                    Text(
                      'Words and mistakes from your lessons',
                      style: V3Type.body(14),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: DesignTokens.inkSoft,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// The authored TCF course comes first. The legacy adaptive course fills in
  /// until authored lessons cover it.
  Widget _heroFor(SpeakRoadmapSession? legacyNext) {
    final authored = _nextAuthored;
    if (authored != null) {
      return _heroCard(
        eyebrow: 'NEXT  ·  ${authored.minutes} MIN',
        title: authored.title,
        subtitle: authored.subtitle.isEmpty
            ? 'TCF Canada course'
            : authored.subtitle,
        onStart: () => _openLesson(authored),
      );
    }
    if (legacyNext == null) {
      return _heroCard(
        eyebrow: 'ALL CAUGHT UP',
        title: 'You are all caught up',
        subtitle: 'New lessons appear here as soon as they are ready.',
      );
    }
    return _heroCard(
      eyebrow: 'NEXT  ·  ${legacyNext.estimatedMinutes} MIN',
      title: legacyNext.title,
      subtitle: 'Unit ${legacyNext.unit}: ${legacyNext.unitTitle}',
      onStart: () => _open(legacyNext),
    );
  }

  Widget _heroCard({
    required String eyebrow,
    required String title,
    required String subtitle,
    VoidCallback? onStart,
  }) {
    // Brand-blue hero in both appearances: white text on the fixed blue keeps
    // contrast, where the lighter dark-mode action blue would wash out.
    const onBlue = Colors.white;
    final dim = onBlue.withValues(alpha: 0.8);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppearanceColors.blueLight,
            Color.lerp(AppearanceColors.blueLight, Colors.black, 0.3)!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: V3Type.eyebrow(dim)),
          const SizedBox(height: 12),
          Text(title, style: V3Type.title(30, color: onBlue)),
          const SizedBox(height: 8),
          Text(subtitle, style: V3Type.body(15, dim)),
          if (onStart != null) ...[
            const SizedBox(height: 22),
            V3Pressable(
              key: const ValueKey('learn.startLesson'),
              label: 'Start lesson',
              onTap: onStart,
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: onBlue,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Start lesson',
                      style: V3Type.strong(16, AppearanceColors.blueLight),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: AppearanceColors.blueLight,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Path --------------------------------------------------------------

  List<Widget> _path(SpeakRoadmap roadmap) {
    final byUnit = <int, List<SpeakRoadmapSession>>{};
    for (final s in roadmap.sessions) {
      byUnit.putIfAbsent(s.unit, () => []).add(s);
    }
    final units = byUnit.keys.toList()..sort();
    final currentUnit = roadmap.nextSession?.unit;
    return [
      for (final unit in units) ...[
        _unitRow(unit, byUnit[unit]!, unit == currentUnit),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _unitRow(int unit, List<SpeakRoadmapSession> sessions, bool current) {
    final done = sessions.where((s) => s.completed).length;
    final finished = done == sessions.length;
    final open = _openUnit == unit;
    final stateColor = finished
        ? DesignTokens.success
        : current
        ? DesignTokens.primary
        : DesignTokens.hairline;
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Column(
        children: [
          V3Pressable(
            key: ValueKey('learn.unit.$unit'),
            label: 'Unit $unit, ${sessions.first.unitTitle}',
            onTap: () => setState(() => _openUnit = open ? null : unit),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 44,
                    decoration: BoxDecoration(
                      color: stateColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UNIT $unit',
                          style: V3Type.eyebrow(DesignTokens.inkSoft),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sessions.first.unitTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: V3Type.strong(17),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$done of ${sessions.length} lessons',
                          style: V3Type.body(13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: DesignTokens.inkSoft,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            for (final s in sessions)
              V3Pressable(
                key: ValueKey('learn.lesson.${s.contentKey}'),
                label: 'Lesson, ${s.title}',
                onTap: s.unlocked && s.contentReady ? () => _open(s) : null,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(38, 12, 18, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: DesignTokens.hairline),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title, style: V3Type.strong(15)),
                            const SizedBox(height: 2),
                            Text(
                              '${s.estimatedMinutes} min',
                              style: V3Type.body(12.5),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        s.completed
                            ? Icons.check_circle_rounded
                            : (s.unlocked && s.contentReady)
                            ? Icons.play_circle_outline_rounded
                            : Icons.lock_outline_rounded,
                        color: s.completed
                            ? DesignTokens.success
                            : DesignTokens.inkSoft,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
