// The active catalog uses the square lesson grid below.
// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../flow/stage_outcome.dart';
import '../../models/content_models.dart';
import '../../models/speaking_course.dart';
import '../../providers/database_provider.dart';
import '../../utils/speaking_translation_alignment.dart';
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
  final List<SpeakingCourseLesson> _generatedLessons = [];
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final level = _beginnerBand(profile.level);
    final lessons = [
      ..._lessonsFor(_mode, level),
      ..._generatedLessons.where(
        (lesson) => lesson.mode == _mode && lesson.level == level,
      ),
    ];
    final completed = ref.watch(storageServiceProvider).completedContentKeys();
    final nextLesson = _nextLesson(lessons, completed);
    final selected = lessons.firstWhere(
      (lesson) => lesson.id == _selectedLessonId,
      orElse: () => nextLesson ?? lessons.first,
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
            _lessonGrid(lessons, completed),
            if (_mode == SpeakingCourseMode.guided) ...[
              const SizedBox(height: 24),
              _generateMoreCard(level),
            ],
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
    if (mode == SpeakingCourseMode.freeTalk) {
      return SpeakingCourseCatalog.freeTalkForLevel(level);
    }
    if (mode == SpeakingCourseMode.roleplay) {
      return SpeakingCourseCatalog.roleplaysForLevel(level);
    }
    final all = <SpeakingCourseLesson>[
      for (final collection in SpeakingCourseCatalog.units)
        for (final lesson in collection.lessons)
          if (lesson.mode == mode) lesson,
    ];
    final exact = all
        .where((lesson) => lesson.level == level)
        .toList(growable: false);
    return exact.isNotEmpty ? exact : all;
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
                onTap: () => setState(() {
                  _mode = entry.$1;
                  _selectedLessonId = null;
                }),
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
      final avoidTitles = [
        ...SpeakingCourseCatalog.units
            .expand((unit) => unit.lessons)
            .map((lesson) => lesson.title),
        ...SpeakingCourseCatalog.freeTalkLessons.map((lesson) => lesson.title),
        ..._generatedLessons.map((lesson) => lesson.title),
      ];
      final passage = requestedMode == SpeakingCourseMode.freeTalk
          ? await ref
                .read(lessonAgentServiceProvider)
                .buildStandaloneFreeTalkTopic(
                  levelBand: level,
                  avoidTitles: avoidTitles,
                )
          : requestedMode == SpeakingCourseMode.roleplay
          ? await ref
                .read(lessonAgentServiceProvider)
                .buildStandaloneRoleplay(
                  levelBand: level,
                  avoidTitles: avoidTitles,
                )
          : await ref
                .read(lessonAgentServiceProvider)
                .buildStandaloneSpeakingLesson(
                  levelBand: level,
                  avoidTitles: avoidTitles,
                );
      final lesson = _lessonFromGeneratedPassage(
        passage,
        level,
        mode: requestedMode,
      );
      if (!mounted) return;
      setState(() {
        _generatedLessons.add(lesson);
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

  SpeakingCourseLesson _lessonFromGeneratedPassage(
    ReadingPassage passage,
    String level, {
    required SpeakingCourseMode mode,
  }) {
    if (mode == SpeakingCourseMode.guided) {
      for (final segment in passage.segments) {
        if (segment.fr.trim().isEmpty || segment.en.trim().isEmpty) {
          throw StateError(
            'Generated Guided Speaking lesson contains a missing French or '
            'English line.',
          );
        }
        // Validate before adding the lesson to the screen. A generated line
        // must have a real bilingual contract; it may not rely on a visual
        // fallback when the learner taps a word later.
        SpeakingTranslationAlignment.forPhrase(segment.fr, segment.en);
      }
    }
    if ((mode == SpeakingCourseMode.freeTalk ||
            mode == SpeakingCourseMode.roleplay) &&
        passage.segments.any(
          (segment) => segment.characterFr?.trim().isNotEmpty != true,
        )) {
      throw StateError('Generated speaking scene has an incomplete prompt.');
    }
    final lines = passage.segments
        .map(
          (segment) => SpeakingCourseLine(
            french: segment.fr,
            english: segment.en,
            partnerFrench: segment.characterFr,
            partnerEnglish: segment.characterEn,
            tip: segment.pronunciationTip,
            openResponse: mode == SpeakingCourseMode.freeTalk,
          ),
        )
        .toList(growable: false);
    if (lines.isEmpty) {
      throw StateError('Generated speaking lesson has no practice lines.');
    }
    return SpeakingCourseLesson(
      id: passage.id,
      title: passage.titleEn?.trim().isNotEmpty == true
          ? passage.titleEn!.trim()
          : passage.title,
      subtitle: 'A fresh $level conversation matched to your practice.',
      level: level,
      icon: Icons.auto_awesome_rounded,
      mode: mode,
      lines: lines,
    );
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
