import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/content_models.dart';
import '../../providers/database_provider.dart';
import '../../widgets/passeport_card.dart';
import '../lessons/listening_exercise_screen.dart';

class ListeningLabScreen extends ConsumerWidget {
  const ListeningLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = ref.watch(contentServiceProvider).listening();
    final store = ref.watch(learningStoreProvider);

    return Scaffold(
      backgroundColor: Passeport.parchmentDim,
      appBar: AppBar(
        title: Text('Listening', style: Passeport.display(20)),
        backgroundColor: Passeport.parchmentDim,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: pack == null
          ? Center(
              child: Text(
                'Listening content unavailable.',
                style: Passeport.body(13).copyWith(color: Passeport.slateDim),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: pack.exercises.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final exercise = pack.exercises[index];
                final progress = store.lessonStatus('listening_${exercise.id}');
                return _ListeningTile(
                  exercise: exercise,
                  status: progress.status,
                  onTap: () {
                    Navigator.push(
                      context,
                      AppRouter.route(builder: (_) => ListeningExerciseScreen(exercise: exercise),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _ListeningTile extends StatelessWidget {
  const _ListeningTile({
    required this.exercise,
    required this.status,
    required this.onTap,
  });

  final ListeningExercise exercise;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PasseportCard(
      padding: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Row(
          children: [
            Expanded(
              child: Text(
                exercise.title,
                style: Passeport.body(15, weight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            _phaseBadge(exercise.phase),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                '${exercise.questions.length} questions',
                style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
              ),
              if (exercise.dictation.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${exercise.dictation.length} dictation',
                  style: Passeport.mono(10.5).copyWith(color: Passeport.slateDim),
                ),
              ],
            ],
          ),
        ),
        trailing: _statusIcon(status),
        onTap: onTap,
      ),
    );
  }

  Widget _phaseBadge(int phase) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Passeport.brass.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Phase $phase',
        style: Passeport.mono(9, weight: FontWeight.w500).copyWith(color: Passeport.brass),
      ),
    );
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icon(CupertinoIcons.checkmark_circle_fill, color: Passeport.brass, size: 20);
      case 'in_progress':
        return Icon(CupertinoIcons.largecircle_fill_circle, color: Passeport.maroon, size: 20);
      default:
        return Icon(CupertinoIcons.circle, color: Passeport.slate, size: 20);
    }
  }
}
