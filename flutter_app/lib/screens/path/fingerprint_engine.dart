import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset, Size;

import '../../data/content_service.dart';
import '../../data/database/learning_store.dart';
import '../../models/content_models.dart';

/// Where a word's practice evidence came from. A word touched by more than
/// one modality is exactly why no two learners' fingerprints look alike —
/// nobody drills, speaks, and writes the same words in the same proportions.
enum ModalitySource { recall, speaking, writing }

class FingerprintNode {
  FingerprintNode({
    required this.entry,
    required this.theme,
    required this.counts,
    required this.position,
  });

  final VocabEntry entry;
  final String theme;

  /// Raw occurrence count per modality that contributed to this word.
  final Map<ModalitySource, int> counts;
  Offset position;

  int get total => counts.values.fold(0, (sum, c) => sum + c);

  Set<ModalitySource> get sources =>
      counts.entries.where((e) => e.value > 0).map((e) => e.key).toSet();

  double get radius => 8 + math.min(13, math.sqrt(total) * 4.2);
}

enum FingerprintEdgeKind { theme, session, cooccurrence }

class FingerprintEdge {
  const FingerprintEdge(this.a, this.b, this.kind);

  final FingerprintNode a;
  final FingerprintNode b;
  final FingerprintEdgeKind kind;
}

class FingerprintGraph {
  const FingerprintGraph(this.nodes, this.edges, {required this.isDemo});

  final List<FingerprintNode> nodes;
  final List<FingerprintEdge> edges;
  final bool isDemo;

  /// A stable number derived from this learner's own totals — used to seed
  /// the background nebula so the backdrop itself is quietly unique to them,
  /// not just the word layout.
  int get seed {
    var acc = nodes.length * 7919;
    for (final n in nodes) {
      acc = (acc + n.total * 104729 + n.entry.id.hashCode) & 0x7fffffff;
    }
    return acc;
  }
}

const Size _canvasSize = Size(1100, 820);

final _stopWords = <String>{
  'le', 'la', 'les', 'l', 'un', 'une', 'des', 'de', 'du', 'au', 'aux', 'et',
  'à', 'a', 'en', 'ce', 'cet', 'cette', 'ces', 'mon', 'ma', 'mes', 'ton',
  'ta', 'tes', 'son', 'sa', 'ses', 'notre', 'nos', 'votre', 'vos', 'leur',
  'leurs', 'que', 'qui', 'pour', 'avec', 'dans', 'sur', 'est', 'es', 'ai',
  'as', 'avons', 'avez', 'ont', 'je', 'tu', 'il', 'elle', 'on', 'nous',
  'vous', 'ils', 'elles', 'se', 'ne', 'pas', 'y', 'd', 'n', 'qu', 'c', 'j',
  'm', 't', 's', 'être', 'suis', 'ça', 'très', 'plus',
};

List<String> _tokenize(String text) {
  final cleaned = text.toLowerCase().replaceAll(RegExp("[’]"), "'");
  final raw = cleaned.split(RegExp(r"[^a-zàâäéèêëïîôöùûüÿœç']+"));
  final tokens = <String>[];
  for (var t in raw) {
    if (t.contains("'")) t = t.split("'").last;
    if (t.isEmpty || _stopWords.contains(t)) continue;
    tokens.add(t);
  }
  return tokens;
}

/// Builds the learner's word fingerprint from every place they've actually
/// produced or reviewed French: flashcard recall, spoken session transcripts
/// (roleplay + pronunciation share the same session log), and free writing.
FingerprintGraph buildFingerprintGraph(LearningStore store, ContentService content) {
  final entries = <String, VocabEntry>{};
  final themes = <String, String>{};
  for (final phase in content.vocabPhases) {
    for (final theme in phase.themes) {
      for (final entry in theme.entries) {
        entries[entry.id] = entry;
        themes[entry.id] = theme.title;
      }
    }
  }

  // Only unambiguous tokens are attributed — a token shared by two entries'
  // French forms is dropped rather than mis-credited.
  final candidates = <String, Set<String>>{};
  for (final entry in entries.values) {
    for (final token in _tokenize(entry.fr)) {
      candidates.putIfAbsent(token, () => {}).add(entry.id);
    }
  }
  final tokenToEntry = <String, String>{
    for (final e in candidates.entries)
      if (e.value.length == 1) e.key: e.value.first,
  };

  Map<String, int> countAndGroup(
    List<String> texts,
    List<Set<String>> groupsOut,
  ) {
    final counts = <String, int>{};
    for (final text in texts) {
      final matched = <String>{};
      for (final token in _tokenize(text)) {
        final id = tokenToEntry[token];
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
        matched.add(id);
      }
      if (matched.length > 1) groupsOut.add(matched);
    }
    return counts;
  }

  final recallCounts = store.reviewCountsByEntry();
  final speakingGroups = <Set<String>>[];
  final speakingCounts = countAndGroup(store.spokenSessionTexts(), speakingGroups);
  final writingGroups = <Set<String>>[];
  final writingCounts = countAndGroup(
    store.submissions().map((s) => s.text).toList(),
    writingGroups,
  );

  final touchedIds = <String>{
    ...recallCounts.keys,
    ...speakingCounts.keys,
    ...writingCounts.keys,
  }..removeWhere((id) => !entries.containsKey(id));

  if (touchedIds.isEmpty) return _buildDemoGraph(entries, themes);

  final lastReviewed = <String, DateTime>{};
  for (final state in store.allSRSStates().values) {
    if (state.lastReviewedAt != null) lastReviewed[state.entryId] = state.lastReviewedAt!;
  }

  final ranked = touchedIds.toList()
    ..sort((a, b) {
      final totalA = (recallCounts[a] ?? 0) + (speakingCounts[a] ?? 0) + (writingCounts[a] ?? 0);
      final totalB = (recallCounts[b] ?? 0) + (speakingCounts[b] ?? 0) + (writingCounts[b] ?? 0);
      final byTotal = totalB.compareTo(totalA);
      if (byTotal != 0) return byTotal;
      return (lastReviewed[b] ?? DateTime(1970)).compareTo(lastReviewed[a] ?? DateTime(1970));
    });
  final shown = ranked.take(90).toList();

  final nodes = <FingerprintNode>[];
  for (var i = 0; i < shown.length; i++) {
    final id = shown[i];
    nodes.add(
      FingerprintNode(
        entry: entries[id]!,
        theme: themes[id] ?? 'Vocabulary',
        counts: {
          ModalitySource.recall: recallCounts[id] ?? 0,
          ModalitySource.speaking: speakingCounts[id] ?? 0,
          ModalitySource.writing: writingCounts[id] ?? 0,
        },
        position: _seedPosition(i),
      ),
    );
  }

  final edges = _connectNodes(
    nodes,
    sessionGroups: store.reviewedEntryGroupsBySession(),
    speakingGroups: speakingGroups,
    writingGroups: writingGroups,
  );
  _settle(nodes, edges);
  return FingerprintGraph(nodes, edges, isDemo: false);
}

FingerprintGraph _buildDemoGraph(Map<String, VocabEntry> entries, Map<String, String> themes) {
  final byTheme = <String, List<VocabEntry>>{};
  for (final id in entries.keys) {
    byTheme.putIfAbsent(themes[id] ?? 'Vocabulary', () => []).add(entries[id]!);
  }
  final nodes = <FingerprintNode>[];
  var i = 0;
  for (final theme in byTheme.keys.take(4)) {
    for (final entry in byTheme[theme]!.take(7)) {
      final hash = entry.id.hashCode & 0x7fffffff;
      nodes.add(
        FingerprintNode(
          entry: entry,
          theme: theme,
          counts: {
            ModalitySource.recall: 1 + (hash % 6),
            ModalitySource.speaking: hash % 3 == 0 ? 1 + (hash % 4) : 0,
            ModalitySource.writing: hash % 5 == 0 ? 1 + (hash % 3) : 0,
          },
          position: _seedPosition(i),
        ),
      );
      i++;
    }
  }
  final edges = _connectNodes(nodes, sessionGroups: const [], speakingGroups: const [], writingGroups: const []);
  _settle(nodes, edges);
  return FingerprintGraph(nodes, edges, isDemo: true);
}

Offset _seedPosition(int i) {
  final angle = i * math.pi * (3 - math.sqrt(5));
  final radius = 70 + 10 * math.sqrt(i + 1);
  return Offset(
    _canvasSize.width / 2 + math.cos(angle) * radius,
    _canvasSize.height / 2 + math.sin(angle) * radius,
  );
}

List<FingerprintEdge> _connectNodes(
  List<FingerprintNode> nodes, {
  required List<List<String>> sessionGroups,
  required List<Set<String>> speakingGroups,
  required List<Set<String>> writingGroups,
}) {
  final byId = {for (final node in nodes) node.entry.id: node};
  final edgeKeys = <String>{};
  final edges = <FingerprintEdge>[];

  void connect(String a, String b, FingerprintEdgeKind kind) {
    if (a == b || !byId.containsKey(a) || !byId.containsKey(b)) return;
    final ids = [a, b]..sort();
    final key = '${ids[0]}:${ids[1]}';
    if (!edgeKeys.add(key)) return;
    edges.add(FingerprintEdge(byId[ids[0]]!, byId[ids[1]]!, kind));
  }

  final byTheme = <String, List<FingerprintNode>>{};
  for (final node in nodes) {
    byTheme.putIfAbsent(node.theme, () => []).add(node);
  }
  for (final group in byTheme.values) {
    for (var i = 1; i < group.length; i++) {
      connect(group[i - 1].entry.id, group[i].entry.id, FingerprintEdgeKind.theme);
    }
  }
  for (final group in sessionGroups) {
    final visible = group.where(byId.containsKey).toList();
    for (var i = 1; i < visible.length; i++) {
      connect(visible[i - 1], visible[i], FingerprintEdgeKind.session);
    }
  }
  for (final group in [...speakingGroups, ...writingGroups]) {
    final visible = group.where(byId.containsKey).toList();
    for (var i = 1; i < visible.length; i++) {
      connect(visible[i - 1], visible[i], FingerprintEdgeKind.cooccurrence);
    }
  }
  return edges;
}

void _settle(List<FingerprintNode> nodes, List<FingerprintEdge> edges) {
  if (nodes.length < 2) return;
  for (var iteration = 0; iteration < 140; iteration++) {
    final forces = List<Offset>.filled(nodes.length, Offset.zero);
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final delta = nodes[i].position - nodes[j].position;
        final distance = math.max(24.0, delta.distance);
        final direction = delta / distance;
        final force = direction * (1500 / (distance * distance));
        forces[i] += force;
        forces[j] -= force;
      }
    }
    for (final edge in edges) {
      final a = nodes.indexOf(edge.a);
      final b = nodes.indexOf(edge.b);
      final delta = edge.b.position - edge.a.position;
      final distance = math.max(1.0, delta.distance);
      final target = edge.kind == FingerprintEdgeKind.theme ? 130.0 : 95.0;
      final force = delta / distance * ((distance - target) * 0.006);
      forces[a] += force;
      forces[b] -= force;
    }
    for (var i = 0; i < nodes.length; i++) {
      final centerPull = Offset(
        (_canvasSize.width / 2 - nodes[i].position.dx) * 0.0015,
        (_canvasSize.height / 2 - nodes[i].position.dy) * 0.0015,
      );
      final next = nodes[i].position + (forces[i] + centerPull) * 0.75;
      nodes[i].position = Offset(
        next.dx.clamp(40, _canvasSize.width - 40),
        next.dy.clamp(40, _canvasSize.height - 40),
      );
    }
  }
}
