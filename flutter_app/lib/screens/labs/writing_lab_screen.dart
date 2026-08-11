import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/learning_store.dart' show WritingSubmission;
import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../../widgets/learning_card.dart';
import '../../widgets/primary_action_button.dart';
import '../lessons/writing_task_screen.dart';

class WritingLabScreen extends ConsumerStatefulWidget {
  const WritingLabScreen({super.key});

  @override
  ConsumerState<WritingLabScreen> createState() => _WritingLabScreenState();
}

class _WritingLabScreenState extends ConsumerState<WritingLabScreen> {
  bool _isGenerating = false;
  String? _errorText;

  Future<void> _startNewPractice() async {
    setState(() {
      _isGenerating = true;
      _errorText = null;
    });
    try {
      final store = ref.read(learningStoreProvider);
      final content = ref.read(contentServiceProvider);
      final profile = store.profile();
      final mistakeTags = store.topMistakeTags();
      final diary = store.recentDiaryEntries();
      final task = await ref
          .read(lessonAgentServiceProvider)
          .generateWritingTask(
            levelBand: profile.level,
            knownVocab: content.knownVocabWords(store.allSRSStates()),
            mistakeTags: mistakeTags
                .map(
                  (m) =>
                      (tag: m.tag, description: m.description, count: m.count),
                )
                .toList(),
            recentDiary: diary.map((d) => d.summary).toList(),
          );
      if (!mounted) return;
      setState(() => _isGenerating = false);
      AppRouter.push(context, (_) => WritingTaskScreen(task: task));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorText = "Couldn't generate a task, try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.canvasDim,
      appBar: AppBar(
        title: Text('Writing', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.canvasDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          PrimaryActionButton(
            label: _isGenerating
                ? 'Preparing your task…'
                : 'New writing practice',
            icon: _isGenerating ? null : CupertinoIcons.wand_stars,
            onPressed: _isGenerating ? null : _startNewPractice,
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
          _pastSubmissions(),
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

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission});

  final WritingSubmission submission;

  String get _dateLabel {
    final parsed = DateTime.tryParse(submission.submittedAt);
    if (parsed == null) return submission.submittedAt;
    final local = parsed.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return LearningCard(
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
