import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../data/content_service.dart';
import '../../data/database/learning_store.dart';
import '../../models/content_models.dart';
import '../../services/lesson_speech_service.dart';

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
    final nodes = <_GraphNode>[];
    for (var i = 0; i < shown.length; i++) {
      final state = shown[i];
      final entry = entries[state.entryId];
      if (entry == null) continue;
      final angle = i * math.pi * (3 - math.sqrt(5));
      final radius = 70 + 10 * math.sqrt(i + 1);
      nodes.add(
        _GraphNode(
          entry: entry,
          practiceCount: reviewCounts[state.entryId] ?? 1,
          theme: themes[state.entryId] ?? 'Vocabulary',
          position: Offset(
            _canvasSize.width / 2 + math.cos(angle) * radius,
            _canvasSize.height / 2 + math.sin(angle) * radius,
          ),
        ),
      );
    }
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
    for (final group in widget.store.reviewedEntryGroupsBySession()) {
      final visible = group.where(byId.containsKey).toList();
      for (var i = 1; i < visible.length; i++) {
        connect(visible[i - 1], visible[i], _EdgeKind.session);
      }
    }
    _settle(nodes, edges);
    return _GraphData(nodes, edges);
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
    if (_graph.nodes.isEmpty) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Passeport.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Passeport.hairline),
        ),
        child: Text(
          'Practice your first words and their connections will appear here.',
          textAlign: TextAlign.center,
          style: Passeport.body(
            15,
          ).copyWith(color: Passeport.slateDim, height: 1.45),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 500,
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Passeport.ink.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Pinch · drag · tap',
                      style: Passeport.body(
                        12,
                        weight: FontWeight.w600,
                      ).copyWith(color: Passeport.card),
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
                    'Larger, brighter words have more recall evidence. Lines connect words from the same topic or practice session.',
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
                            '${_selected!.practiceCount} practices',
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
}

class _GraphData {
  const _GraphData(this.nodes, this.edges);

  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
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
  const _LearningGraphPainter({required this.graph, required this.selected});

  final _GraphData graph;
  final _GraphNode? selected;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Passeport.ink);
    for (final edge in graph.edges) {
      final highlighted =
          selected == null || edge.a == selected || edge.b == selected;
      canvas.drawLine(
        edge.a.position,
        edge.b.position,
        Paint()
          ..color =
              (edge.kind == _EdgeKind.session ? Passeport.sky : Passeport.slate)
                  .withValues(alpha: highlighted ? 0.38 : 0.1)
          ..strokeWidth = edge.kind == _EdgeKind.session ? 1.5 : 0.8,
      );
    }
    for (final node in graph.nodes) {
      final strength = (math.log(node.practiceCount + 1) / math.log(8)).clamp(
        0.18,
        1.0,
      );
      final related =
          selected == null ||
          node == selected ||
          graph.edges.any(
            (edge) =>
                (edge.a == selected && edge.b == node) ||
                (edge.b == selected && edge.a == node),
          );
      final color = Color.lerp(Passeport.slate, Passeport.sky, strength)!;
      if (node == selected) {
        canvas.drawCircle(
          node.position,
          node.radius + 8,
          Paint()..color = Passeport.card.withValues(alpha: 0.2),
        );
      }
      canvas.drawCircle(
        node.position,
        node.radius,
        Paint()..color = color.withValues(alpha: related ? 1 : 0.24),
      );
      if (node.practiceCount >= 2 || node == selected) {
        final painter = TextPainter(
          text: TextSpan(
            text: node.entry.fr,
            style: Passeport.body(12, weight: FontWeight.w600).copyWith(
              color: Passeport.card.withValues(alpha: related ? 0.95 : 0.28),
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
