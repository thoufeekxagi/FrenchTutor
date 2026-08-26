// The active catalog uses the square lesson grid below.
// ignore_for_file: unused_element

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../data/database/speaking_lesson_codec.dart';
import '../../data/database/speaking_lesson_store.dart';
import '../../flow/stage_outcome.dart';
import '../../models/speaking_course.dart';
import '../../providers/database_provider.dart';
import 'speak_roleplay_screen.dart';
import 'speak_settings_screen.dart';
import 'speaking_lesson_flow_screen.dart';

/// The independent Speaking home opened from Practice -> Speaking.
///
/// It never replaces the app dashboard and never routes a speaking card into
/// another product. The permanent A1/A2 foundation is available even when no
/// generated adaptive lesson exists yet.
class SpeakingCourseHomeScreen extends ConsumerStatefulWidget {
  const SpeakingCourseHomeScreen({super.key});

  @override
  ConsumerState<SpeakingCourseHomeScreen> createState() =>
      _SpeakingCourseHomeScreenState();
}

class _SpeakingCourseHomeScreenState
    extends ConsumerState<SpeakingCourseHomeScreen> {
  SpeakingCourseMode _mode = SpeakingCourseMode.guided;
  String? _selectedLessonId;
  final List<SpeakingCourseLesson> _persistedLessons = [];
  bool _isGenerating = false;
  bool _isReplenishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreSpeakingCatalog());
    });
  }

  Future<void> _restoreSpeakingCatalog() async {
    try {
      await ref.read(syncServiceProvider).hydrateSpeakingLessons();
      _reloadPersistedLessons();
      if (mounted) setState(() {});
      final profile = ref.read(learningStoreProvider).profile();
      unawaited(_ensureReserve(_mode, _beginnerBand(profile.level)));
    } catch (error, stackTrace) {
      debugPrint('Speaking catalog restore failed: $error\n$stackTrace');
    }
    // Publishing is deliberately fire-and-forget. The bundled catalog is
    // already rendered locally, so a network write never delays first paint.
    unawaited(
      ref.read(syncServiceProvider).publishDefaultSpeakingCatalog().catchError((
        error,
      ) {
        debugPrint('Speaking catalog publish failed: $error');
      }),
    );
  }

  void _reloadPersistedLessons() {
    final lessons = ref.read(speakingLessonStoreProvider).list();
    _persistedLessons
      ..clear()
      ..addAll(lessons);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final level = _beginnerBand(profile.level);
    final visibleLessons = _lessonsFor(_mode, level);
    final completed = ref.watch(storageServiceProvider).completedContentKeys();
    final nextLesson = _nextLesson(visibleLessons, completed);
    final selected = visibleLessons.firstWhere(
      (lesson) => lesson.id == _selectedLessonId,
      orElse: () => nextLesson ?? visibleLessons.first,
    );

    return Scaffold(
      backgroundColor: DesignTokens.nightCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
          children: [
            _header(context, level),
            const SizedBox(height: 25),
            Text('Build confidence to speak', style: _display(31)),
            const SizedBox(height: 7),
            Text(
              'Choose a speaking lesson, hear the model, say the line, and see exactly what matched.',
              style: _body(
                14,
              ).copyWith(color: DesignTokens.nightMuted, height: 1.4),
            ),
            const SizedBox(height: 22),
            _modePicker(),
            const SizedBox(height: 18),
            _sectionLabel('EXTRA PRACTICE'),
            const SizedBox(height: 10),
            _featuredLesson(selected, completed.contains(selected.id)),
            const SizedBox(height: 28),
            _sectionLabel(_sectionTitle),
            const SizedBox(height: 10),
            _lessonGrid(visibleLessons, completed),
            const SizedBox(height: 24),
            _generateMoreCard(level),
          ],
        ),
      ),
    );
  }

  String get _sectionTitle => switch (_mode) {
    SpeakingCourseMode.guided => 'BEGINNER SPEAKING LESSONS',
    SpeakingCourseMode.freeTalk => 'FREE TALK TOPICS',
    SpeakingCourseMode.roleplay => 'ROLEPLAY SCENES',
  };

  List<SpeakingCourseLesson> _lessonsFor(
    SpeakingCourseMode mode,
    String level,
  ) {
    List<SpeakingCourseLesson> bundled;
    if (mode == SpeakingCourseMode.freeTalk) {
      bundled = SpeakingCourseCatalog.freeTalkForLevel(level);
    } else if (mode == SpeakingCourseMode.roleplay) {
      bundled = SpeakingCourseCatalog.roleplaysForLevel(level);
    } else {
      final all = <SpeakingCourseLesson>[
        for (final collection in SpeakingCourseCatalog.units)
          for (final lesson in collection.lessons)
            if (lesson.mode == mode) lesson,
      ];
      final exact = all
          .where((lesson) => lesson.level == level)
          .toList(growable: false);
      bundled = exact.isNotEmpty ? exact : all;
    }
    return _dedupeLessons([
      ...bundled,
      ..._persistedLessons.where(
        (lesson) => lesson.mode == mode && lesson.level == level,
      ),
    ]);
  }

  List<SpeakingCourseLesson> _dedupeLessons(
    Iterable<SpeakingCourseLesson> lessons,
  ) {
    final ids = <String>{};
    final fingerprints = <String>{};
    final result = <SpeakingCourseLesson>[];
    for (final lesson in lessons) {
      final fingerprint = speakingLessonFingerprint(lesson);
      if (ids.contains(lesson.id) || fingerprints.contains(fingerprint)) {
        continue;
      }
      ids.add(lesson.id);
      fingerprints.add(fingerprint);
      result.add(lesson);
    }
    return result;
  }

  String _beginnerBand(String raw) {
    final normalised = raw.trim().toUpperCase();
    return normalised == 'A1' || normalised == 'ZERO' || normalised == 'BASICS'
        ? 'A1'
        : 'A2';
  }

  Widget _header(BuildContext context, String level) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: DesignTokens.nightText),
        ),
        const SizedBox(width: 4),
        Expanded(child: Text('Speaking', style: _display(23))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: DesignTokens.nightAccentSoft,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            level,
            style: _body(
              12,
              weight: FontWeight.w800,
            ).copyWith(color: DesignTokens.nightAccent),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Speaking settings',
          onPressed: () =>
              AppRouter.push(context, (_) => const SpeakSettingsScreen()),
          icon: Icon(Icons.tune_rounded, color: DesignTokens.nightAccent),
        ),
      ],
    );
  }

  Widget _modePicker() {
    const modes = [
      (SpeakingCourseMode.guided, 'Guided', Icons.mic_none_rounded),
      (SpeakingCourseMode.freeTalk, 'Free talk', Icons.forum_outlined),
      (SpeakingCourseMode.roleplay, 'Roleplay', Icons.theater_comedy_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: DesignTokens.nightHairline),
      ),
      child: Row(
        children: [
          for (final entry in modes)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _mode = entry.$1;
                    _selectedLessonId = null;
                  });
                  final profile = ref.read(learningStoreProvider).profile();
                  unawaited(
                    _ensureReserve(entry.$1, _beginnerBand(profile.level)),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 54,
                  decoration: BoxDecoration(
                    color: _mode == entry.$1
                        ? DesignTokens.nightAccent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        entry.$3,
                        size: 18,
                        color: _mode == entry.$1
                            ? Colors.black
                            : DesignTokens.nightMuted,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.$2,
                        style: _body(10, weight: FontWeight.w800).copyWith(
                          color: _mode == entry.$1
                              ? Colors.black
                              : DesignTokens.nightMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _featuredLesson(SpeakingCourseLesson lesson, bool complete) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: DesignTokens.nightAccent),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: DesignTokens.nightSurfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  lesson.icon,
                  color: DesignTokens.nightAccent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson.title,
                      style: _body(18, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lesson.level} · ${lesson.lines.length} speaking checks',
                      style: _body(12).copyWith(color: DesignTokens.nightMuted),
                    ),
                  ],
                ),
              ),
              if (complete)
                Icon(Icons.check_circle_rounded, color: DesignTokens.success),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            lesson.subtitle,
            style: _body(14).copyWith(color: DesignTokens.nightMuted),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              _phase(Icons.volume_up_outlined, 'Hear'),
              _phase(Icons.mic_none_rounded, 'Say'),
              _phase(Icons.check_circle_outline_rounded, 'Check'),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => _startLesson(lesson),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DesignTokens.nightAccent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                complete ? 'Practise again' : 'Start speaking',
                style: _body(
                  15,
                  weight: FontWeight.w800,
                ).copyWith(color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phase(IconData icon, String label) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: DesignTokens.nightAccent),
          const SizedBox(width: 5),
          Text(label, style: _body(11, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _lessonRow(
    SpeakingCourseLesson lesson, {
    required bool selected,
    required bool complete,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedLessonId = lesson.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected
              ? DesignTokens.nightAccentSoft
              : DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected
                ? DesignTokens.nightAccent
                : DesignTokens.nightHairline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: selected
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightSurfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(
                lesson.icon,
                color: selected ? Colors.black : DesignTokens.nightAccent,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.title, style: _body(14, weight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    lesson.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _body(11).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
              ),
            ),
            if (complete)
              Icon(
                Icons.check_circle_rounded,
                color: DesignTokens.success,
                size: 19,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: DesignTokens.nightAccent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _lessonGrid(
    List<SpeakingCourseLesson> lessons,
    Set<String> completed,
  ) {
    return GridView.builder(
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
        return _SpeakingTopicCard(
          lesson: lesson,
          selected: lesson.id == _selectedLessonId,
          complete: completed.contains(lesson.id),
          onTap: () => setState(() => _selectedLessonId = lesson.id),
        );
      },
    );
  }

  SpeakingCourseLesson? _nextLesson(
    List<SpeakingCourseLesson> lessons,
    Set<String> completed,
  ) {
    for (final lesson in lessons) {
      if (!completed.contains(lesson.id)) return lesson;
    }
    return lessons.isEmpty ? null : lessons.first;
  }

  Widget _generateMoreCard(String level) {
    final freeTalk = _mode == SpeakingCourseMode.freeTalk;
    final roleplay = _mode == SpeakingCourseMode.roleplay;
    final format = freeTalk
        ? 'topic'
        : roleplay
        ? 'scene'
        : 'lesson';
    final formatLabel = freeTalk
        ? 'Free Talk'
        : roleplay
        ? 'roleplay'
        : 'practice';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _isGenerating ? null : () => _generateLesson(level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
        decoration: BoxDecoration(
          color: DesignTokens.nightSurface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: DesignTokens.nightHairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_rounded, color: DesignTokens.nightAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isGenerating
                        ? 'Generating a $level $format…'
                        : 'Generate more $level $formatLabel',
                    style: _body(14, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    freeTalk
                        ? 'Create a fresh level-matched topic with prompts, starters, and pronunciation help.'
                        : roleplay
                        ? 'Create a fresh level-matched scene with Marie prompts and learner replies.'
                        : 'Create one short, level-matched conversation with Gemini when you want a fresh challenge.',
                    style: _body(
                      11,
                    ).copyWith(color: DesignTokens.nightMuted, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              _isGenerating
                  ? Icons.hourglass_top_rounded
                  : Icons.chevron_right_rounded,
              color: DesignTokens.nightAccent,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateLesson(String level, {SpeakingCourseMode? mode}) async {
    final requestedMode = mode ?? _mode;
    setState(() => _isGenerating = true);
    try {
      final lesson = await _generateValidatedLesson(
        level: level,
        mode: requestedMode,
        avoidTitles: _lessonsFor(
          requestedMode,
          level,
        ).map((lesson) => lesson.title),
      );
      final inserted = ref
          .read(speakingLessonStoreProvider)
          .insertGenerated(lesson);
      if (!inserted) {
        throw StateError('The generated lesson duplicated an existing lesson.');
      }
      _reloadPersistedLessons();
      if (!mounted) return;
      setState(() {
        _selectedLessonId = lesson.id;
        _isGenerating = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lesson generation failed: $error')),
      );
    }
  }

  Future<SpeakingCourseLesson> _generateValidatedLesson({
    required String level,
    required SpeakingCourseMode mode,
    required Iterable<String> avoidTitles,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final agent = ref.read(lessonAgentServiceProvider);
        final passage = switch (mode) {
          SpeakingCourseMode.guided =>
            await agent.buildStandaloneSpeakingLesson(
              levelBand: level,
              avoidTitles: avoidTitles,
            ),
          SpeakingCourseMode.freeTalk =>
            await agent.buildStandaloneFreeTalkTopic(
              levelBand: level,
              avoidTitles: avoidTitles,
            ),
          SpeakingCourseMode.roleplay => await agent.buildStandaloneRoleplay(
            levelBand: level,
            avoidTitles: avoidTitles,
          ),
        };
        return SpeakingCourseLessonValidator.fromPassage(
          passage: passage,
          id: SpeakingLessonStore.newId(),
          level: level,
          mode: mode,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'The generator did not produce a validated ${mode.name} lesson: $lastError',
    );
  }

  Future<void> _ensureReserve(SpeakingCourseMode mode, String level) async {
    if (_isReplenishing || _isGenerating) return;
    final lessons = _lessonsFor(mode, level);
    final completed = ref.read(storageServiceProvider).completedContentKeys();
    final remaining = lessons
        .where((lesson) => !completed.contains(lesson.id))
        .length;
    if (remaining >= 10) return;

    _isReplenishing = true;
    try {
      for (var index = 0; index < 2; index++) {
        final current = _lessonsFor(mode, level);
        final avoidTitles = current.map((lesson) => lesson.title).toList();
        try {
          final lesson = await _generateValidatedLesson(
            level: level,
            mode: mode,
            avoidTitles: avoidTitles,
          );
          final inserted = ref
              .read(speakingLessonStoreProvider)
              .insertGenerated(lesson);
          if (inserted) {
            _reloadPersistedLessons();
            if (mounted) setState(() {});
          }
        } catch (error, stackTrace) {
          // Background replenishment must never change the current lesson or
          // show a scary error card. The validated row simply is not added;
          // the next reserve check can try again.
          debugPrint('Speaking reserve generation failed: $error\n$stackTrace');
        }
      }
    } finally {
      _isReplenishing = false;
    }
  }

  Future<void> _startLesson(SpeakingCourseLesson lesson) async {
    Object? result;
    if (lesson.mode == SpeakingCourseMode.roleplay) {
      result = await AppRouter.push<SpeakingResult>(
        context,
        (_) => SpeakRoleplayScreen(lesson: lesson),
        fullscreenDialog: true,
      );
    } else {
      result = await AppRouter.push<SpeakingResult>(
        context,
        (_) => SpeakingLessonFlowScreen(
          title: lesson.title,
          topic: lesson.subtitle,
          level: lesson.level,
          contentKey: lesson.id,
          steps: lesson.mode == SpeakingCourseMode.guided
              ? speakingStepsForCourseLines(lesson.lines, level: lesson.level)
              : [
                  for (final line in lesson.lines)
                    SpeakingPhraseStep(
                      french: line.french,
                      english: line.english,
                      partnerFrench: line.partnerFrench,
                      partnerEnglish: line.partnerEnglish,
                      tip: line.tip,
                      hintWords: line.hintWords,
                      hintWordsEnglish: line.hintWordsEnglish,
                      translationAlignment: line.translationAlignment,
                      partnerTranslationAlignment:
                          line.partnerTranslationAlignment,
                      openResponse: line.openResponse,
                    ),
                ],
        ),
        fullscreenDialog: true,
      );
    }
    if (!mounted || result is! SpeakingResult || !result.connected) return;
    ref
        .read(storageServiceProvider)
        .markCourseSessionCompleted(
          contentKey: lesson.id,
          topic: lesson.title,
          stage: lesson.mode.name,
        );
    setState(() {});
    unawaited(_ensureReserve(lesson.mode, lesson.level));
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: _body(
      12,
      weight: FontWeight.w800,
    ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.3),
  );

  TextStyle _display(double size) =>
      DesignTokens.display(size).copyWith(color: DesignTokens.nightText);

  TextStyle _body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(
        size,
        weight: weight,
      ).copyWith(color: DesignTokens.nightText);
}

class _SpeakingTopicCard extends StatelessWidget {
  const _SpeakingTopicCard({
    required this.lesson,
    required this.selected,
    required this.complete,
    required this.onTap,
  });

  final SpeakingCourseLesson lesson;
  final bool selected;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${lesson.title}, ${lesson.subtitle}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(11, 12, 9, 10),
          decoration: BoxDecoration(
            color: selected
                ? DesignTokens.nightAccentSoft
                : DesignTokens.nightSurface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? DesignTokens.nightAccent
                  : DesignTokens.nightHairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(lesson.icon, color: DesignTokens.nightAccent, size: 20),
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
                style: DesignTokens.body(
                  12,
                  weight: FontWeight.w700,
                ).copyWith(color: DesignTokens.nightText),
              ),
              const SizedBox(height: 3),
              Text(
                lesson.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  10,
                ).copyWith(color: DesignTokens.nightMuted, height: 1.15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
