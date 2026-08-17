import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../data/content_service.dart';
import '../../data/database/learning_store.dart';
import '../../services/lesson_speech_service.dart';
import 'fingerprint_engine.dart';

/// The learner's word fingerprint — a constellation built from real evidence
/// across every modality (flashcard recall, spoken sessions, free writing),
/// so its shape, density, and color mix are as personal as the words a
/// learner actually chooses to use. Two learners never produce the same one:
/// different starting words, different repeats, different modality mix.
/// A brand-new learner sees a grayed-out demo constellation built from real
/// course words, replaced by their own the moment they practice.
class FingerprintView extends StatefulWidget {
  const FingerprintView({
    super.key,
    required this.store,
    required this.content,
    this.height = 320,
  });

  final LearningStore store;
  final ContentService content;
  final double height;

  @override
  State<FingerprintView> createState() => _FingerprintViewState();
}

class _FingerprintViewState extends State<FingerprintView> {
  final TransformationController _transform = TransformationController();
  late FingerprintGraph _graph;
  FingerprintNode? _selected;

  @override
  void initState() {
    super.initState();
    _graph = buildFingerprintGraph(widget.store, widget.content);
  }

  @override
  void didUpdateWidget(covariant FingerprintView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _graph = buildFingerprintGraph(widget.store, widget.content);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _selectNode(TapDownDetails details) {
    final point = _transform.toScene(details.localPosition);
    FingerprintNode? nearest;
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
            height: widget.height,
            child: Stack(
              children: [
                // The dark backdrop lives here, OUTSIDE the InteractiveViewer,
                // so it's a fixed frame that never pans or zooms — only the
                // graph drawn inside InteractiveViewer's child does. Previously
                // the backdrop was painted as part of that same zoomable
                // CustomPaint, so pinching/dragging moved the "background"
                // right along with the dots instead of staying put.
                const Positioned.fill(
                  child: ColoredBox(color: DesignTokens.ink),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: _selectNode,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      constrained: false,
                      alignment: Alignment.center,
                      boundaryMargin: const EdgeInsets.all(240),
                      minScale: 0.45,
                      maxScale: 3.5,
                      child: CustomPaint(
                        size: const Size(1100, 820),
                        painter: _FingerprintPainter(
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
                Positioned(top: 12, left: 12, child: _modalityLegend()),
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
                        ? 'Preview. Practice a word to start yours.'
                        : 'Bigger words mean more practice.',
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: DesignTokens.mutedDim, height: 1.4),
                  ),
                )
              : Container(
                  key: ValueKey(_selected!.entry.id),
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: DesignTokens.infoSoft,
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
                              style: DesignTokens.display(20),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_selected!.entry.en} · ${_selected!.theme}',
                              style: DesignTokens.body(
                                13,
                              ).copyWith(color: DesignTokens.mutedDim),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final source in ModalitySource.values)
                                  if ((_selected!.counts[source] ?? 0) > 0)
                                    _sourcePill(
                                      source,
                                      _selected!.counts[source]!,
                                    ),
                              ],
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
                                color: DesignTokens.info,
                              ),
                            ),
                          ),
                          Text(
                            _graph.isDemo
                                ? 'preview'
                                : '${_selected!.total} total',
                            style: DesignTokens.body(
                              12,
                              weight: FontWeight.w700,
                            ).copyWith(color: DesignTokens.info),
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

  Widget _sourcePill(ModalitySource source, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: _modalityColor(source).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _modalityColor(source),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${_modalityLabel(source)} · $count',
            style: DesignTokens.body(
              11.5,
              weight: FontWeight.w600,
            ).copyWith(color: DesignTokens.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _modalityLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: DesignTokens.ink.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final source in ModalitySource.values) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _modalityColor(source),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _modalityLabel(source),
              style: DesignTokens.body(
                10.5,
                weight: FontWeight.w600,
              ).copyWith(color: Colors.white.withValues(alpha: 0.82)),
            ),
            if (source != ModalitySource.values.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DesignTokens.ink.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: DesignTokens.body(
          12,
          weight: FontWeight.w600,
        ).copyWith(color: Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }
}

String _modalityLabel(ModalitySource source) => switch (source) {
  ModalitySource.recall => 'Recall',
  ModalitySource.speaking => 'Speaking',
  ModalitySource.writing => 'Writing',
};

Color _modalityColor(ModalitySource source) => switch (source) {
  ModalitySource.recall => DesignTokens.info,
  ModalitySource.speaking => DesignTokens.mastery,
  ModalitySource.writing => DesignTokens.success,
};

class _FingerprintPainter extends CustomPainter {
  _FingerprintPainter({required this.graph, required this.selected})
    : _themeColors = _assignThemeColors(graph);

  final FingerprintGraph graph;
  final FingerprintNode? selected;
  final Map<String, Color> _themeColors;

  /// A wider jewel-tone cycle than a plain "topic color" scheme needs, so
  /// clusters read as distinct neighborhoods rather than a handful of repeats.
  static const _palette = <Color>[
    DesignTokens.primary,
    DesignTokens.info,
    DesignTokens.mastery,
    DesignTokens.success,
    DesignTokens.danger,
    DesignTokens.primaryDeep,
  ];

  static Map<String, Color> _assignThemeColors(FingerprintGraph graph) {
    final themes = <String>[];
    for (final node in graph.nodes) {
      if (!themes.contains(node.theme)) themes.add(node.theme);
    }
    return {
      for (var i = 0; i < themes.length; i++)
        themes[i]: _palette[i % _palette.length],
    };
  }

  Color _nodeColor(FingerprintNode node) {
    if (graph.isDemo) return DesignTokens.muted;
    return _themeColors[node.theme] ?? DesignTokens.info;
  }

  bool _isRelated(FingerprintNode node) {
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
    _paintNebula(canvas, size);

    for (final edge in graph.edges) {
      final highlighted =
          selected == null || edge.a == selected || edge.b == selected;
      final color = graph.isDemo
          ? DesignTokens.muted
          : switch (edge.kind) {
              FingerprintEdgeKind.session => DesignTokens.mastery,
              FingerprintEdgeKind.cooccurrence => DesignTokens.success,
              FingerprintEdgeKind.theme => Color.lerp(
                _nodeColor(edge.a),
                _nodeColor(edge.b),
                0.5,
              )!,
            };
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
      final dashed = edge.kind == FingerprintEdgeKind.cooccurrence;
      if (dashed) {
        _drawDashedLine(
          canvas,
          edge.a.position,
          edge.b.position,
          Paint()
            ..color = color.withValues(
              alpha: highlighted ? (graph.isDemo ? 0.30 : 0.5) : 0.08,
            )
            ..strokeWidth = 1.3,
        );
      } else {
        canvas.drawLine(
          edge.a.position,
          edge.b.position,
          Paint()
            ..color = color.withValues(
              alpha: highlighted ? (graph.isDemo ? 0.28 : 0.45) : 0.07,
            )
            ..strokeWidth = edge.kind == FingerprintEdgeKind.session
                ? 1.4
                : 0.9,
        );
      }
    }

    for (final node in graph.nodes) {
      final strength = (math.log(node.total + 1) / math.log(8)).clamp(
        0.18,
        1.0,
      );
      final related = _isRelated(node);
      final color = _nodeColor(node);
      final dimFactor = related ? 1.0 : 0.22;

      canvas.drawCircle(
        node.position,
        node.radius * 2.4,
        Paint()
          ..color = color.withValues(
            alpha: (graph.isDemo ? 0.10 : 0.22) * strength * dimFactor,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, node.radius * 1.1),
      );
      canvas.drawCircle(
        node.position,
        node.radius * 1.25,
        Paint()
          ..color = color.withValues(
            alpha: (graph.isDemo ? 0.2 : 0.4) * strength * dimFactor,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
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

      if (!graph.isDemo && node.sources.length > 1) {
        _paintModalityRing(canvas, node, dimFactor);
      }

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

      if (node.total >= 3 || node == selected) {
        final painter = TextPainter(
          text: TextSpan(
            text: node.entry.fr,
            style: DesignTokens.body(12, weight: FontWeight.w600).copyWith(
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

  /// Two or three faint colored blobs whose position, hue, and size are
  /// derived from this learner's own totals (`graph.seed`) — a quiet backdrop
  /// signature that's part of what makes the whole canvas theirs alone.
  void _paintNebula(Canvas canvas, Size size) {
    // No solid fill here — the dark backdrop is now a static ColoredBox
    // behind InteractiveViewer (see build() above), not part of this
    // zoomable canvas. Painting it here too would make it visibly slide
    // and resize under the fixed one as soon as the graph is panned/zoomed.
    final rand = math.Random(graph.seed);
    final blobColors = graph.isDemo
        ? [DesignTokens.muted, DesignTokens.muted, DesignTokens.muted]
        : [
            DesignTokens.primary,
            DesignTokens.info,
            DesignTokens.mastery,
            DesignTokens.success,
            DesignTokens.danger,
          ];
    for (var i = 0; i < 3; i++) {
      final color = blobColors[rand.nextInt(blobColors.length)];
      final cx = size.width * (0.15 + rand.nextDouble() * 0.7);
      final cy = size.height * (0.15 + rand.nextDouble() * 0.7);
      final radius = size.width * (0.22 + rand.nextDouble() * 0.18);
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  color.withValues(alpha: graph.isDemo ? 0.05 : 0.10),
                  Colors.transparent,
                ],
              ).createShader(
                Rect.fromCircle(center: Offset(cx, cy), radius: radius),
              ),
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: graph.isDemo ? 0.02 : 0.04),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
  }

  /// A thin segmented ring, one arc per contributing modality, drawn just
  /// outside the core — the Apple-Watch-rings idea, but reporting *how* a
  /// word was earned rather than a fitness stat.
  void _paintModalityRing(
    Canvas canvas,
    FingerprintNode node,
    double dimFactor,
  ) {
    final sources = ModalitySource.values
        .where((s) => node.sources.contains(s))
        .toList();
    if (sources.isEmpty) return;
    final sweep = (2 * math.pi) / sources.length;
    final ringRadius = node.radius + 4.5;
    var start = -math.pi / 2;
    for (final source in sources) {
      canvas.drawArc(
        Rect.fromCircle(center: node.position, radius: ringRadius),
        start + 0.06,
        sweep - 0.12,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = _modalityColor(source).withValues(alpha: 0.85 * dimFactor),
      );
      start += sweep;
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 4.0;
    final total = (b - a).distance;
    final direction = (b - a) / total;
    var covered = 0.0;
    while (covered < total) {
      final segmentEnd = math.min(covered + dashLength, total);
      canvas.drawLine(
        a + direction * covered,
        a + direction * segmentEnd,
        paint,
      );
      covered += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _FingerprintPainter oldDelegate) =>
      oldDelegate.graph != graph || oldDelegate.selected != selected;
}
