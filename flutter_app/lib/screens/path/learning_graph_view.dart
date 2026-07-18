import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../data/content_service.dart';
import '../../data/database/learning_store.dart';
import '../../models/content_models.dart';
import '../../services/lesson_speech_service.dart';

/// The learner's knowledge map — an Obsidian-style constellation of every
/// word they've practiced. Nodes glow brighter and grow larger with recall
/// evidence; color marks the topic; edges connect words from the same theme
/// or the same practice session. A brand-new learner gets a GRAYED-OUT demo
/// constellation built from real course words to explore, replaced by their
/// own map the moment they practice their first word.
class LearningGraphView extends StatefulWidget {
  const LearningGraphView({
    super.key,
    required this.store,
    required this.content,
  });

  final LearningStore store;
  final ContentService content;

  @override
  State<LearningGraphView> createState() => _LearningGraphViewState();
}

class _LearningGraphViewState extends State<LearningGraphView> {
  static const _canvasSize = Size(1100, 820);
  final TransformationController _transform = TransformationController();
  late _GraphData _graph;
  _GraphNode? _selected;

  @override
  void initState() {
    super.initState();
    _graph = _buildGraph();
  }

  @override
  void didUpdateWidget(covariant LearningGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _graph = _buildGraph();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  _GraphData _buildGraph() {
    final reviewCounts = widget.store.reviewCountsByEntry();
    final states = widget.store.allSRSStates().values.toList()
      ..sort((a, b) {
        final byReviews = (reviewCounts[b.entryId] ?? 0).compareTo(
          reviewCounts[a.entryId] ?? 0,
        );
        if (byReviews != 0) return byReviews;
        return (b.lastReviewedAt ?? DateTime(1970)).compareTo(
          a.lastReviewedAt ?? DateTime(1970),
        );
      });
    final shown = states.take(64).toList();

    final entries = <String, VocabEntry>{};
    final themes = <String, String>{};
    for (final phase in widget.content.vocabPhases) {
      for (final theme in phase.themes) {
        for (final entry in theme.entries) {
          entries[entry.id] = entry;
          themes[entry.id] = theme.title;
        }
      }
    }

    if (shown.isEmpty) {
      return _buildDemoGraph(entries, themes);
    }

    final nodes = <_GraphNode>[];
    for (var i = 0; i < shown.length; i++) {
      final state = shown[i];
      final entry = entries[state.entryId];
      if (entry == null) continue;
      nodes.add(
        _GraphNode(
          entry: entry,
          practiceCount: reviewCounts[state.entryId] ?? 1,
          theme: themes[state.entryId] ?? 'Vocabulary',
          position: _seedPosition(i),
        ),
      );
    }
    final edges = _connectNodes(nodes, useSessions: true);
    _settle(nodes, edges);
    return _GraphData(nodes, edges, isDemo: false);
  }

  /// A curated sample constellation for brand-new learners: real course words
  /// across a few themes, with plausible varied practice counts — fully
  /// explorable, deliberately gray, so the promise is visible before the
  /// first word is ever practiced.
  _GraphData _buildDemoGraph(
    Map<String, VocabEntry> entries,
    Map<String, String> themes,
  ) {
    final byTheme = <String, List<VocabEntry>>{};
    for (final id in entries.keys) {
      byTheme.putIfAbsent(themes[id] ?? 'Vocabulary', () => []);
      byTheme[themes[id] ?? 'Vocabulary']!.add(entries[id]!);
    }
    final nodes = <_GraphNode>[];
    var i = 0;
    for (final theme in byTheme.keys.take(4)) {
      for (final entry in byTheme[theme]!.take(7)) {
        // Deterministic pseudo-varied practice counts (1..8) so the demo has
        // believable big/small, bright/dim variety without any randomness.
        final fakeCount = 1 + ((entry.id.hashCode & 0x7fffffff) % 8);
        nodes.add(
          _GraphNode(
            entry: entry,
            practiceCount: fakeCount,
            theme: theme,
            position: _seedPosition(i),
          ),
        );
        i++;
      }
    }
    final edges = _connectNodes(nodes, useSessions: false);
    _settle(nodes, edges);
    return _GraphData(nodes, edges, isDemo: true);
  }

  Offset _seedPosition(int i) {
    final angle = i * math.pi * (3 - math.sqrt(5));
    final radius = 70 + 10 * math.sqrt(i + 1);
    return Offset(
      _canvasSize.width / 2 + math.cos(angle) * radius,
      _canvasSize.height / 2 + math.sin(angle) * radius,
    );
  }

  List<_GraphEdge> _connectNodes(
    List<_GraphNode> nodes, {
    required bool useSessions,
  }) {
    final byId = {for (final node in nodes) node.entry.id: node};
    final edgeKeys = <String>{};
    final edges = <_GraphEdge>[];

    void connect(String a, String b, _EdgeKind kind) {
      if (a == b || !byId.containsKey(a) || !byId.containsKey(b)) return;
      final ids = [a, b]..sort();
      final key = '${ids[0]}:${ids[1]}';
      if (!edgeKeys.add(key)) return;
      edges.add(_GraphEdge(byId[ids[0]]!, byId[ids[1]]!, kind));
    }

    final byTheme = <String, List<_GraphNode>>{};
    for (final node in nodes) {
      byTheme.putIfAbsent(node.theme, () => []).add(node);
    }
    for (final group in byTheme.values) {
      for (var i = 1; i < group.length; i++) {
        connect(group[i - 1].entry.id, group[i].entry.id, _EdgeKind.theme);
      }
    }
    if (useSessions) {
      for (final group in widget.store.reviewedEntryGroupsBySession()) {
        final visible = group.where(byId.containsKey).toList();
        for (var i = 1; i < visible.length; i++) {
          connect(visible[i - 1], visible[i], _EdgeKind.session);
        }
      }
    }
    return edges;
  }

  void _settle(List<_GraphNode> nodes, List<_GraphEdge> edges) {
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
        final target = edge.kind == _EdgeKind.session ? 95.0 : 130.0;
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

  void _selectNode(TapDownDetails details) {
    final point = _transform.toScene(details.localPosition);
    _GraphNode? nearest;
    var nearestDistance = double.infinity;
    for (final node in _graph.nodes) {
      final distance = (node.position - point).distance;
      if (distance <= node.radius + 14 && distance < nearestDistance) {
        nearest = node;
        nearestDistance = distance;
      }
    }
    setState(() => _selected = nearest);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 520,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: _selectNode,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(240),
                      minScale: 0.45,
                      maxScale: 3.5,
                      child: CustomPaint(
                        size: _canvasSize,
                        painter: _LearningGraphPainter(
                          graph: _graph,
                          selected: _selected,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _chip('Pinch · drag · tap'),
                ),
                if (_graph.isDemo)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Passeport.ink.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.sparkles,
                            size: 16,
                            color: Passeport.brass,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'A preview of your map. Practice your first '
                              'words and they light up here, in color.',
                              style: Passeport.body(12.5).copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: DesignTokens.durationMedium,
          child: _selected == null
              ? Padding(
                  key: const ValueKey('legend'),
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _graph.isDemo
                        ? 'Every word you practice becomes a star on this map — brighter with every recall, connected to the words it lives with.'
                        : 'Larger, brighter words have more recall evidence. Lines connect words from the same topic or practice session.',
                    style: Passeport.body(
                      13,
                    ).copyWith(color: Passeport.slateDim, height: 1.4),
                  ),
                )
              : Container(
                  key: ValueKey(_selected!.entry.id),
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Passeport.infoSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selected!.entry.fr,
                              style: Passeport.display(20),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_selected!.entry.en} · ${_selected!.theme}',
                              style: Passeport.body(
                                13,
                              ).copyWith(color: Passeport.slateDim),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => LessonSpeechService.shared.speak(
                              items: [
                                SpeechItem(
                                  text: _selected!.entry.fr,
                                  language: 'fr-FR',
                                ),
                              ],
                            ),
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                CupertinoIcons.speaker_2_fill,
                                color: Passeport.sky,
                              ),
                            ),
                          ),
                          Text(
                            _graph.isDemo
                                ? 'preview'
                                : '${_selected!.practiceCount} practices',
                            style: Passeport.mono(
                              12,
                              weight: FontWeight.w700,
                            ).copyWith(color: Passeport.sky),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Passeport.ink.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: Passeport.body(
          12,
          weight: FontWeight.w600,
        ).copyWith(color: Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }
}

class _GraphData {
  const _GraphData(this.nodes, this.edges, {required this.isDemo});

  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final bool isDemo;
}

class _GraphNode {
  _GraphNode({
    required this.entry,
    required this.practiceCount,
    required this.theme,
    required this.position,
  });

  final VocabEntry entry;
  final int practiceCount;
  final String theme;
  Offset position;

  double get radius => 8 + math.min(12, math.sqrt(practiceCount) * 4);
}

enum _EdgeKind { theme, session }

class _GraphEdge {
  const _GraphEdge(this.a, this.b, this.kind);

  final _GraphNode a;
  final _GraphNode b;
  final _EdgeKind kind;
}

class _LearningGraphPainter extends CustomPainter {
  _LearningGraphPainter({required this.graph, required this.selected})
    : _themeColors = _assignThemeColors(graph);

  final _GraphData graph;
  final _GraphNode? selected;
  final Map<String, Color> _themeColors;

  /// Topic palette — cycled per theme so neighborhoods of the map share a
  /// color family, exactly like Obsidian's folder-colored clusters.
  static const _palette = <Color>[
    Passeport.sky,
    Passeport.brass,
    Passeport.sage,
    Passeport.mastery,
    Passeport.maroon,
  ];

  static Map<String, Color> _assignThemeColors(_GraphData graph) {
    final themes = <String>[];
    for (final node in graph.nodes) {
      if (!themes.contains(node.theme)) themes.add(node.theme);
    }
    return {
      for (var i = 0; i < themes.length; i++)
        themes[i]: _palette[i % _palette.length],
    };
  }

  Color _nodeColor(_GraphNode node) {
    if (graph.isDemo) return Passeport.slate;
    return _themeColors[node.theme] ?? Passeport.sky;
  }

  bool _isRelated(_GraphNode node) {
    if (selected == null) return true;
    if (node == selected) return true;
    return graph.edges.any(
      (edge) =>
          (edge.a == selected && edge.b == node) ||
          (edge.b == selected && edge.a == node),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Deep space: near-black ink with a soft center glow so the map has
    // depth instead of a flat backdrop.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF11151C));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: graph.isDemo ? 0.025 : 0.05),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );

    // Edges: a wide blurred pass for glow, then a crisp core line.
    for (final edge in graph.edges) {
      final highlighted =
          selected == null || edge.a == selected || edge.b == selected;
      final color = graph.isDemo
          ? Passeport.slate
          : (edge.kind == _EdgeKind.session
                ? Passeport.brass
                : Color.lerp(_nodeColor(edge.a), _nodeColor(edge.b), 0.5)!);
      if (highlighted) {
        canvas.drawLine(
          edge.a.position,
          edge.b.position,
          Paint()
            ..color = color.withValues(alpha: graph.isDemo ? 0.10 : 0.16)
            ..strokeWidth = 3.5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawLine(
        edge.a.position,
        edge.b.position,
        Paint()
          ..color = color.withValues(
            alpha: highlighted ? (graph.isDemo ? 0.28 : 0.45) : 0.07,
          )
          ..strokeWidth = edge.kind == _EdgeKind.session ? 1.4 : 0.9,
      );
    }

    for (final node in graph.nodes) {
      final strength = (math.log(node.practiceCount + 1) / math.log(8)).clamp(
        0.18,
        1.0,
      );
      final related = _isRelated(node);
      final color = _nodeColor(node);
      final dimFactor = related ? 1.0 : 0.22;

      // Outer luminous halo — the "glow" that makes practiced words feel
      // alive. Scales with recall strength.
      canvas.drawCircle(
        node.position,
        node.radius * 2.4,
        Paint()
          ..color = color.withValues(
            alpha: (graph.isDemo ? 0.10 : 0.22) * strength * dimFactor,
          )
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            node.radius * 1.1,
          ),
      );
      // Mid glow ring.
      canvas.drawCircle(
        node.position,
        node.radius * 1.25,
        Paint()
          ..color = color.withValues(
            alpha: (graph.isDemo ? 0.2 : 0.4) * strength * dimFactor,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Core: brightened toward white with strength, like a heating star.
      final core = Color.lerp(
        color,
        Colors.white,
        graph.isDemo ? 0.1 : 0.25 + 0.3 * strength,
      )!;
      canvas.drawCircle(
        node.position,
        node.radius,
        Paint()..color = core.withValues(alpha: dimFactor.clamp(0.24, 1.0)),
      );

      if (node == selected) {
        canvas.drawCircle(
          node.position,
          node.radius + 7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = Colors.white.withValues(alpha: 0.85),
        );
      }

      if (node.practiceCount >= 2 || node == selected) {
        final painter = TextPainter(
          text: TextSpan(
            text: node.entry.fr,
            style: Passeport.body(12, weight: FontWeight.w600).copyWith(
              color: Colors.white.withValues(
                alpha: related ? (graph.isDemo ? 0.55 : 0.92) : 0.2,
              ),
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: 130);
        painter.paint(
          canvas,
          node.position + Offset(-painter.width / 2, node.radius + 6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LearningGraphPainter oldDelegate) =>
      oldDelegate.graph != graph || oldDelegate.selected != selected;
}
