import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../providers/database_provider.dart';
import '../path/fingerprint_engine.dart';
import '../path/learning_graph_view.dart';
import 'speak_ui.dart';

/// A dedicated, screenshot-friendly view of the learner's personal French
/// fingerprint. The graph is deliberately derived from local learning
/// evidence, so it changes with the learner rather than looking like a shared
/// progress illustration.
class FrenchFingerprintScreen extends ConsumerWidget {
  const FrenchFingerprintScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(learningStoreProvider);
    final content = ref.watch(contentServiceProvider);
    final vocabularySets = ref
        .watch(generatedVocabularySetStoreProvider)
        .list();
    final stories = ref.watch(generatedStoryStoreProvider).list();
    final grammarStories = ref.watch(generatedGrammarStoryStoreProvider).list();
    final roleplays = ref.watch(generatedRoleplayStoreProvider).list();
    final writingTasks = ref.watch(generatedWritingTaskStoreProvider).list();
    final graph = buildFingerprintGraph(
      store,
      content,
      vocabularySets: vocabularySets,
      stories: stories,
      grammarStories: grammarStories,
      roleplays: roleplays,
      writingTasks: writingTasks,
    );
    final sessions = ref.watch(storageServiceProvider).getAllSessions();
    final practiceSignals = _practiceSignals(sessions);

    return SpeakScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: SpeakColors.inkSoft,
                ),
              ),
              const Spacer(),
              Text(
                'PROFILE · MAP',
                style: DesignTokens.label(
                  10,
                ).copyWith(color: SpeakColors.inkSoft, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Your French fingerprint', style: DesignTokens.display(29)),
          const SizedBox(height: 6),
          Text(
            'A living map of the words and practice paths that make your French yours.',
            style: DesignTokens.body(
              14,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 20),
          _FingerprintStats(
            words: graph.nodes.length,
            links: graph.edges.length,
            sessions: sessions.length,
          ),
          const SizedBox(height: 18),
          FingerprintView(
            store: store,
            content: content,
            graph: graph,
            vocabularySets: vocabularySets,
            stories: stories,
            grammarStories: grammarStories,
            roleplays: roleplays,
            writingTasks: writingTasks,
            height: 500,
          ),
          const SizedBox(height: 24),
          Text('Practice signals', style: DesignTokens.display(20)),
          const SizedBox(height: 5),
          Text(
            'The map grows from the work you actually do across the app.',
            style: DesignTokens.body(
              13,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 12),
          _SignalStrip(signals: practiceSignals),
          const SizedBox(height: 18),
          Text(
            graph.isDemo
                ? 'This is a quiet preview using course vocabulary. Complete a lesson or conversation to start shaping your own map.'
                : 'Tap a word to see where it came from. Pinch to zoom, drag to explore, and watch the shape change as you learn.',
            style: DesignTokens.body(
              12.5,
            ).copyWith(color: SpeakColors.inkSoft, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _FingerprintStats extends StatelessWidget {
  const _FingerprintStats({
    required this.words,
    required this.links,
    required this.sessions,
  });

  final int words;
  final int links;
  final int sessions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _stat('$words', 'words mapped', SpeakColors.accent),
        const SizedBox(width: 10),
        _stat('$links', 'learning links', SpeakColors.orange),
        const SizedBox(width: 10),
        _stat('$sessions', 'sessions', SpeakColors.green),
      ],
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: DesignTokens.display(19).copyWith(color: color)),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesignTokens.body(
                10.5,
                weight: FontWeight.w600,
              ).copyWith(color: SpeakColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeSignal {
  const _PracticeSignal(this.label, this.count, this.icon, this.color);

  final String label;
  final int count;
  final IconData icon;
  final Color color;
}

List<_PracticeSignal> _practiceSignals(List<dynamic> sessions) {
  final counts = <String, int>{};
  for (final session in sessions) {
    final stage = session.stage as String?;
    if (stage == null || stage.isEmpty) continue;
    counts[stage] = (counts[stage] ?? 0) + 1;
  }
  return [
    _PracticeSignal(
      'Vocabulary',
      counts['vocab'] ?? 0,
      Icons.style_rounded,
      SpeakColors.accent,
    ),
    _PracticeSignal(
      'Grammar',
      counts['grammar'] ?? 0,
      Icons.auto_awesome_rounded,
      SpeakColors.orange,
    ),
    _PracticeSignal(
      'Stories',
      (counts['story'] ?? 0) + (counts['reading_listening'] ?? 0),
      Icons.menu_book_rounded,
      SpeakColors.green,
    ),
    _PracticeSignal(
      'Speaking',
      (counts['speaking'] ?? 0) + (counts['roleplay'] ?? 0),
      Icons.mic_none_rounded,
      DesignTokens.secondary,
    ),
  ];
}

class _SignalStrip extends StatelessWidget {
  const _SignalStrip({required this.signals});

  final List<_PracticeSignal> signals;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: signals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final signal = signals[index];
          return Container(
            width: 124,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SpeakColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(signal.icon, size: 16, color: signal.color),
                    const Spacer(),
                    Text(
                      '${signal.count}',
                      style: DesignTokens.body(
                        15,
                        weight: FontWeight.w700,
                      ).copyWith(color: signal.color),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  signal.label,
                  style: DesignTokens.body(
                    11,
                    weight: FontWeight.w600,
                  ).copyWith(color: SpeakColors.inkSoft),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
