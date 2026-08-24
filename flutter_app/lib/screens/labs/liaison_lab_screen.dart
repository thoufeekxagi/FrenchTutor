import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/generated_grammar_story_store.dart';
import '../../data/liaison_curriculum_catalog.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/profile.dart';
import '../../models/session.dart';
import '../../providers/database_provider.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/personalized_generation_loader.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../lessons/grammar_workshop_screen.dart';
import '../speak/speak_ui.dart';
import 'liaison_lesson_screen.dart';

const _liaisonGrammarPoint = 'Liaison';

class LiaisonLabScreen extends ConsumerStatefulWidget {
  const LiaisonLabScreen({super.key, this.autoStart = false});

  final bool autoStart;

  @override
  ConsumerState<LiaisonLabScreen> createState() => _LiaisonLabScreenState();
}

class _LiaisonLabScreenState extends ConsumerState<LiaisonLabScreen> {
  LiaisonStartMode _mode = LiaisonStartMode.wordPairs;
  bool _isGenerating = false;
  String? _generationStage;
  String? _errorText;

  String get _selectedLevel => LiaisonCurriculumCatalog.normalizeLevel(
    ref.read(learningStoreProvider).profile().level,
  );

  List<LiaisonCurriculumLesson> get _lessons =>
      LiaisonCurriculumCatalog.forLevel(_selectedLevel);

  LiaisonCurriculumLesson get _nextLesson {
    final store = ref.read(learningStoreProvider);
    for (final lesson in _lessons) {
      if (store.lessonStatus(lesson.progressId).status != 'completed') {
        return lesson;
      }
    }
    return _lessons.first;
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openLesson(_nextLesson, closeAfter: true));
      });
    }
  }

  Future<void> _openLesson(
    LiaisonCurriculumLesson lesson, {
    bool closeAfter = false,
  }) async {
    final result = await AppRouter.push<bool>(
      context,
      (_) => LiaisonLessonScreen(lesson: lesson, startMode: _mode),
      fullscreenDialog: true,
    );
    if (!mounted) return;
    setState(() {});
    if (closeAfter) Navigator.of(context).pop(result == true);
  }

  Future<void> _generateStory() async {
    setState(() {
      _isGenerating = true;
      _generationStage = 'explanation';
      _errorText = null;
    });
    try {
      final agent = ref.read(lessonAgentServiceProvider);
      final explanation = await agent.buildLiaisonExplanation(
        levelBand: _selectedLevel,
      );
      if (!mounted) return;
      setState(() => _generationStage = 'story');
      final passage = await agent.buildLiaisonStory(
        levelBand: _selectedLevel,
        explanation: explanation,
      );
      if (!mounted) return;
      setState(() => _generationStage = 'quiz');
      final generated = await agent.buildLiaisonQuiz(
        passage: passage,
        levelBand: _selectedLevel,
      );
      final story = GeneratedGrammarStory(
        id: newGeneratedGrammarStoryId(),
        grammarPoint: _liaisonGrammarPoint,
        levelBand: _selectedLevel,
        explanation: explanation,
        passage: passage,
        quiz: generated.quiz,
        keywords: generated.keywords,
        createdAt: DateTime.now(),
      );
      ref.read(generatedGrammarStoryStoreProvider).insert(story);
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _generationStage = null;
      });
      await AppRouter.push<GrammarWorkshopResult>(
        context,
        (_) => GrammarWorkshopScreen(story: story, showFinishButton: true),
        fullscreenDialog: true,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorText =
            'Liaison story failed during ${_generationStage ?? 'generation'}: $error';
        _generationStage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return Scaffold(
        backgroundColor: SpeakColors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final store = ref.watch(learningStoreProvider);
    final sessions = ref
        .read(storageServiceProvider)
        .getAllSessions()
        .where((session) => session.stage == 'liaison')
        .take(5)
        .toList();
    final generated = ref
        .read(generatedGrammarStoryStoreProvider)
        .list()
        .where((story) => story.grammarPoint == _liaisonGrammarPoint)
        .take(5)
        .toList();
    final completed = _lessons
        .where(
          (lesson) =>
              store.lessonStatus(lesson.progressId).status == 'completed',
        )
        .length;

    return Scaffold(
      backgroundColor: SpeakColors.background,
      appBar: AppBar(
        backgroundColor: SpeakColors.background,
        foregroundColor: SpeakColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Liaison', style: DesignTokens.display(24)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: SpeakColors.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  LearnerLevel.displayLabel(_selectedLevel),
                  style: DesignTokens.label(
                    12,
                  ).copyWith(color: SpeakColors.accent),
                ),
              ),
            ),
          ),
        ],
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text('Hear the words connect', style: DesignTokens.display(31)),
            const SizedBox(height: 8),
            Text(
              'Learn the sound, say it clearly, then carry it through a sentence.',
              style: DesignTokens.body(
                14,
              ).copyWith(color: SpeakColors.inkSoft, height: 1.45),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: CupertinoIcons.link,
                    title: 'Word pairs',
                    selected: _mode == LiaisonStartMode.wordPairs,
                    onTap: () =>
                        setState(() => _mode = LiaisonStartMode.wordPairs),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeCard(
                    icon: CupertinoIcons.text_quote,
                    title: 'Sentences',
                    selected: _mode == LiaisonStartMode.sentences,
                    onTap: () =>
                        setState(() => _mode = LiaisonStartMode.sentences),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeCard(
                    icon: CupertinoIcons.book,
                    title: 'Read aloud',
                    selected: _mode == LiaisonStartMode.readAloud,
                    onTap: () =>
                        setState(() => _mode = LiaisonStartMode.readAloud),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            KickerText('Continue · $completed of ${_lessons.length}'),
            const SizedBox(height: 10),
            _ContinueCard(
              lesson: _nextLesson,
              onTap: () => _openLesson(_nextLesson),
            ),
            const SizedBox(height: 28),
            const KickerText('Your liaison path'),
            const SizedBox(height: 10),
            for (final entry in _groupedLessons.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  entry.key,
                  style: DesignTokens.body(15, weight: FontWeight.w700),
                ),
              ),
              for (final lesson in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _LessonTile(
                    lesson: lesson,
                    completed:
                        store.lessonStatus(lesson.progressId).status ==
                        'completed',
                    onTap: () => _openLesson(lesson),
                  ),
                ),
            ],
            const SizedBox(height: 26),
            const KickerText('Create a practice story'),
            const SizedBox(height: 10),
            SpeakCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate an extra story after the prepared path. It never replaces your saved lessons.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  if (_isGenerating)
                    PersonalizedGenerationLoader(
                      content: 'liaison story',
                      detail: 'Building ${_generationStage ?? 'lesson'}…',
                      compact: true,
                    )
                  else
                    SpeakPrimaryButton(
                      label: 'Generate with AI',
                      icon: CupertinoIcons.wand_stars,
                      onTap: _generateStory,
                    ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorText!,
                      style: DesignTokens.body(
                        12,
                      ).copyWith(color: DesignTokens.danger),
                    ),
                  ],
                ],
              ),
            ),
            if (sessions.isNotEmpty || generated.isNotEmpty) ...[
              const SizedBox(height: 28),
              const KickerText('Recent liaison'),
              const SizedBox(height: 10),
              for (final session in sessions)
                _RecentTile(
                  title: session.topic ?? 'Liaison practice',
                  subtitle: 'Open saved lesson',
                  onTap: () => _openRecent(session),
                ),
              for (final story in generated)
                _RecentTile(
                  title: story.displayTitle,
                  subtitle: 'Generated story · ${story.levelBand}',
                  onTap: () => AppRouter.push(
                    context,
                    (_) => GrammarWorkshopScreen(story: story),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, List<LiaisonCurriculumLesson>> get _groupedLessons {
    final grouped = <String, List<LiaisonCurriculumLesson>>{};
    for (final lesson in _lessons) {
      grouped.putIfAbsent(lesson.collection, () => []).add(lesson);
    }
    return grouped;
  }

  void _openRecent(Session session) {
    final lesson = session.contentKey == null
        ? null
        : LiaisonCurriculumCatalog.byProgressId(session.contentKey!);
    if (lesson == null) {
      setState(() => _errorText = 'This saved liaison lesson is unavailable.');
      return;
    }
    unawaited(_openLesson(lesson));
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 104,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SpeakColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? SpeakColors.accent : SpeakColors.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: SpeakColors.accent, size: 22),
            Text(title, style: DesignTokens.body(12, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.lesson, required this.onTap});

  final LiaisonCurriculumLesson lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _TapCard(
    onTap: onTap,
    child: Row(
      children: [
        _CircleIcon(icon: CupertinoIcons.link),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lesson.title,
                style: DesignTokens.body(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                lesson.linkedDisplay,
                style: DesignTokens.body(
                  12,
                ).copyWith(color: SpeakColors.inkSoft),
              ),
            ],
          ),
        ),
        Icon(CupertinoIcons.play_fill, color: SpeakColors.accent),
      ],
    ),
  );
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({
    required this.lesson,
    required this.completed,
    required this.onTap,
  });

  final LiaisonCurriculumLesson lesson;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _TapCard(
    onTap: onTap,
    child: Row(
      children: [
        Icon(
          completed
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.waveform,
          color: completed ? DesignTokens.success : SpeakColors.accent,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lesson.title,
                style: DesignTokens.body(14, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                lesson.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  12,
                ).copyWith(color: SpeakColors.inkSoft),
              ),
            ],
          ),
        ),
        const Icon(CupertinoIcons.chevron_right, size: 17),
      ],
    ),
  );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: _TapCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(CupertinoIcons.clock, color: SpeakColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ],
            ),
          ),
          const Icon(CupertinoIcons.chevron_right, size: 17),
        ],
      ),
    ),
  );
}

class _TapCard extends StatelessWidget {
  const _TapCard({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: SpeakCard(child: child),
  );
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: SpeakColors.accentSoft,
    ),
    child: Icon(icon, color: SpeakColors.accent),
  );
}
