import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/generated_grammar_story_store.dart';
import '../../data/grammar_curriculum_catalog.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/practice_content_card.dart';
import '../../widgets/web/web_constrained_view.dart';
import 'grammar_lesson_flow_screen.dart';

class GrammarCurriculumHomeScreen extends ConsumerStatefulWidget {
  const GrammarCurriculumHomeScreen({
    super.key,
    required this.generatedHistory,
    required this.isGenerating,
    required this.generationError,
    required this.onGenerateAdvanced,
    required this.onOpenGenerated,
  });

  final List<GeneratedGrammarStory> generatedHistory;
  final bool isGenerating;
  final String? generationError;
  final Future<void> Function(GrammarCurriculumLesson lesson)
  onGenerateAdvanced;
  final ValueChanged<GeneratedGrammarStory> onOpenGenerated;

  @override
  ConsumerState<GrammarCurriculumHomeScreen> createState() =>
      _GrammarCurriculumHomeScreenState();
}

class _GrammarCurriculumHomeScreenState
    extends ConsumerState<GrammarCurriculumHomeScreen> {
  late String _level;
  GrammarPracticeMode _mode = GrammarPracticeMode.pickWord;
  String? _selectedLessonId;

  @override
  void initState() {
    super.initState();
    _level = GrammarCurriculumCatalog.normalizeLevel(
      ref.read(learningStoreProvider).profile().level,
    );
  }

  List<GrammarCurriculumLesson> get _lessons =>
      GrammarCurriculumCatalog.forLevel(_level);

  GrammarCurriculumLesson get _selectedLesson {
    final selected = GrammarCurriculumCatalog.byId(_selectedLessonId ?? '');
    if (selected != null && selected.level == _level) return selected;

    final progress = ref.read(learningStoreProvider).allLessonProgress();
    return _lessons.firstWhere(
      (lesson) => progress[lesson.progressId]?.status != 'completed',
      orElse: () => _lessons.first,
    );
  }

  Future<void> _openLesson(
    GrammarCurriculumLesson lesson, {
    GrammarPracticeMode? mode,
  }) async {
    final store = ref.read(learningStoreProvider);
    final existing = store.lessonStatus(lesson.progressId);
    if (existing.status == 'not_started') {
      store.setLessonStatus(lesson.progressId, 'in_progress');
    }
    await AppRouter.push<GrammarCurriculumResult>(
      context,
      (_) =>
          GrammarLessonFlowScreen(lesson: lesson, initialMode: mode ?? _mode),
      fullscreenDialog: true,
    );
    if (mounted) setState(() {});
  }

  Future<void> _reviewMistake() async {
    final progress = ref.read(learningStoreProvider).allLessonProgress();
    GrammarCurriculumLesson? target;
    for (final lesson in GrammarCurriculumCatalog.all) {
      final state = progress[lesson.progressId];
      if (state != null && state.status != 'completed' && state.score != null) {
        target = lesson;
        break;
      }
    }
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No grammar mistakes are waiting.')),
      );
      return;
    }
    final lesson = target;
    setState(() {
      _level = lesson.level;
      _selectedLessonId = lesson.id;
    });
    await _openLesson(lesson, mode: GrammarPracticeMode.pickWord);
  }

  Future<void> _chooseLevel() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DesignTokens.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grammar level', style: DesignTokens.display(22)),
              const SizedBox(height: 14),
              for (final level in GrammarCurriculumCatalog.levels)
                _LevelRow(
                  level: level,
                  selected: level == _level,
                  onTap: () => Navigator.of(sheetContext).pop(level),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == _level || !mounted) return;
    setState(() {
      _level = selected;
      _selectedLessonId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedLesson;
    final progress = ref.read(learningStoreProvider).allLessonProgress();
    final completed = _lessons
        .where((lesson) => progress[lesson.progressId]?.status == 'completed')
        .length;

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      appBar: AppBar(
        title: Text('Grammar', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Semantics(
            button: true,
            label: 'Change grammar level, current level $_level',
            child: TextButton(
              onPressed: _chooseLevel,
              style: TextButton.styleFrom(
                foregroundColor: DesignTokens.primary,
                backgroundColor: DesignTokens.primarySoft,
                minimumSize: const Size(52, 44),
                shape: const StadiumBorder(),
              ),
              child: Text(
                _level,
                style: DesignTokens.body(
                  14,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.primary),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text('Grammar that sticks', style: DesignTokens.display(34)),
            const SizedBox(height: 8),
            Text(
              'Pick the right form, build the sentence, then use it yourself.',
              style: DesignTokens.body(
                16,
              ).copyWith(color: DesignTokens.muted, height: 1.45),
            ),
            const SizedBox(height: 22),
            _CurrentLessonCard(
              lesson: selected,
              completed: progress[selected.progressId]?.status == 'completed',
              onStart: () => _openLesson(selected),
            ),
            const SizedBox(height: 24),
            const KickerText('PRACTICE YOUR WAY'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.touch_app_outlined,
                    title: 'Pick a word',
                    subtitle: 'Choose the right form',
                    selected: _mode == GrammarPracticeMode.pickWord,
                    onTap: () =>
                        setState(() => _mode = GrammarPracticeMode.pickWord),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.grid_view_rounded,
                    title: 'Make a sentence',
                    subtitle: 'Put words in order',
                    selected: _mode == GrammarPracticeMode.makeSentence,
                    onTap: () => setState(
                      () => _mode = GrammarPracticeMode.makeSentence,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Write your own',
                    subtitle: 'Use it in context',
                    selected: _mode == GrammarPracticeMode.writeOwn,
                    onTap: () =>
                        setState(() => _mode = GrammarPracticeMode.writeOwn),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(child: KickerText('$_level GRAMMAR LESSONS')),
                Text(
                  '$completed/${_lessons.length}',
                  style: DesignTokens.body(
                    13,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lessons.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 116,
              ),
              itemBuilder: (context, index) {
                final lesson = _lessons[index];
                return _LessonCard(
                  lesson: lesson,
                  selected: lesson.id == selected.id,
                  completed: progress[lesson.progressId]?.status == 'completed',
                  onTap: () async {
                    setState(() => _selectedLessonId = lesson.id);
                    await _openLesson(lesson);
                  },
                );
              },
            ),
            if (_level == 'B1' || _level == 'B2') ...[
              const SizedBox(height: 24),
              _AdvancedGenerationCard(
                level: _level,
                lesson: selected,
                isGenerating: widget.isGenerating,
                errorText: widget.generationError,
                onGenerate: () => widget.onGenerateAdvanced(selected),
              ),
            ],
            const SizedBox(height: 24),
            _ReviewMistakesCard(onTap: _reviewMistake),
            if (widget.generatedHistory.isNotEmpty) ...[
              const SizedBox(height: 26),
              const KickerText('SAVED GRAMMAR STORIES'),
              const SizedBox(height: 10),
              SizedBox(
                height: 244,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.generatedHistory.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final story = widget.generatedHistory[index];
                    return SizedBox(
                      width: 210,
                      child: PracticeContentCard(
                        title: story.displayTitle,
                        summary: 'Practice ${story.grammarPoint} in context.',
                        levelBand: story.levelBand,
                        meta: '${story.passage.segments.length} scenes',
                        coverUrl: story.coverUrl,
                        fallbackIcon: CupertinoIcons.textformat,
                        onTap: () => widget.onOpenGenerated(story),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CurrentLessonCard extends StatelessWidget {
  const _CurrentLessonCard({
    required this.lesson,
    required this.completed,
    required this.onStart,
  });

  final GrammarCurriculumLesson lesson;
  final bool completed;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _iconForCollection(lesson.collection),
                  color: DesignTokens.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      completed ? 'PRACTISE AGAIN' : 'NEXT GRAMMAR LESSON',
                      style: DesignTokens.label(
                        11,
                        weight: FontWeight.w800,
                      ).copyWith(color: DesignTokens.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(lesson.title, style: DesignTokens.display(23)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            lesson.tip,
            style: DesignTokens.body(
              15,
            ).copyWith(color: DesignTokens.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignTokens.primary,
                foregroundColor: DesignTokens.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                completed ? 'Practise again' : 'Start now',
                style: DesignTokens.body(
                  15,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          height: 126,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? DesignTokens.primary : DesignTokens.hairline,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: DesignTokens.primary, size: 22),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(12, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
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
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.lesson,
    required this.selected,
    required this.completed,
    required this.onTap,
  });

  final GrammarCurriculumLesson lesson;
  final bool selected;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${lesson.title}, ${lesson.subtitle}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          padding: const EdgeInsets.fromLTRB(11, 12, 9, 10),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? DesignTokens.primary : DesignTokens.hairline,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _iconForCollection(lesson.collection),
                    color: DesignTokens.primary,
                    size: 20,
                  ),
                  const Spacer(),
                  if (completed)
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: DesignTokens.success,
                      size: 17,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                lesson.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(12, weight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                lesson.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  10,
                ).copyWith(color: DesignTokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdvancedGenerationCard extends StatelessWidget {
  const _AdvancedGenerationCard({
    required this.level,
    required this.lesson,
    required this.isGenerating,
    required this.errorText,
    required this.onGenerate,
  });

  final String level;
  final GrammarCurriculumLesson lesson;
  final bool isGenerating;
  final String? errorText;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.wand_stars, color: DesignTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Generate another $level lesson',
                  style: DesignTokens.body(16, weight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Creates one saved lesson about ${lesson.generationPoint}. Generation only starts when you tap below.',
            style: DesignTokens.body(
              13,
            ).copyWith(color: DesignTokens.muted, height: 1.35),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText!,
              style: DesignTokens.body(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.danger),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: isGenerating ? null : onGenerate,
              icon: isGenerating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DesignTokens.primary,
                      ),
                    )
                  : const Icon(CupertinoIcons.sparkles, size: 18),
              label: Text(isGenerating ? 'Generating…' : 'Generate lesson'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DesignTokens.primary,
                side: BorderSide(color: DesignTokens.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewMistakesCard extends StatelessWidget {
  const _ReviewMistakesCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: DesignTokens.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: DesignTokens.primarySoft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                CupertinoIcons.refresh_thick,
                color: DesignTokens.primary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review mistakes',
                    style: DesignTokens.body(16, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Repair the patterns that still need practice.',
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.muted),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, color: DesignTokens.muted),
          ],
        ),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final String level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      title: Text(level, style: DesignTokens.body(16, weight: FontWeight.w700)),
      subtitle: Text(switch (level) {
        'A1' => 'Beginner foundations',
        'A2' => 'Everyday connections',
        'B1' => 'Independent grammar',
        _ => 'Advanced nuance',
      }, style: DesignTokens.body(13).copyWith(color: DesignTokens.muted)),
      trailing: selected
          ? Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: DesignTokens.primary,
            )
          : null,
    );
  }
}

IconData _iconForCollection(String collection) => switch (collection) {
  'Articles & nouns' => CupertinoIcons.textformat_abc,
  'Present tense' => CupertinoIcons.clock,
  'Questions & negatives' => CupertinoIcons.question_circle,
  'Agreement' => CupertinoIcons.equal_circle,
  'Everyday patterns' => CupertinoIcons.chat_bubble_2,
  'Past & future' => CupertinoIcons.time,
  'Pronouns' => CupertinoIcons.person_2,
  'Comparison & quantity' => CupertinoIcons.slider_horizontal_3,
  'Prepositions' => CupertinoIcons.location,
  'Linking ideas' => CupertinoIcons.link,
  'Narrating clearly' => CupertinoIcons.book,
  'Connecting ideas' => CupertinoIcons.link,
  'Speaking politely' => CupertinoIcons.chat_bubble_text,
  'Nuance and stance' => CupertinoIcons.sparkles,
  'Complex hypotheses' => CupertinoIcons.arrow_branch,
  'Register' => CupertinoIcons.textformat,
  'Complex sentences' => CupertinoIcons.square_stack_3d_up,
  'Cohesion' => CupertinoIcons.rectangle_3_offgrid,
  _ => CupertinoIcons.textformat_alt,
};
