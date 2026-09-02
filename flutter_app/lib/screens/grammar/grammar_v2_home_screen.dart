import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/generated_grammar_story_store.dart';
import '../../data/grammar_curriculum_catalog.dart';
import '../../design/app_router.dart';
import '../../design/tokens.dart';
import '../../models/grammar_course_v2.dart';
import '../../providers/database_provider.dart';
import '../../widgets/kicker_text.dart';
import '../../widgets/practice_content_card.dart';
import '../../widgets/web/web_constrained_view.dart';
import 'grammar_v2_lesson_screen.dart';

/// Writing-style Grammar home. The cards are deliberately sourced from the
/// existing frozen curriculum so a learner always has five instant lessons;
/// the selected tense is a view over that same validated content.
class GrammarV2HomeScreen extends ConsumerStatefulWidget {
  const GrammarV2HomeScreen({
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
  ConsumerState<GrammarV2HomeScreen> createState() =>
      _GrammarV2HomeScreenState();
}

class _GrammarV2HomeScreenState extends ConsumerState<GrammarV2HomeScreen> {
  late String _level;
  GrammarV2Mode _mode = GrammarV2Mode.guided;
  String _tense = GrammarV2Tenses.all;
  String? _selectedLessonId;

  @override
  void initState() {
    super.initState();
    _level = GrammarCurriculumCatalog.normalizeLevel(
      ref.read(learningStoreProvider).profile().level,
    );
  }

  List<GrammarCurriculumLesson> get _lessons {
    final sameLevel = GrammarCurriculumCatalog.forLevel(_level);
    if (_tense == GrammarV2Tenses.mixed) {
      final mixed = <GrammarCurriculumLesson>[];
      final pool = [
        ...sameLevel,
        ...grammarV2FallbackLessons,
        ...GrammarCurriculumCatalog.all,
      ];
      for (final filter in [
        GrammarV2Tenses.present,
        GrammarV2Tenses.past,
        GrammarV2Tenses.future,
      ]) {
        for (final lesson in pool) {
          if (GrammarV2Tenses.matches(lesson, filter) &&
              !mixed.any((existing) => existing.id == lesson.id)) {
            mixed.add(lesson);
            break;
          }
        }
      }
      for (final lesson in pool) {
        if (!mixed.any((existing) => existing.id == lesson.id)) {
          mixed.add(lesson);
        }
        if (mixed.length >= 5) break;
      }
      return mixed.take(5).toList(growable: false);
    }
    final selected = sameLevel
        .where((lesson) => GrammarV2Tenses.matches(lesson, _tense))
        .toList(growable: false);

    // Past/future are intentionally available to an A1 learner as a small
    // preview set. If the current band has fewer than five frozen cards, fill
    // from the next authored band rather than inventing content at tap time.
    final fallback =
        [...grammarV2FallbackLessons, ...GrammarCurriculumCatalog.all].where(
          (lesson) =>
              !selected.any((existing) => existing.id == lesson.id) &&
              GrammarV2Tenses.matches(lesson, _tense),
        );
    return [...selected, ...fallback].take(5).toList(growable: false);
  }

  GrammarCurriculumLesson get _selectedLesson {
    final available = _lessons;
    for (final lesson in available) {
      if (lesson.id == _selectedLessonId) return lesson;
    }
    return available.first;
  }

  Map<String, dynamic> get _progress =>
      ref.read(learningStoreProvider).allLessonProgress();

  bool _isCompleted(GrammarCurriculumLesson lesson) =>
      _progress[lesson.progressId]?.status == 'completed';

  Future<void> _openLesson(GrammarCurriculumLesson lesson) async {
    final store = ref.read(learningStoreProvider);
    if (store.lessonStatus(lesson.progressId).status == 'not_started') {
      store.setLessonStatus(lesson.progressId, 'in_progress');
    }
    await AppRouter.push<GrammarV2LessonResult>(
      context,
      (_) => GrammarV2LessonScreen(
        lesson: lesson,
        mode: _mode,
        warmupLessons: _lessons,
      ),
      fullscreenDialog: true,
    );
    if (mounted) setState(() {});
  }

  void _setMode(GrammarV2Mode mode) => setState(() => _mode = mode);

  void _setTense(String tense) {
    if (_tense == tense) return;
    setState(() {
      _tense = tense;
      _selectedLessonId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lessons = _lessons;
    final selected = _selectedLesson;
    final completed = lessons.where(_isCompleted).length;

    return Scaffold(
      backgroundColor: DesignTokens.canvas,
      body: SafeArea(
        child: WebConstrainedView(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            children: [
              _header(context),
              const SizedBox(height: 16),
              Text('Build your grammar', style: DesignTokens.display(34)),
              const SizedBox(height: 8),
              Text(
                'Start with one form, build the sentence, then use it in context.',
                style: DesignTokens.body(
                  16,
                ).copyWith(color: DesignTokens.muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              _tensePicker(),
              const SizedBox(height: 22),
              _featuredLesson(selected),
              const SizedBox(height: 24),
              const KickerText('PRACTICE A SKILL'),
              const SizedBox(height: 10),
              _modeGrid(),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: KickerText(
                      '${_tense.toUpperCase()} · ${_level.toUpperCase()} LESSONS',
                    ),
                  ),
                  Text(
                    '$completed/${lessons.length}',
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
                itemCount: lessons.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final lesson = lessons[index];
                  return _LessonCard(
                    lesson: lesson,
                    selected: lesson.id == selected.id,
                    completed: _isCompleted(lesson),
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
              if (widget.generatedHistory.isNotEmpty) ...[
                const SizedBox(height: 28),
                const KickerText('SAVED GRAMMAR STORIES'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 230,
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
      ),
    );
  }

  Widget _header(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Close Grammar',
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(CupertinoIcons.xmark),
              color: DesignTokens.ink,
            ),
          ),
          Expanded(
            child: Text(
              'Grammar',
              textAlign: TextAlign.center,
              style: DesignTokens.display(20),
            ),
          ),
          Semantics(
            button: true,
            label: 'Change grammar level, current level $_level',
            child: TextButton(
              onPressed: _chooseLevel,
              style: TextButton.styleFrom(
                foregroundColor: DesignTokens.primary,
                backgroundColor: DesignTokens.primarySoft,
                minimumSize: const Size(54, 42),
                shape: const StadiumBorder(),
              ),
              child: Text(
                _level,
                style: DesignTokens.body(
                  13,
                  weight: FontWeight.w800,
                ).copyWith(color: DesignTokens.primary),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _tensePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: KickerText('FOCUS')),
            Text(
              'Choose a tense',
              style: DesignTokens.body(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: DesignTokens.muted),
            ),
          ],
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: GrammarV2Tenses.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final tense = GrammarV2Tenses.values[index];
              final selected = tense == _tense;
              return ChoiceChip(
                label: Text(tense),
                selected: selected,
                onSelected: (_) => _setTense(tense),
                labelStyle: DesignTokens.body(13, weight: FontWeight.w700)
                    .copyWith(
                      color: selected
                          ? DesignTokens.onPrimary
                          : DesignTokens.ink,
                    ),
                selectedColor: DesignTokens.primary,
                backgroundColor: DesignTokens.surface,
                side: BorderSide(
                  color: selected
                      ? DesignTokens.primary
                      : DesignTokens.hairline,
                ),
                shape: const StadiumBorder(),
                showCheckmark: false,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _featuredLesson(GrammarCurriculumLesson lesson) {
    final completed = _isCompleted(lesson);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DesignTokens.primary.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: DesignTokens.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _iconForCollection(lesson.collection),
                  color: DesignTokens.primary,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
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
                    Text(lesson.title, style: DesignTokens.display(22)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            _mode.description,
            style: DesignTokens.body(15).copyWith(color: DesignTokens.inkSoft),
          ),
          const SizedBox(height: 4),
          Text(
            lesson.tip,
            style: DesignTokens.body(
              14,
            ).copyWith(color: DesignTokens.muted, height: 1.35),
          ),
          const SizedBox(height: 17),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _openLesson(lesson),
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

  Widget _modeGrid() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < GrammarV2Mode.values.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            child: _ModeCard(
              mode: GrammarV2Mode.values[index],
              selected: _mode == GrammarV2Mode.values[index],
              onTap: () => _setMode(GrammarV2Mode.values[index]),
            ),
          ),
        ],
      ],
    );
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(level, style: DesignTokens.body(16)),
                  trailing: level == _level
                      ? Icon(Icons.check, color: DesignTokens.primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(level),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null || selected == _level) return;
    setState(() {
      _level = selected;
      _selectedLessonId = null;
    });
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final GrammarV2Mode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      GrammarV2Mode.guided => Icons.edit_note_rounded,
      GrammarV2Mode.complete => Icons.checklist_rounded,
      GrammarV2Mode.roleplay => Icons.forum_outlined,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label}, ${mode.subtitle}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 0.92,
          child: AnimatedContainer(
            duration: DesignTokens.durationFast,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: DesignTokens.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? DesignTokens.primary : DesignTokens.hairline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: DesignTokens.primary, size: 25),
                const Spacer(),
                Text(
                  mode.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(13, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  mode.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    11,
                  ).copyWith(color: DesignTokens.muted, height: 1.18),
                ),
              ],
            ),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          padding: const EdgeInsets.fromLTRB(12, 13, 11, 11),
          decoration: BoxDecoration(
            color: DesignTokens.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? DesignTokens.primary : DesignTokens.hairline,
              width: selected ? 1.5 : 1,
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
                    size: 21,
                  ),
                  const Spacer(),
                  if (completed)
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: DesignTokens.success,
                      size: 18,
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
              const SizedBox(height: 4),
              Text(
                '${GrammarV2Tenses.labelFor(lesson)} · ${lesson.level}',
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
                  'Generate a personalized set',
                  style: DesignTokens.body(16, weight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Adds a validated ${lesson.generationPoint} lesson for $level using the learner profile.',
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
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DesignTokens.primary,
                      ),
                    )
                  : Icon(CupertinoIcons.wand_stars),
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

IconData _iconForCollection(String collection) {
  final lower = collection.toLowerCase();
  if (lower.contains('article')) return Icons.article_outlined;
  if (lower.contains('question')) return Icons.help_outline_rounded;
  if (lower.contains('past') || lower.contains('future')) {
    return Icons.schedule_rounded;
  }
  if (lower.contains('pronoun')) return Icons.person_outline_rounded;
  if (lower.contains('comparison')) return Icons.compare_arrows_rounded;
  if (lower.contains('preposition')) return Icons.place_outlined;
  return Icons.auto_fix_high_outlined;
}
