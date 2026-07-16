import '../../design/app_router.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens.dart';
import '../../widgets/passeport_card.dart';
import '../../widgets/kicker_text.dart';
import '../../providers/database_provider.dart';
import '../lessons/grammar_lesson_screen.dart';
import '../lessons/topic_lesson_screen.dart';

class GrammarLabScreen extends ConsumerWidget {
  const GrammarLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentServiceProvider);
    final store = ref.watch(learningStoreProvider);
    final grammar = content.grammar();

    if (grammar == null) {
      return Scaffold(
        backgroundColor: DesignTokens.parchment,
        appBar: AppBar(
          title: Text('Grammar', style: DesignTokens.display(20)),
          backgroundColor: DesignTokens.parchment,
          foregroundColor: DesignTokens.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: const Center(child: Text('No grammar content loaded.')),
      );
    }

    final lessons = List.of(grammar.lessons)
      ..sort((a, b) => a.order.compareTo(b.order));
    final topics = grammar.topics;
    final progress = store.allLessonProgress();

    return Scaffold(
      backgroundColor: DesignTokens.parchment,
      appBar: AppBar(
        title: Text('Grammar', style: DesignTokens.display(20)),
        backgroundColor: DesignTokens.parchment,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // --- Lessons section ---
          const SizedBox(height: 8),
          const KickerText('Lessons'),
          const SizedBox(height: 10),
          PasseportCard(
            padding: 0,
            child: Column(
              children: [
                for (int i = 0; i < lessons.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: DesignTokens.hairline,
                      indent: 16,
                      endIndent: 16,
                    ),
                  _LessonTile(
                    lesson: lessons[i],
                    status: progress[lessons[i].id]?.status ?? 'not_started',
                  ),
                ],
              ],
            ),
          ),
          // --- Topics section ---
          if (topics.isNotEmpty) ...[
            const SizedBox(height: 24),
            const KickerText('Topics'),
            const SizedBox(height: 10),
            PasseportCard(
              padding: 0,
              child: Column(
                children: [
                  for (int i = 0; i < topics.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: DesignTokens.hairline,
                        indent: 16,
                        endIndent: 16,
                      ),
                    _TopicTile(
                      topic: topics[i],
                      status: progress[topics[i].id]?.status ?? 'not_started',
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, required this.status});

  final dynamic lesson; // GrammarLesson
  final String status;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        lesson.title as String,
        style: DesignTokens.body(15, weight: FontWeight.w500),
      ),
      subtitle: Text(
        lesson.subtitle as String,
        style: DesignTokens.body(12).copyWith(color: DesignTokens.slateDim),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(status: status),
          const SizedBox(width: 4),
          Icon(
            CupertinoIcons.chevron_right,
            color: DesignTokens.slate,
            size: 20,
          ),
        ],
      ),
      onTap: () {
        AppRouter.push(context, (_) => GrammarLessonScreen(lesson: lesson));
      },
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic, required this.status});

  final dynamic topic; // GrammarTopic
  final String status;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        topic.title as String,
        style: DesignTokens.body(15, weight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(status: status),
          const SizedBox(width: 4),
          Icon(
            CupertinoIcons.chevron_right,
            color: DesignTokens.slate,
            size: 20,
          ),
        ],
      ),
      onTap: () {
        AppRouter.push(context, (_) => TopicLessonScreen(topic: topic));
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (status) {
      'completed' => ('Ready', DesignTokens.success),
      'in_progress' => ('Building', DesignTokens.info),
      _ => ('New', DesignTokens.slate),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: DesignTokens.mono(
          10,
          weight: FontWeight.w500,
        ).copyWith(color: color),
      ),
    );
  }
}
