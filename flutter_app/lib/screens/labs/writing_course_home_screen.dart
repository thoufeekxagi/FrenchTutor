import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/writing_course.dart';
import '../../providers/database_provider.dart';
import '../../widgets/primary_action_button.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../lessons/writing_course_lesson_screen.dart';
import '../settings/settings_screen.dart';

class WritingCourseHomeScreen extends ConsumerStatefulWidget {
  const WritingCourseHomeScreen({super.key});

  @override
  ConsumerState<WritingCourseHomeScreen> createState() =>
      _WritingCourseHomeScreenState();
}

class _WritingCourseHomeScreenState
    extends ConsumerState<WritingCourseHomeScreen> {
  static const _reserveFloor = 2;
  static const _replenishCount = 3;

  WritingCourseMode _mode = WritingCourseMode.guided;
  String? _selectedLessonId;
  List<WritingCourseLesson> _generated = const [];
  bool _isGenerating = false;
  bool _isReplenishing = false;
  String? _generationError;

  @override
  void initState() {
    super.initState();
    _reloadGenerated();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_restoreWritingCatalog());
    });
  }

  Future<void> _restoreWritingCatalog() async {
    try {
      await ref.read(syncServiceProvider).hydrateWritingLessons();
      _reloadGenerated();
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Writing catalog restore failed: $error\n$stackTrace');
    }
    if (mounted) await _ensureReserve(_mode);
  }

  void _reloadGenerated() {
    _generated = ref.read(writingLessonStoreProvider).list();
  }

  String get _profileLevel {
    final raw = ref.read(learningStoreProvider).profile().level.toUpperCase();
    return switch (raw) {
      'A2' => 'A2',
      'B1' || 'CONVERSATIONAL' => 'B1',
      'B2' => 'B2',
      _ => 'A1',
    };
  }

  List<WritingCourseLesson> _lessonsFor(WritingCourseMode mode) {
    final lessons = <WritingCourseLesson>[
      ...WritingCourseCatalog.forMode(mode),
      ..._generated.where(
        (lesson) => lesson.mode == mode && lesson.level == _profileLevel,
      ),
    ];
    final fingerprints = <String>{};
    return lessons
        .where((lesson) => fingerprints.add(writingLessonFingerprint(lesson)))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final lessons = _lessonsFor(_mode);
    final selected = _selectedLesson(lessons);
    final completedCount = lessons.where(_isCompleted).length;
    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 34),
            children: [
              _header(context),
              const SizedBox(height: 22),
              Text(
                'Build confidence to write',
                style: DesignTokens.display(30),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a lesson, write in French, and improve one step at a time.',
                style: DesignTokens.body(
                  14,
                ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _LevelBadge(level: _profileLevel),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${lessons.length} lessons ready · $completedCount complete',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _modePicker(),
              const SizedBox(height: 24),
              _sectionLabel('NEXT ${_modeLabel(_mode).toUpperCase()} LESSON'),
              const SizedBox(height: 10),
              if (selected != null) _featuredLesson(selected),
              const SizedBox(height: 28),
              _sectionLabel('${_modeLabel(_mode).toUpperCase()} LESSONS'),
              const SizedBox(height: 10),
              _lessonGrid(lessons),
              const SizedBox(height: 22),
              _generateMoreCard(),
              if (_generationError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _generationError!,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: DesignTokens.ink,
          ),
        ),
        Expanded(
          child: Text(
            'Writing',
            textAlign: TextAlign.center,
            style: DesignTokens.display(21),
          ),
        ),
        Semantics(
          button: true,
          label: 'Writing settings',
          child: IconButton(
            onPressed: () =>
                AppRouter.push(context, (_) => const SettingsScreen()),
            icon: const Icon(Icons.tune_rounded),
            color: DesignTokens.primary,
          ),
        ),
      ],
    ),
  );

  Widget _modePicker() {
    const modes = [
      (WritingCourseMode.guided, 'Guided', Icons.edit_note_rounded),
      (WritingCourseMode.complete, 'Complete', Icons.checklist_rounded),
      (WritingCourseMode.roleplay, 'Roleplay', Icons.forum_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        children: [
          for (final entry in modes)
            Expanded(
              child: Semantics(
                button: true,
                selected: _mode == entry.$1,
                label: '${entry.$2} writing mode',
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _mode = entry.$1;
                      _selectedLessonId = null;
                      _generationError = null;
                    });
                    unawaited(_ensureReserve(entry.$1));
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: DesignTokens.durationFast,
                    constraints: const BoxConstraints(minHeight: 58),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _mode == entry.$1
                          ? DesignTokens.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          entry.$3,
                          size: 19,
                          color: _mode == entry.$1
                              ? DesignTokens.onPrimary
                              : DesignTokens.muted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.$2,
                          style: DesignTokens.label(10).copyWith(
                            color: _mode == entry.$1
                                ? DesignTokens.onPrimary
                                : DesignTokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _featuredLesson(WritingCourseLesson lesson) {
    final complete = _isCompleted(lesson);
    final phases = switch (lesson.mode) {
      WritingCourseMode.guided => const [
        (Icons.touch_app_outlined, 'Choose'),
        (Icons.edit_note_outlined, 'Build'),
        (Icons.refresh_rounded, 'Rewrite'),
      ],
      WritingCourseMode.complete => const [
        (Icons.question_mark_rounded, 'Read'),
        (Icons.checklist_rounded, 'Choose'),
        (Icons.keyboard_outlined, 'Recall'),
      ],
      WritingCourseMode.roleplay => const [
        (Icons.chat_bubble_outline, 'Read'),
        (Icons.edit_outlined, 'Reply'),
        (Icons.refresh_rounded, 'Rewrite'),
      ],
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
        border: Border.all(color: DesignTokens.primary),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
                ),
                child: Icon(lesson.icon, color: DesignTokens.primary, size: 27),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lesson.title, style: DesignTokens.display(18)),
                    const SizedBox(height: 4),
                    Text(
                      '${lesson.level} · ${lesson.steps.length} writing steps',
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.muted),
                    ),
                  ],
                ),
              ),
              if (complete)
                Icon(Icons.check_circle_rounded, color: DesignTokens.success),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            lesson.subtitle,
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 16),
          Divider(color: DesignTokens.hairline),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final phase in phases)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(phase.$1, color: DesignTokens.primary, size: 17),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          phase.$2,
                          style: DesignTokens.label(10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryActionButton(
            label: complete ? 'Practise again' : 'Start writing',
            onPressed: () => _startLesson(lesson),
          ),
        ],
      ),
    );
  }

  Widget _lessonGrid(List<WritingCourseLesson> lessons) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: lessons.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1,
    ),
    itemBuilder: (context, index) {
      final lesson = lessons[index];
      final selected = _selectedLessonId == lesson.id;
      return _WritingLessonCard(
        key: ValueKey(lesson.id),
        lesson: lesson,
        selected: selected,
        complete: _isCompleted(lesson),
        onTap: () => setState(() => _selectedLessonId = lesson.id),
      );
    },
  );

  Widget _generateMoreCard() => Material(
    color: DesignTokens.surface,
    borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
    child: InkWell(
      onTap: _isGenerating || _isReplenishing
          ? null
          : () => _generateOne(_mode, manual: true),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Row(
          children: [
            if (_isGenerating)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignTokens.primary,
                ),
              )
            else
              Icon(Icons.auto_awesome_rounded, color: DesignTokens.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isGenerating
                        ? 'Generating a $_profileLevel lesson…'
                        : 'Generate another $_profileLevel lesson',
                    style: DesignTokens.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Uses your level, goals, known words, interests, and recent corrections.',
                    style: DesignTokens.body(
                      11,
                    ).copyWith(color: DesignTokens.muted, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: DesignTokens.primary),
          ],
        ),
      ),
    ),
  );

  WritingCourseLesson? _selectedLesson(List<WritingCourseLesson> lessons) {
    if (lessons.isEmpty) return null;
    for (final lesson in lessons) {
      if (lesson.id == _selectedLessonId) return lesson;
    }
    for (final lesson in lessons) {
      if (!_isCompleted(lesson)) return lesson;
    }
    return lessons.first;
  }

  bool _isCompleted(WritingCourseLesson lesson) =>
      ref.read(learningStoreProvider).lessonStatus(lesson.id).status ==
      'completed';

  Future<void> _startLesson(WritingCourseLesson lesson) async {
    final result = await AppRouter.push<bool>(
      context,
      (_) => WritingCourseLessonScreen(lesson: lesson),
      fullscreenDialog: true,
    );
    if (!mounted || result != true) return;
    ref
        .read(learningStoreProvider)
        .setLessonStatus(lesson.id, 'completed', score: 1);
    setState(() {
      _selectedLessonId = null;
      _generationError = null;
    });
    unawaited(_ensureReserve(lesson.mode));
  }

  Future<void> _ensureReserve(WritingCourseMode mode) async {
    if (_isGenerating || _isReplenishing) return;
    final remaining = _lessonsFor(
      mode,
    ).where((lesson) => !_isCompleted(lesson)).length;
    if (remaining >= _reserveFloor) return;
    _isReplenishing = true;
    try {
      for (var index = 0; index < _replenishCount; index++) {
        try {
          await _generateOne(mode, manual: false);
        } catch (error, stackTrace) {
          debugPrint('Writing reserve generation failed: $error\n$stackTrace');
        }
      }
    } finally {
      _isReplenishing = false;
    }
  }

  Future<void> _generateOne(
    WritingCourseMode mode, {
    required bool manual,
  }) async {
    if (manual) {
      setState(() {
        _isGenerating = true;
        _generationError = null;
      });
    }
    try {
      final store = ref.read(learningStoreProvider);
      final profile = store.profile();
      final content = ref.read(contentServiceProvider);
      final current = _lessonsFor(mode);
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final lesson = await ref
              .read(lessonAgentServiceProvider)
              .generateWritingCourseLesson(
                mode: mode,
                levelBand: _profileLevel,
                learnerGoal: profile.goal,
                interests: profile.interests,
                knownVocab: content.knownVocabWords(store.allSRSStates()),
                mistakeTags: [
                  for (final mistake in store.topMistakeTags(limit: 5))
                    (
                      tag: mistake.tag,
                      description: mistake.description,
                      count: mistake.count,
                    ),
                ],
                avoidTitles: current.map((lesson) => lesson.title),
              );
          final fingerprint = writingLessonFingerprint(lesson);
          if (current.any(
            (existing) => writingLessonFingerprint(existing) == fingerprint,
          )) {
            throw StateError(
              'The generated lesson duplicated an existing lesson.',
            );
          }
          final inserted = ref
              .read(writingLessonStoreProvider)
              .insertGenerated(lesson);
          if (!inserted) {
            throw StateError('The generated lesson was already saved.');
          }
          _reloadGenerated();
          if (mounted) {
            setState(() {
              if (manual) _selectedLessonId = lesson.id;
              _generationError = null;
            });
          }
          return;
        } catch (error) {
          lastError = error;
        }
      }
      throw StateError('Could not create a validated lesson: $lastError');
    } catch (error) {
      if (manual && mounted) {
        setState(
          () => _generationError =
              'Couldn’t generate a lesson right now. Your saved lessons are still available.',
        );
      }
      if (!manual) rethrow;
    } finally {
      if (manual && mounted) setState(() => _isGenerating = false);
    }
  }

  String _modeLabel(WritingCourseMode mode) => switch (mode) {
    WritingCourseMode.guided => 'Guided',
    WritingCourseMode.complete => 'Complete',
    WritingCourseMode.roleplay => 'Roleplay',
  };

  Widget _sectionLabel(String label) => Text(
    label,
    style: DesignTokens.label(
      11,
    ).copyWith(color: DesignTokens.primary, letterSpacing: 1.2),
  );
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final String level;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 38, minWidth: 54),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: DesignTokens.primarySoft,
      borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
      border: Border.all(color: DesignTokens.primary),
    ),
    child: Text(
      level,
      style: DesignTokens.label(12).copyWith(color: DesignTokens.primary),
    ),
  );
}

class _WritingLessonCard extends StatelessWidget {
  const _WritingLessonCard({
    super.key,
    required this.lesson,
    required this.selected,
    required this.complete,
    required this.onTap,
  });

  final WritingCourseLesson lesson;
  final bool selected;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${lesson.title}, ${lesson.subtitle}',
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(11, 12, 9, 10),
        decoration: BoxDecoration(
          color: selected ? DesignTokens.primarySoft : DesignTokens.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? DesignTokens.primary : DesignTokens.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(lesson.icon, color: DesignTokens.primary, size: 20),
                const Spacer(),
                if (complete)
                  Icon(
                    Icons.check_circle_rounded,
                    color: DesignTokens.success,
                    size: 17,
                  ),
              ],
            ),
            const Spacer(),
            Text(
              lesson.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(12, weight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              lesson.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                10,
              ).copyWith(color: DesignTokens.muted, height: 1.15),
            ),
          ],
        ),
      ),
    ),
  );
}
