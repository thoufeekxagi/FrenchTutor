import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_provider.dart';
import '../../services/universal_learning_data_service.dart';
import '../../screens/path/fingerprint_engine.dart';
import '../../screens/path/learning_graph_view.dart';
import '../../widgets/v3/v3_surface.dart';
import '../ui/v3_ui.dart';

/// V3 profile surface around the existing evidence-based French word map.
class V3FrenchFingerprintScreen extends ConsumerWidget {
  const V3FrenchFingerprintScreen({super.key});

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
    final profile = store.profile();
    final snapshot = UniversalLearningDataService.buildSnapshot(
      ref.watch(databaseProvider),
      profile,
    );
    final graph = buildFingerprintGraph(
      store,
      content,
      vocabularySets: vocabularySets,
      stories: stories,
      grammarStories: grammarStories,
      roleplays: roleplays,
      writingTasks: writingTasks,
      recentSnapshot: snapshot,
    );
    final sessions = ref.watch(storageServiceProvider).getAllSessions();

    return V3Scaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          const V3Header(
            title: 'French fingerprint',
            subtitle: 'A personal map shaped by the French you practise.',
            leading: V3BackButton(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _stat(context, '${graph.nodes.length}', 'words')),
              const SizedBox(width: 8),
              Expanded(
                child: _stat(context, '${graph.edges.length}', 'connections'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _stat(context, '${sessions.length}', 'sessions')),
            ],
          ),
          const SizedBox(height: 12),
          V3Card(
            padding: const EdgeInsets.all(8),
            child: FingerprintView(
              store: store,
              content: content,
              graph: graph,
              vocabularySets: vocabularySets,
              stories: stories,
              grammarStories: grammarStories,
              roleplays: roleplays,
              writingTasks: writingTasks,
              height: MediaQuery.sizeOf(context).height < 720 ? 310 : 370,
            ),
          ),
          const SizedBox(height: 18),
          const V3SectionLabel('Practice signals'),
          const SizedBox(height: 8),
          V3Card(
            child: Column(
              children: [
                for (final source in ModalitySource.values) ...[
                  if (source != ModalitySource.values.first)
                    Divider(height: 18, color: Theme.of(context).dividerColor),
                  _signalRow(context, graph, source),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            graph.isDemo
                ? 'This preview uses course vocabulary. Complete lessons and practice to build your own map.'
                : 'Tap a word to see its source. Pinch to zoom and drag to explore.',
            style: V3Type.body(12.5),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) => V3Card(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: V3Type.title(21)),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: V3Type.body(11),
        ),
      ],
    ),
  );

  Widget _signalRow(
    BuildContext context,
    FingerprintGraph graph,
    ModalitySource source,
  ) {
    final count = graph.nodes
        .where((node) => (node.counts[source] ?? 0) > 0)
        .length;
    final (label, detail, icon) = switch (source) {
      ModalitySource.recall => (
        'Recall',
        'Words revisited in vocabulary practice',
        Icons.replay_rounded,
      ),
      ModalitySource.speaking => (
        'Speaking',
        'Words used in spoken sessions',
        Icons.graphic_eq_rounded,
      ),
      ModalitySource.writing => (
        'Writing',
        'Words used in your writing',
        Icons.edit_outlined,
      ),
    };
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: V3Type.strong(14)),
              Text(detail, style: V3Type.body(11.5)),
            ],
          ),
        ),
        Text('$count', style: V3Type.strong(14)),
      ],
    );
  }
}
