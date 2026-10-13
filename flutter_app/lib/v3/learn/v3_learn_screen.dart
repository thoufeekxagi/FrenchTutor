import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/app_router.dart';
import '../../design/appearance_colors.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
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
/// They must understand: what to do next, how long it takes, how far along
/// they are, and how far the exam is.
/// Primary action: Start (or resume) the next lesson. Exactly one.
/// Secondary: Path to pick any lesson, Stories to read.
/// Success state: a lesson opens at the right step and finishing it moves the
/// "next" card on.
/// Must not contain: AI-generated lessons, fake progress, photo heroes.
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
    final stories = await V3Stories.load();
    final storiesDone = await V3StoryProgress.done();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tcf_exam_date');
    if (!mounted) return;
    setState(() {
      _course = course;
      _done = done;
      _pos = pos;
      _stories = stories;
      _storiesDone = storiesDone;
      _examDate = raw == null ? null : DateTime.tryParse(raw);
      _loaded = true;
    });
  }

  V3Lesson? get _next {
    for (final lesson in _course) {
      if (!_done.contains(lesson.id)) return lesson;
    }
    return null;
  }

  Future<void> _openLesson(V3Lesson lesson) async {
    await AppRouter.push<bool>(
      context,
      (_) => V3LessonPlayer(lesson: lesson, startAt: _pos[lesson.id] ?? 0),
      fullscreenDialog: true,
    );
    if (mounted) unawaited(_load());
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
                  chip,
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
              const SizedBox(width: 24),
              _segment('Stories', 2),
            ],
          ),
          const SizedBox(height: 20),
          if (!_loaded)
            const SizedBox(height: 240)
          else if (_tab == 0)
            ..._today()
          else if (_tab == 1)
            ..._path()
          else
            const V3StoriesPanel(),
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

  List<Widget> _today() {
    final real = _course.where((l) => !l.dev).toList();
    final doneCount = real.where((l) => _done.contains(l.id)).length;
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
      _hero(),
      if (real.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: doneCount / real.length,
                  minHeight: 5,
                  backgroundColor: DesignTokens.hairline,
                  color: DesignTokens.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$doneCount of ${real.length} lessons',
              style: V3Type.body(13),
            ),
          ],
        ),
      ],
      if (_stories.isNotEmpty) ...[
        const SizedBox(height: 22),
        V3Pressable(
          key: const ValueKey('learn.readStory'),
          label: 'Read a story',
          onTap: () => setState(() => _tab = 2),
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
                      Text('Read a story', style: V3Type.strong(18)),
                      const SizedBox(height: 4),
                      Text(
                        'Short, tap any word, hear any line',
                        style: V3Type.body(14),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.arrow_right,
                  color: DesignTokens.inkSoft,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  Widget _hero() {
    final next = _next;
    if (next == null) {
      return _heroCard(
        eyebrow: _course.isEmpty ? 'LESSONS' : 'ALL DONE FOR NOW',
        title: _course.isEmpty
            ? 'No lessons found'
            : 'You finished every lesson',
        subtitle: _course.isEmpty
            ? 'Close and reopen the app. If this stays, contact support.'
            : 'More units are coming. Replay any lesson from Path or read a story.',
      );
    }
    final at = _pos[next.id] ?? 0;
    return _heroCard(
      eyebrow: at > 0
          ? 'RESUME  ·  STEP ${at + 1} OF ${next.steps.length}'
          : 'NEXT  ·  ${next.minutes} MIN',
      title: next.title,
      subtitle: next.unit.isEmpty
          ? next.subtitle
          : '${next.unitLabel}: ${next.unitTitle}',
      action: at > 0 ? 'Resume lesson' : 'Start lesson',
      onStart: () => _openLesson(next),
    );
  }

  Widget _heroCard({
    required String eyebrow,
    required String title,
    required String subtitle,
    String action = 'Start lesson',
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
              label: action,
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
                      action,
                      style: V3Type.strong(16, AppearanceColors.blueLight),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      CupertinoIcons.arrow_right,
                      size: 18,
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
      onTap: () => _openLesson(l),
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
                    at > 0 && !done
                        ? '${l.minutes} min  ·  in progress'
                        : '${l.minutes} min',
                    style: V3Type.body(12.5),
                  ),
                ],
              ),
            ),
            Icon(
              done
                  ? CupertinoIcons.checkmark_circle_fill
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
