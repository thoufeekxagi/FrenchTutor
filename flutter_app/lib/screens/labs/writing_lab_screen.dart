import 'dart:async';
import 'dart:convert';

import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/learning_store.dart' show WritingSubmission;
import '../../data/database/generated_writing_task_store.dart';
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../services/lesson_speech_service.dart';
import '../../services/practice_artwork_service.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/passeport_primary_button.dart';
import '../../widgets/personalized_generation_loader.dart';
import '../../widgets/practice_content_card.dart';
import '../../widgets/responsive_card_grid.dart';
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
        unawaited(_generateCover(generated));
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

  Future<void> _generateCover(GeneratedWritingTask generated) async {
    final sync = ref.read(syncServiceProvider);
    final store = ref.read(generatedWritingTaskStoreProvider);
    try {
      final url = await PracticeArtworkService.generateAndUpload(
        sync: sync,
        id: generated.id,
        title: generated.task.title,
        summary: generated.task.promptEn,
        topic: generated.task.title,
        levelBand: generated.task.levelBand,
        coverPrompt:
            'A premium literary book-cover scene for a French learner writing about '
            '${generated.task.promptEn}. Use one clear focal scene, sophisticated editorial '
            'realism, restrained color grading, layered depth, and a polished publishing '
            'aesthetic. Keep the composition portrait and crop-friendly with safe margins.',
      );
      if (url == null) return;
      store.updateCoverUrl(generated.id, url);
      if (mounted) _loadHistory();
    } catch (error, stackTrace) {
      debugPrint('Writing cover generation failed: $error\n$stackTrace');
    }
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
            if (_isGenerating)
              const PersonalizedGenerationLoader(
                content: 'writing task',
                detail: 'Creating a prompt matched to your level and goals.',
                compact: true,
              )
            else
              ModernPrimaryButton(
                label: 'New writing practice',
                icon: CupertinoIcons.wand_stars,
                onPressed: _startNewPractice,
              ),
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
          ResponsiveCardGrid(
            mainAxisExtent: 292,
            itemCount: history.length,
            itemBuilder: (context, index) {
              final generated = history[index];
              return _GeneratedWritingTaskTile(
                generated: generated,
                onTap: () => AppRouter.push(
                  context,
                  (_) => WritingWorkshopScreen(task: generated.task),
                ),
              );
            },
          ),
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
    return PracticeContentCard(
      title: generated.task.displayTitle,
      summary: generated.task.promptEn,
      levelBand: generated.task.levelBand,
      meta: '${generated.task.minWords}+ words',
      coverUrl: generated.coverUrl,
      fallbackIcon: CupertinoIcons.pencil,
      onTap: onTap,
    );
  }
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
