import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../screens/labs/vocab_lab_screen.dart';
import '../../screens/labs/vocabulary_flashcards_screen.dart';
import '../lesson/v3_course.dart';
import '../lesson/v3_lesson.dart';
import '../lesson/v3_lesson_player.dart';
import '../story/v3_stories_panel.dart';
import '../story/v3_story.dart';
import '../story/v3_story_reader.dart';
import '../story/v3_story_store.dart';
import '../ui/v3_ui.dart';

/// Learn tab. Screen contract:
///
/// User arrived to: open the app to study.
/// They must understand: the next authored lesson and its duration, plus the
/// exam countdown when an exam date is saved. Full pathway progress lives in
/// the Path segment.
/// Primary action: Continue the course pathway. Exactly one.
/// Secondary: Review today's flashcards; Path and Stories stay in the top
/// segments.
/// Success state: the lesson opens at the saved step and moves the pathway on
/// when complete.
/// Must not contain: AI-generated lessons, fake progress, photos, or subtitles.
///
/// Everything comes from the bundled authored course. Progress is local.
class V3LearnScreen extends ConsumerStatefulWidget {
  const V3LearnScreen({super.key});

  @override
  ConsumerState<V3LearnScreen> createState() => _V3LearnScreenState();
}

class _V3LearnScreenState extends ConsumerState<V3LearnScreen> {
  var _tab = 0;
  var _loaded = false;
  List<V3Lesson> _course = const [];
  Set<String> _done = const {};
  Map<String, int> _pos = const {};
  String? _active;
  String? _lastDone;
  List<V3Story> _stories = const [];
  Set<String> _storiesDone = const {};
  String? _openUnit;
  DateTime? _examDate;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final course = await V3Course.load();
    final done = await V3Progress.completed();
    final pos = await V3Progress.positions();
    final active = await V3Progress.lastActive();
    final lastDone = await V3Progress.lastCompleted();
    final stories = await V3Stories.load();
    final storiesDone = await V3StoryProgress.done();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tcf_exam_date');
    if (!mounted) return;
    setState(() {
      _course = course;
      _done = done;
      _pos = pos;
      _active = active;
      _lastDone = lastDone;
      _stories = stories;
      _storiesDone = storiesDone;
      _examDate = raw == null ? null : DateTime.tryParse(raw);
      _loaded = true;
    });
  }

  /// Where Resume goes. One rule, kept in [V3Progress.pickNext].
  V3Lesson? get _next => V3Progress.pickNext(
    _course,
    _done,
    _pos,
    active: _active,
    lastCompleted: _lastDone,
  );

  /// [review] opens from the first step to look again. It never lowers real
  /// progress: the furthest step reached is kept and Resume still returns to it.
  Future<void> _openLesson(V3Lesson lesson, {bool review = false}) async {
    final reached = _pos[lesson.id] ?? 0;
    final finished = _done.contains(lesson.id);
    await AppRouter.push<bool>(
      context,
      (_) => V3LessonPlayer(
        lesson: lesson,
        startAt: review || finished ? 0 : reached,
        frontier: reached,
        reviewAll: finished,
      ),
      fullscreenDialog: true,
    );
    if (mounted) unawaited(_load());
  }

  /// A lesson row. Unfinished with progress: resume or look again. Finished:
  /// replay. Not started: start.
  Future<void> _tapLesson(V3Lesson lesson) async {
    final reached = _pos[lesson.id] ?? 0;
    if (_done.contains(lesson.id) || reached == 0) {
      return _openLesson(lesson);
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => V3Width(
        child: Container(
          key: const ValueKey('learn.sheet'),
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: DesignTokens.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: DesignTokens.hairline,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(lesson.title, style: V3Type.title(24)),
              const SizedBox(height: 4),
              Text(
                'You reached step ${reached + 1} of ${lesson.steps.length}.',
                style: V3Type.body(15),
              ),
              const SizedBox(height: 18),
              V3Button(
                key: const ValueKey('learn.sheet.resume'),
                label: 'Resume at step ${reached + 1}',
                onTap: () => Navigator.of(context).pop('resume'),
              ),
              const SizedBox(height: 10),
              V3Button(
                key: const ValueKey('learn.sheet.review'),
                label: 'Review from the start',
                kind: V3ButtonKind.ghost,
                trailingArrow: false,
                onTap: () => Navigator.of(context).pop('review'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await _openLesson(lesson, review: choice == 'review');
  }

  Future<void> _openStory(V3Story story) async {
    final storyPos = (await V3StoryProgress.positions())[story.id] ?? 0;
    if (!mounted) return;
    await AppRouter.push<bool>(
      context,
      (_) => V3StoryReader(story: story, startAt: storyPos),
    );
    if (mounted) unawaited(_load());
  }

  Future<void> _openReview() async {
    try {
      final entries = await ref.read(srsServiceProvider).dailyMixedQueue();
      if (!mounted) return;

      if (entries.isEmpty) {
        await AppRouter.push(context, (_) => const VocabLabScreen());
      } else {
        final profile = ref.read(learningStoreProvider).profile();
        await AppRouter.push<bool>(
          context,
          (_) => VocabularyFlashcardsScreen(
            title: 'Daily review',
            entries: entries,
            source: 'v3_daily_review',
            topic: 'Daily review',
            levelBand: profile.level.toUpperCase(),
            studyDepth: VocabularyStudyDepth.wordsAndSentences,
            storyExamples: ref
                .read(contentServiceProvider)
                .vocabExamplesFor(entries),
          ),
          fullscreenDialog: true,
        );
      }
      if (mounted) unawaited(_load());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review is unavailable right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = ref
        .watch(learningStoreProvider)
        .profile()
        .level
        .toLowerCase();
    final chip = const {'a1', 'a2', 'b1', 'b2'}.contains(level)
        ? level.toUpperCase()
        : 'A1';
    final days = _examDate?.difference(DateTime.now()).inDays;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wideToday = _tab == 0 && constraints.maxWidth >= 840;
          final contentWidth = wideToday
              ? constraints.maxWidth
              : constraints.maxWidth.clamp(0, 680).toDouble();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TCF CANADA', style: V3Type.eyebrow()),
                            const SizedBox(height: 4),
                            Text('Learn', style: V3Type.hero(36)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: DesignTokens.primarySoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              chip,
                              style: V3Type.strong(14, DesignTokens.primary),
                            ),
                          ),
                          if (days != null && days >= 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              days == 1
                                  ? 'Exam tomorrow'
                                  : 'Exam in $days days',
                              style: V3Type.body(12),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _segment('Today', 0),
                      const SizedBox(width: 24),
                      _segment('Path', 1),
                      const SizedBox(width: 24),
                      _segment('Stories', 2),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (!_loaded)
                    const SizedBox(height: 240)
                  else if (_tab == 0)
                    ..._today(wide: wideToday)
                  else if (_tab == 1)
                    ..._path()
                  else
                    const V3StoriesPanel(),
                ],
              ),
            ),
          );
        },
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
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.bottomLeft,
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

  List<Widget> _today({required bool wide}) {
    final review = _reviewShortcut();
    if (wide) {
      return [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _hero()),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: review),
          ],
        ),
      ];
    }
    return [_hero(), const SizedBox(height: 12), review];
  }

  Widget _hero() {
    final next = _next;
    if (next == null) {
      return _heroCard(
        eyebrow: 'CONTINUE PATH',
        title: _course.isEmpty ? 'No lessons found' : 'Path complete',
        detail: '',
        action: 'Open path',
        onStart: () => setState(() => _tab = 1),
      );
    }
    return _heroCard(
      eyebrow: 'CONTINUE PATH',
      title: next.title,
      detail: '${next.unitLabel} · ${next.minutes} min',
      action: 'Continue path',
      onStart: () => _openLesson(next),
    );
  }

  Widget _reviewShortcut() {
    return V3Pressable(
      key: const ValueKey('learn.review'),
      label: 'Review flashcards',
      onTap: _openReview,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.style_outlined, color: DesignTokens.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text('Review', style: V3Type.strong(16))),
            Icon(
              CupertinoIcons.arrow_right,
              color: DesignTokens.inkSoft,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard({
    required String eyebrow,
    required String title,
    required String detail,
    required String action,
    VoidCallback? onStart,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: V3Type.eyebrow()),
          const SizedBox(height: 10),
          Text(title, style: V3Type.title(25)),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(detail, style: V3Type.body(13)),
          ],
          const SizedBox(height: 16),
          V3Button(
            key: const ValueKey('learn.continuePath'),
            label: action,
            onTap: onStart,
          ),
        ],
      ),
    );
  }

  // ---- Path --------------------------------------------------------------

  List<Widget> _path() {
    final groups = <String, List<V3Lesson>>{};
    for (final l in _course) {
      groups.putIfAbsent(l.unit, () => []).add(l);
    }
    final nextUnit = _next?.unit;
    return [
      for (final entry in groups.entries) ...[
        _unitCard(entry.key, entry.value, entry.key == (_openUnit ?? nextUnit)),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _unitCard(String unit, List<V3Lesson> lessons, bool open) {
    final first = lessons.first;
    final done = lessons.where((l) => _done.contains(l.id)).length;
    final finished = done == lessons.length;
    final current = _next?.unit == unit;
    final stateColor = finished
        ? DesignTokens.success
        : current
        ? DesignTokens.primary
        : DesignTokens.hairline;
    final label = unit.isEmpty ? 'Dev' : first.unitLabel;
    final title = unit.isEmpty ? 'Test lessons' : first.unitTitle;
    final stories = [
      for (final s in _stories)
        if (s.unit == unit) s,
    ];
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
            label: '$label, $title',
            onTap: () => setState(() => _openUnit = open ? '' : unit),
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
                          label.toUpperCase(),
                          style: V3Type.eyebrow(DesignTokens.inkSoft),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: V3Type.strong(17),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$done of ${lessons.length} lessons',
                          style: V3Type.body(13),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    open
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 18,
                    color: DesignTokens.inkSoft,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            for (final l in lessons) _lessonRow(l),
            for (final s in stories) _storyRow(s),
          ],
        ],
      ),
    );
  }

  Widget _lessonRow(V3Lesson l) {
    final done = _done.contains(l.id);
    final at = _pos[l.id] ?? 0;
    return V3Pressable(
      key: ValueKey('learn.lesson.${l.id}'),
      label: 'Lesson, ${l.title}',
      onTap: () => _tapLesson(l),
      child: Container(
        padding: const EdgeInsets.fromLTRB(38, 12, 18, 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.title, style: V3Type.strong(15)),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? '${l.minutes} min  ·  tap to replay'
                        : at > 0
                        ? '${l.minutes} min  ·  in progress, step ${at + 1}'
                        : '${l.minutes} min',
                    style: V3Type.body(12.5),
                  ),
                ],
              ),
            ),
            Icon(
              done
                  ? CupertinoIcons.checkmark_circle_fill
                  : at > 0
                  ? CupertinoIcons.play_circle_fill
                  : CupertinoIcons.play_circle,
              color: done ? DesignTokens.success : DesignTokens.inkSoft,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _storyRow(V3Story s) {
    final done = _storiesDone.contains(s.id);
    return V3Pressable(
      key: ValueKey('learn.story.${s.id}'),
      label: 'Story, ${s.titleEn}',
      onTap: () => _openStory(s),
      child: Container(
        padding: const EdgeInsets.fromLTRB(38, 12, 18, 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: DesignTokens.hairline)),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.book, size: 18, color: DesignTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Story: ${s.title}', style: V3Type.strong(15)),
                  const SizedBox(height: 2),
                  Text(
                    '${s.minutes} min  ·  ${s.titleEn}',
                    style: V3Type.body(12.5),
                  ),
                ],
              ),
            ),
            Icon(
              done
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.chevron_right,
              color: done ? DesignTokens.success : DesignTokens.inkSoft,
              size: done ? 24 : 18,
            ),
          ],
        ),
      ),
    );
  }
}
