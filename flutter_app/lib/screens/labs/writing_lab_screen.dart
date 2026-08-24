import 'dart:async';
import 'dart:convert';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/learning_store.dart' show WritingSubmission;
import '../../data/database/generated_writing_task_store.dart';
import '../../data/writing_curriculum_catalog.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_speech_service.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/personalized_generation_loader.dart';
import '../../widgets/web/web_constrained_view.dart';
import '../lessons/writing_workshop_screen.dart';

class WritingLabScreen extends ConsumerStatefulWidget {
  const WritingLabScreen({
    super.key,
    this.topic,
    this.contextPrompt,
    this.autoStart = false,
    this.examName,
    this.examLevel,
    this.examMode = false,
  });

  final String? topic;
  final String? contextPrompt;
  final bool autoStart;
  final String? examName;
  final String? examLevel;
  final bool examMode;

  @override
  ConsumerState<WritingLabScreen> createState() => _WritingLabScreenState();
}

class _WritingLabScreenState extends ConsumerState<WritingLabScreen> {
  bool _isGenerating = false;
  String? _errorText;
  List<GeneratedWritingTask>? _history;
  String _selectedMode = 'Words';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    unawaited(_refreshHistory());
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startNewPractice());
      });
    }
  }

  void _loadHistory() {
    if (!mounted) return;
    if (widget.examMode) return;
    setState(
      () => _history = ref.read(generatedWritingTaskStoreProvider).list(),
    );
  }

  Future<void> _refreshHistory() async {
    if (widget.examMode) return;
    try {
      await ref.read(syncServiceProvider).hydrateGeneratedWritingTasks();
    } catch (error, stackTrace) {
      debugPrint('Writing task hydration failed: $error\n$stackTrace');
    }
    if (mounted) _loadHistory();
  }

  Future<void> _startNewPractice() async {
    setState(() {
      _isGenerating = true;
      _errorText = null;
    });
    try {
      final store = ref.read(learningStoreProvider);
      final content = ref.read(contentServiceProvider);
      final profile = store.profile();
      final task = await ref
          .read(lessonAgentServiceProvider)
          .generateWritingTask(
            levelBand: widget.examLevel ?? profile.level,
            topic: widget.topic,
            contextPrompt: widget.contextPrompt,
            examName: widget.examName,
            examMode: widget.examMode,
            knownVocab: content.knownVocabWords(store.allSRSStates()),
          );
      if (!mounted) return;
      final generated = GeneratedWritingTask(
        task: task,
        createdAt: DateTime.now(),
      );
      final examAttemptId = widget.examMode
          ? ref
                .read(examPracticeStoreProvider)
                .startMetadata(
                  examName: widget.examName ?? 'Exam practice',
                  levelBand: widget.examLevel ?? task.levelBand,
                  skill: 'writing',
                  content: {'kind': 'writing', 'task': task.toJson()},
                )
          : null;
      if (!widget.examMode) {
        ref.read(generatedWritingTaskStoreProvider).insert(generated);
        _loadHistory();
      }
      setState(() => _isGenerating = false);
      // Warm the fixed prompt while the workshop opens. The live tutor call
      // remains uncached; only this deterministic lesson line is pre-generated.
      if (!widget.examMode) {
        unawaited(
          LessonSpeechService.shared.prewarmNarration([
            SpeechItem(
              text: task.promptFr,
              language: 'fr-FR',
              contentItemId: 'writing:${task.id}:prompt',
            ),
          ]),
        );
      }
      final result = await AppRouter.push<bool>(
        context,
        (_) => WritingWorkshopScreen(task: task),
        fullscreenDialog: widget.autoStart,
      );
      if (widget.examMode && examAttemptId != null && result == true) {
        ref
            .read(examPracticeStoreProvider)
            .complete(id: examAttemptId, score: 1, total: 1);
      }
      if (widget.autoStart && mounted) {
        Navigator.of(context).pop(result ?? false);
      }
    } catch (e) {
      if (!mounted) return;
      if (widget.autoStart) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _isGenerating = false;
        _errorText = "Couldn't generate a task, try again.";
      });
    }
  }

  String get _level =>
      (widget.examLevel ?? ref.read(learningStoreProvider).profile().level)
          .trim()
          .toUpperCase();

  List<WritingTask> get _curriculum =>
      WritingCurriculumCatalog.forLevel(_level);

  WritingTask? _nextTaskForMode(String mode) {
    final store = ref.read(learningStoreProvider);
    for (final task in _curriculum) {
      if (_modeFor(task) != mode) continue;
      if (store.lessonStatus(task.id).status != 'completed') return task;
    }
    return null;
  }

  Future<void> _openCurriculumTask(WritingTask task) async {
    final result = await AppRouter.push<bool>(
      context,
      (_) => WritingWorkshopScreen(task: task),
    );
    if (result == true && mounted) {
      ref
          .read(learningStoreProvider)
          .setLessonStatus(task.id, 'completed', score: 1);
      setState(() {});
    }
  }

  String _modeFor(WritingTask task) {
    if (task.type == 'word') return 'Words';
    if (task.type == 'sentence') return 'Sentences';
    return 'Free writing';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.autoStart) {
      return Scaffold(
        backgroundColor: DesignTokens.canvasDim,
        appBar: AppBar(
          title: Text('Writing', style: DesignTokens.display(20)),
          backgroundColor: DesignTokens.canvasDim,
          elevation: 0,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: PersonalizedGenerationLoader(
              content: 'writing task',
              detail:
                  'Turning your level, goals, and interests into a useful prompt.',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        title: Text('Writing', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvasDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: WebConstrainedView(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          children: [
            _writingIntro(),
            const SizedBox(height: 16),
            if (_isGenerating)
              const PersonalizedGenerationLoader(
                content: 'writing task',
                detail: 'Creating a prompt matched to your level and goals.',
                compact: true,
              )
            else if (widget.examMode)
              ModernPrimaryButton(
                label: 'New writing practice',
                icon: CupertinoIcons.wand_stars,
                onPressed: _startNewPractice,
              )
            else ...[
              _nextPracticePreview(),
              const SizedBox(height: 18),
              _practiceModes(),
              const SizedBox(height: 14),
              ModernPrimaryButton(
                label: 'Generate a personalized task',
                icon: CupertinoIcons.wand_stars,
                onPressed: _startNewPractice,
              ),
              const SizedBox(height: 20),
              _curriculumSection(),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: DesignTokens.mono(
                  11,
                ).copyWith(color: DesignTokens.primary),
              ),
            ],
            const SizedBox(height: 16),
            _pastGeneratedTasks(),
            _pastSubmissions(),
          ],
        ),
      ),
    );
  }

  Widget _writingIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Build your writing', style: DesignTokens.display(30)),
        const SizedBox(height: 6),
        Text(
          'Start with words, build a sentence, then write your own French.',
          style: DesignTokens.body(
            14,
          ).copyWith(color: DesignTokens.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _LevelBadge(label: _level),
            const SizedBox(width: 8),
            Text(
              '${_curriculum.length} ready lessons',
              style: DesignTokens.body(
                12,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ),
      ],
    );
  }

  Widget _practiceModes() {
    final cards = <Widget>[];
    if (_curriculum.any((task) => task.type == 'word')) {
      final next = _nextTaskForMode('Words');
      cards.add(
        _ModeCard(
          title: 'Words',
          subtitle: next == null
              ? 'Generate next'
              : 'Next: ${next.titleEn ?? next.title}',
          icon: CupertinoIcons.textformat,
          selected: _selectedMode == 'Words',
          onTap: () => _selectMode('Words'),
        ),
      );
    }
    if (_curriculum.any((task) => task.type == 'sentence')) {
      final next = _nextTaskForMode('Sentences');
      cards.add(
        _ModeCard(
          title: 'Sentences',
          subtitle: next == null
              ? 'Generate next'
              : 'Next: ${next.titleEn ?? next.title}',
          icon: CupertinoIcons.list_bullet,
          selected: _selectedMode == 'Sentences',
          onTap: () => _selectMode('Sentences'),
        ),
      );
    }
    if (_curriculum.any(
      (task) => task.type != 'word' && task.type != 'sentence',
    )) {
      final next = _nextTaskForMode('Free writing');
      cards.add(
        _ModeCard(
          title: 'Free writing',
          subtitle: next == null
              ? 'Generate next'
              : 'Next: ${next.titleEn ?? next.title}',
          icon: CupertinoIcons.pencil,
          selected: _selectedMode == 'Free writing',
          onTap: () => _selectMode('Free writing'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRACTICE A SKILL',
          style: DesignTokens.label(
            11,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1.3),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(child: cards[index]),
            ],
          ],
        ),
      ],
    );
  }

  void _selectMode(String mode) {
    setState(() {
      _selectedMode = mode;
      _errorText = null;
    });
  }

  Widget _nextPracticePreview() {
    final next = _nextTaskForMode(_selectedMode);
    final title = next == null
        ? 'Ready for a new $_selectedMode lesson?'
        : (next.titleEn ?? next.title);
    final detail = next == null
        ? 'Your $_selectedMode queue is complete. Generate a personalised task to continue.'
        : '${next.levelBand} · ${_modeLabel(next)}';

    return Material(
      color: DesignTokens.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: DesignTokens.primary.withValues(alpha: 0.38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: next == null
            ? _startNewPractice
            : () => _openCurriculumTask(next),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: DesignTokens.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _iconForTask(next),
                  color: DesignTokens.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NEXT ${_selectedMode.toUpperCase()}',
                      style: DesignTokens.label(10).copyWith(
                        color: DesignTokens.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.display(18),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesignTokens.body(
                        11,
                      ).copyWith(color: DesignTokens.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                next == null
                    ? CupertinoIcons.wand_stars
                    : CupertinoIcons.chevron_right,
                color: DesignTokens.primary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel(WritingTask task) {
    if (task.type == 'word') return 'choose a word';
    if (task.type == 'sentence') return 'build a sentence';
    return 'write freely';
  }

  IconData _iconForTask(WritingTask? task) {
    if (task == null) return CupertinoIcons.wand_stars;
    return switch (task.type) {
      'word' => CupertinoIcons.textformat,
      'sentence' => CupertinoIcons.list_bullet,
      _ => CupertinoIcons.pencil,
    };
  }

  Widget _curriculumSection() {
    final tasks = _curriculum.take(12).toList(growable: false);
    final rows = <Widget>[];
    for (var start = 0; start < tasks.length; start += 3) {
      final rowTasks = tasks.skip(start).take(3).toList(growable: false);
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < 3; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: index < rowTasks.length
                      ? _CurriculumTile(
                          task: rowTasks[index],
                          completed:
                              ref
                                  .read(learningStoreProvider)
                                  .lessonStatus(rowTasks[index].id)
                                  .status ==
                              'completed',
                          onTap: () => _openCurriculumTask(rowTasks[index]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
      if (start + 3 < tasks.length) rows.add(const SizedBox(height: 8));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WRITING PATH',
          style: DesignTokens.label(
            11,
          ).copyWith(color: DesignTokens.primary, letterSpacing: 1.3),
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }

  Widget _pastGeneratedTasks() {
    final history = _history ?? const [];
    if (history.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your writing prompts',
            style: DesignTokens.mono(
              10.5,
              weight: FontWeight.w500,
            ).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: 8),
          for (final generated in history) ...[
            _GeneratedWritingTaskTile(
              generated: generated,
              onTap: () => AppRouter.push(
                context,
                (_) => WritingWorkshopScreen(task: generated.task),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _pastSubmissions() {
    final submissions = ref.watch(learningStoreProvider).submissions();
    if (submissions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Past submissions',
            style: DesignTokens.mono(
              10.5,
              weight: FontWeight.w500,
            ).copyWith(color: DesignTokens.mutedDim),
          ),
          const SizedBox(height: 8),
          for (final s in submissions) ...[
            _SubmissionTile(submission: s),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _GeneratedWritingTaskTile extends StatelessWidget {
  const _GeneratedWritingTaskTile({
    required this.generated,
    required this.onTap,
  });

  final GeneratedWritingTask generated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      padding: 14,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.wand_stars,
              color: DesignTokens.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    generated.task.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.label(14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${generated.task.levelBand} · ${generated.task.minWords}+ words · personalised',
                    style: DesignTokens.body(
                      11,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: DesignTokens.primary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: DesignTokens.primarySoft,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: DesignTokens.primary),
      ),
      child: Text(
        label,
        style: DesignTokens.label(12).copyWith(color: DesignTokens.primary),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DesignTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? DesignTokens.primary : DesignTokens.hairline,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                color: selected ? DesignTokens.primary : DesignTokens.inkSoft,
                size: 23,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, style: DesignTokens.label(13)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(
                      11,
                    ).copyWith(color: DesignTokens.mutedDim),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurriculumTile extends StatelessWidget {
  const _CurriculumTile({
    required this.task,
    required this.completed,
    required this.onTap,
  });

  final WritingTask task;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      padding: 10,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: completed
                    ? DesignTokens.successSoft
                    : DesignTokens.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                completed ? CupertinoIcons.checkmark : _iconForTask(task),
                color: completed ? DesignTokens.success : DesignTokens.primary,
                size: 17,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              task.titleEn ?? task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.label(12.5),
            ),
            const SizedBox(height: 4),
            Text(
              '${task.levelBand} · ${_modeLabel(task)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                10,
              ).copyWith(color: DesignTokens.mutedDim),
            ),
          ],
        ),
      ),
    );
  }

  String _modeLabel(WritingTask task) {
    if (task.type == 'word') return 'choose a word';
    if (task.type == 'sentence') return 'build a sentence';
    return 'write freely';
  }

  IconData _iconForTask(WritingTask task) => switch (task.type) {
    'word' => CupertinoIcons.textformat,
    'sentence' => CupertinoIcons.list_bullet,
    _ => CupertinoIcons.pencil,
  };
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission});

  final WritingSubmission submission;

  String get _dateLabel {
    final parsed = DateTime.tryParse(submission.submittedAt);
    if (parsed == null) return submission.submittedAt;
    final local = parsed.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  Map<String, dynamic>? get _review {
    if (submission.feedback.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(submission.feedback);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Older submissions stored only the improved sentence. Keep them readable.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    final score = review?['score_out_of_10'];
    final strengths = (review?['strengths'] as List?)
        ?.whereType<String>()
        .take(2)
        .toList(growable: false);
    final corrections = (review?['corrections'] as List?)
        ?.whereType<Map>()
        .take(1)
        .toList(growable: false);
    return ModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  submission.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(14),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _dateLabel,
                style: DesignTokens.mono(
                  10.5,
                ).copyWith(color: DesignTokens.mutedDim),
              ),
            ],
          ),
          if (submission.feedback.isNotEmpty) ...[
            const SizedBox(height: 6),
            if (review != null) ...[
              if (score is num)
                Text(
                  'Writing score  ${score.toStringAsFixed(1)}/10',
                  style: DesignTokens.body(
                    14,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.primary),
                ),
              if (strengths != null && strengths.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final strength in strengths)
                  Text(
                    '✓ $strength',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.body(12.5).copyWith(height: 1.35),
                  ),
              ],
              if (corrections != null && corrections.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Next correction: ${corrections.first['fixed'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    12.5,
                  ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
                ),
              ],
            ] else
              Text(
                submission.feedback,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.body(
                  12.5,
                ).copyWith(color: DesignTokens.mutedDim, height: 1.35),
              ),
          ],
        ],
      ),
    );
  }
}
