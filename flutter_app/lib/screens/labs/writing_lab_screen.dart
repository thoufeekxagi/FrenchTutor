import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/passeport_primary_button.dart';
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
      final task = await ref
          .read(lessonAgentServiceProvider)
          .generateWritingTask(
            levelBand: profile.level,
            knownVocab: content.knownVocabWords(store.allSRSStates()),
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
    final pack = ref.watch(contentServiceProvider).writingTasks();

    return Scaffold(
      backgroundColor: DesignTokens.parchmentDim,
      appBar: AppBar(
        title: Text('Writing', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        children: [
          PasseportPrimaryButton(
            label: _isGenerating ? 'Preparing your task…' : 'New writing practice',
            icon: _isGenerating ? null : CupertinoIcons.wand_stars,
            onPressed: _isGenerating ? null : _startNewPractice,
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: DesignTokens.mono(11).copyWith(color: DesignTokens.primary),
            ),
          ],
          const SizedBox(height: 16),
          if (pack != null && pack.tasks.isNotEmpty) ...[
            Text(
              'Offline practice bank',
              style: DesignTokens.mono(
                10.5,
                weight: FontWeight.w500,
              ).copyWith(color: DesignTokens.slateDim),
            ),
            const SizedBox(height: 8),
            for (final task in pack.tasks) ...[
              _WritingTaskTile(
                task: task,
                onTap: () {
                  AppRouter.push(context, (_) => WritingTaskScreen(task: task));
                },
              ),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _WritingTaskTile extends StatelessWidget {
  const _WritingTaskTile({required this.task, required this.onTap});

  final WritingTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PasseportCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: DesignTokens.body(15, weight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                _typeBadge(task.type),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${task.minWords}+ words',
              style: DesignTokens.mono(
                10.5,
              ).copyWith(color: DesignTokens.slateDim),
            ),
            if (task.targetConnectors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${task.targetConnectors.length} target connectors',
                style: DesignTokens.mono(
                  10.5,
                ).copyWith(color: DesignTokens.info),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: DesignTokens.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        type,
        style: DesignTokens.mono(
          9,
          weight: FontWeight.w500,
        ).copyWith(color: DesignTokens.primary),
      ),
    );
  }
}
