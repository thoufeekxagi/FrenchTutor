import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/app_router.dart';
import '../../design/tokens.dart';
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

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(learningStoreProvider).profile();
    final level = _beginnerBand(profile.level);
    final lessons = _lessonsFor(_mode, level);
    final selected = lessons.firstWhere(
      (lesson) => lesson.id == _selectedLessonId,
      orElse: () => lessons.first,
    );
    final completed = ref.watch(storageServiceProvider).completedContentKeys();

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
            _featuredLesson(selected, completed.contains(selected.id)),
            const SizedBox(height: 28),
            _sectionLabel(_sectionTitle),
            const SizedBox(height: 10),
            if (_mode == SpeakingCourseMode.guided)
              ...lessons.map(
                (lesson) => _lessonRow(
                  lesson,
                  selected: lesson.id == selected.id,
                  complete: completed.contains(lesson.id),
                ),
              )
            else
              _lessonGrid(lessons, completed),
            if (_mode == SpeakingCourseMode.guided) ...[
              const SizedBox(height: 24),
              _sectionLabel('SPEAKING COLLECTIONS'),
              const SizedBox(height: 10),
              _collectionGrid(level),
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
      final exact = SpeakingCourseCatalog.freeTalkLessons
          .where((lesson) => lesson.level == level)
          .toList(growable: false);
      return exact.isNotEmpty ? exact : SpeakingCourseCatalog.freeTalkLessons;
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
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DesignTokens.nightText,
          ),
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
          icon: const Icon(Icons.tune_rounded, color: DesignTokens.nightAccent),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF4A3518), Color(0xFF201A12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
                decoration: const BoxDecoration(
                  color: DesignTokens.nightAccent,
                  shape: BoxShape.circle,
                ),
                child: Icon(lesson.icon, color: Colors.black, size: 26),
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
                const Icon(
                  Icons.check_circle_rounded,
                  color: DesignTokens.success,
                ),
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
              const Icon(
                Icons.check_circle_rounded,
                color: DesignTokens.success,
                size: 19,
              )
            else
              const Icon(
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
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, index) {
        final lesson = lessons[index];
        return GestureDetector(
          onTap: () => setState(() => _selectedLessonId = lesson.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: lesson.id == _selectedLessonId
                  ? DesignTokens.nightAccentSoft
                  : DesignTokens.nightSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: lesson.id == _selectedLessonId
                    ? DesignTokens.nightAccent
                    : DesignTokens.nightHairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      lesson.icon,
                      color: DesignTokens.nightAccent,
                      size: 24,
                    ),
                    const Spacer(),
                    if (completed.contains(lesson.id))
                      const Icon(
                        Icons.check_circle_rounded,
                        color: DesignTokens.success,
                        size: 18,
                      ),
                  ],
                ),
                const Spacer(),
                Text(lesson.title, style: _body(15, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${lesson.lines.length} turns · ${lesson.level}',
                  style: _body(11).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _collectionGrid(String level) {
    final collections = SpeakingCourseCatalog.units
        .where((collection) => collection.level == level)
        .toList(growable: false);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: collections.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.3,
      ),
      itemBuilder: (context, index) {
        final collection = collections[index];
        final firstLesson = collection.lessons.firstWhere(
          (lesson) => lesson.mode == SpeakingCourseMode.guided,
          orElse: () => collection.lessons.first,
        );
        return GestureDetector(
          onTap: () => setState(() => _selectedLessonId = firstLesson.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DesignTokens.nightSurface,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: DesignTokens.nightHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  collection.icon,
                  color: DesignTokens.nightAccent,
                  size: 25,
                ),
                const Spacer(),
                Text(
                  collection.title,
                  style: _body(14, weight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${collection.lessons.length} lessons',
                  style: _body(10).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
        );
      },
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
          steps: [
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
