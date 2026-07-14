import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../widgets/passeport_card.dart';
import '../lessons/writing_task_screen.dart';

class WritingLabScreen extends ConsumerWidget {
  const WritingLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(contentServiceProvider).writingTasks();

    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text('Writing', style: Passeport.display(20)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: pack == null
          ? Center(
              child: Text(
                'Writing content unavailable.',
                style: Passeport.body(13).copyWith(color: Passeport.slateDim),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: pack.tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final task = pack.tasks[index];
                return _WritingTaskTile(
                  task: task,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WritingTaskScreen(task: task),
                      ),
                    );
                  },
                );
              },
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
                    style: Passeport.body(15, weight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                _typeBadge(task.type),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${task.minWords}+ words',
              style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
            ),
            if (task.targetConnectors.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${task.targetConnectors.length} target connectors',
                style: Passeport.mono(10.5).copyWith(color: Passeport.brass),
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
        color: Passeport.maroon.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        type,
        style: Passeport.mono(9, weight: FontWeight.w500).copyWith(color: Passeport.maroon),
      ),
    );
  }
}
