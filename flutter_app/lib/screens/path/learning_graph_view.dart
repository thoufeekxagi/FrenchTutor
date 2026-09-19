import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../data/content_service.dart';
import '../../data/database/learning_store.dart';
import '../../data/database/generated_grammar_story_store.dart';
import '../../data/database/generated_writing_task_store.dart';
import '../../models/content_models.dart';
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
    this.graph,
    this.vocabularySets = const [],
    this.stories = const [],
    this.grammarStories = const [],
    this.roleplays = const [],
    this.writingTasks = const [],
    this.height = 320,
  });

  final LearningStore store;
  final ContentService content;
  final FingerprintGraph? graph;
  final List<GeneratedVocabularySet> vocabularySets;
  final List<GeneratedStory> stories;
  final List<GeneratedGrammarStory> grammarStories;
  final List<GeneratedRoleplay> roleplays;
  final List<GeneratedWritingTask> writingTasks;
  final double height;

  @override
  State<FingerprintView> createState() => _FingerprintViewState();
}

class _FingerprintViewState extends State<FingerprintView>
    with SingleTickerProviderStateMixin {
  static const _sceneSize = Size(1100, 820);
  final TransformationController _transform = TransformationController();
  late FingerprintGraph _graph;
  late final AnimationController _transformAnimationController;
  Animation<Matrix4>? _transformAnimation;
  FingerprintNode? _selected;
  Size _viewportSize = Size.zero;
  Matrix4 _fitTransform = Matrix4.identity();
  double _fitScale = 1;
  bool _hasFitted = false;
  bool _isZoomed = false;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    _graph = widget.graph ?? _buildGraph(widget);
    _transformAnimationController =
        AnimationController(vsync: this, duration: DesignTokens.durationMedium)
          ..addListener(() {
            final animation = _transformAnimation;
            if (animation != null) _transform.value = animation.value;
          });
  }

  @override
  void didUpdateWidget(covariant FingerprintView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final graphChanged = widget.graph != null
        ? widget.graph != oldWidget.graph
        : widget.store != oldWidget.store ||
              widget.content != oldWidget.content ||
              widget.vocabularySets != oldWidget.vocabularySets ||
              widget.stories != oldWidget.stories ||
              widget.grammarStories != oldWidget.grammarStories ||
              widget.roleplays != oldWidget.roleplays ||
              widget.writingTasks != oldWidget.writingTasks;
    if (graphChanged) {
      _graph = widget.graph ?? _buildGraph(widget);
      _selected = null;
      _hasFitted = false;
    }
  }

  FingerprintGraph _buildGraph(FingerprintView view) => buildFingerprintGraph(
    view.store,
    view.content,
    vocabularySets: view.vocabularySets,
    stories: view.stories,
    grammarStories: view.grammarStories,
    roleplays: view.roleplays,
    writingTasks: view.writingTasks,
  );

  @override
  void dispose() {
    _transformAnimationController.dispose();
    _transform.dispose();
    super.dispose();
  }

  Rect get _graphBounds {
    if (_graph.nodes.isEmpty) return Offset.zero & _sceneSize;
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final node in _graph.nodes) {
      final padding = node.radius + 30;
      left = math.min(left, node.position.dx - padding);
      top = math.min(top, node.position.dy - padding);
      right = math.max(right, node.position.dx + padding);
      bottom = math.max(bottom, node.position.dy + padding + 18);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Matrix4 _matrixForViewport(Size viewport) {
    final bounds = _graphBounds;
    // Keep the constellation clear of the inline legend and interaction hint.
    final usableWidth = math.max(1.0, viewport.width - 28);
    final usableHeight = math.max(1.0, viewport.height - 104);
    final scale = math
        .min(
          usableWidth / math.max(1.0, bounds.width),
          usableHeight / math.max(1.0, bounds.height),
        )
        .clamp(0.35, 1.15)
        .toDouble();
    _fitScale = scale;
    final dx =
        (viewport.width - bounds.width * scale) / 2 - bounds.left * scale;
    final dy =
        54 + (usableHeight - bounds.height * scale) / 2 - bounds.top * scale;
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
  }

  void _scheduleInitialFit(Size viewport) {
    if (_hasFitted && viewport == _viewportSize) return;
    _viewportSize = viewport;
    _fitTransform = _matrixForViewport(viewport);
    if (_hasFitted) return;
    _hasFitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transform.value = _fitTransform.clone();
      _updateZoomState();
    });
  }

  void _animateTransform(Matrix4 target) {
    _transformAnimationController.stop();
    _transformAnimation =
        Matrix4Tween(
          begin: _transform.value.clone(),
          end: target.clone(),
        ).animate(
          CurvedAnimation(
            parent: _transformAnimationController,
            curve: DesignTokens.curveStandard,
          ),
        );
    _transformAnimationController.forward(from: 0);
  }

  void _resetView() {
    setState(() {
      _selected = null;
      _isZoomed = false;
    });
    _animateTransform(_fitTransform);
  }

  void _updateZoomState() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > _fitScale * 1.06;
    if (zoomed != _isZoomed && mounted) setState(() => _isZoomed = zoomed);
  }

  void _selectNode(Offset point) {
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

  FingerprintNode? _nodeAt(Offset scenePoint) {
    FingerprintNode? nearest;
    var nearestDistance = double.infinity;
    for (final node in _graph.nodes) {
      final distance = (node.position - scenePoint).distance;
      if (distance <= math.max(22, node.radius + 12) &&
          distance < nearestDistance) {
        nearest = node;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  void _handleTap(Offset viewportPoint) {
    _selectNode(_transform.toScene(viewportPoint));
  }

  void _handleDoubleTap() {
    final viewportPoint = _doubleTapPosition;
    if (viewportPoint == null) return;
    final node = _nodeAt(_transform.toScene(viewportPoint));
    if (node == null || _isZoomed) {
      _resetView();
      return;
    }
    setState(() => _selected = node);
    final scale = math.max(_fitScale * 1.8, 1.15).clamp(1.15, 2.2).toDouble();
    final target = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, _viewportSize.width / 2 - node.position.dx * scale)
      ..setEntry(1, 3, _viewportSize.height / 2 - node.position.dy * scale);
    setState(() => _isZoomed = true);
    _animateTransform(target);
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                _scheduleInitialFit(viewport);
                return Stack(
                  children: [
                    // This is an intentionally dark, fixed presentation layer.
                    // `ink` is a text token and becomes near-white in dark mode,
                    // which caused the old beige canvas.
                    Positioned.fill(
                      child: ColoredBox(color: DesignTokens.canvasFor(true)),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _handleTap(details.localPosition),
                        onDoubleTapDown: (details) =>
                            _doubleTapPosition = details.localPosition,
                        onDoubleTap: _handleDoubleTap,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          constrained: false,
                          alignment: Alignment.topLeft,
                          // At the fitted scale, vertical drags belong to the
                          // parent ListView. Once zoomed, they pan the map.
                          panEnabled: _isZoomed,
                          scaleEnabled: true,
                          boundaryMargin: const EdgeInsets.all(240),
                          minScale: 0.30,
                          maxScale: 3.0,
                          onInteractionUpdate: (_) => _updateZoomState(),
                          onInteractionEnd: (_) => _updateZoomState(),
                          child: CustomPaint(
                            size: _sceneSize,
                            painter: _FingerprintPainter(
                              graph: _graph,
                              selected: _selected,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(top: 12, left: 12, child: _modalityLegend()),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Semantics(
                        button: true,
                        label: 'Reset fingerprint view',
                        child: IconButton(
                          tooltip: 'Reset view',
                          onPressed: _resetView,
                          icon: const Icon(Icons.refresh_rounded),
                          color: Colors.white.withValues(alpha: 0.82),
                          style: IconButton.styleFrom(
                            backgroundColor: DesignTokens.surfaceFor(
                              true,
                            ).withValues(alpha: 0.88),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      bottom: 12,
                      child: IgnorePointer(
                        child: Text(
                          _isZoomed
                              ? 'Drag to explore · double-tap to reset'
                              : 'Pinch to zoom · tap a word',
                          style: DesignTokens.body(11.5).copyWith(
                            color: Colors.white.withValues(alpha: 0.60),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
                    color: DesignTokens.surfaceFor(true),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: DesignTokens.primary.withValues(alpha: 0.22),
                    ),
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
                              _selected!.entry.en.isEmpty
                                  ? _selected!.theme
                                  : '${_selected!.entry.en} · ${_selected!.theme}',
                              style: DesignTokens.body(13).copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
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
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                CupertinoIcons.speaker_2_fill,
                                color: DesignTokens.primary,
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
                            ).copyWith(color: DesignTokens.primary),
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
        color: DesignTokens.canvasFor(true),
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
            ).copyWith(color: Colors.white.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }

  Widget _modalityLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: DesignTokens.surfaceFor(true).withValues(alpha: 0.94),
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
  static final _palette = <Color>[
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
    final source = _themeColors[node.theme] ?? DesignTokens.info;
    // Keep modality colors as accents inside the dark app rather than bright
    // pastel discs. This preserves hue while substantially lowering luminance.
    return Color.lerp(DesignTokens.canvasFor(true), source, 0.62)!;
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
            ..color = color.withValues(alpha: graph.isDemo ? 0.06 : 0.10)
            ..strokeWidth = 2.8
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
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
              alpha: highlighted ? (graph.isDemo ? 0.22 : 0.34) : 0.05,
            )
            ..strokeWidth = 1.3,
        );
      } else {
        canvas.drawLine(
          edge.a.position,
          edge.b.position,
          Paint()
            ..color = color.withValues(
              alpha: highlighted ? (graph.isDemo ? 0.20 : 0.30) : 0.05,
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
            alpha: (graph.isDemo ? 0.06 : 0.11) * strength * dimFactor,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, node.radius * 0.8),
      );
      canvas.drawCircle(
        node.position,
        node.radius * 1.25,
        Paint()
          ..color = color.withValues(
            alpha: (graph.isDemo ? 0.12 : 0.20) * strength * dimFactor,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      final core = Color.lerp(
        color,
        Colors.white,
        graph.isDemo ? 0.04 : 0.06 + 0.10 * strength,
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
            ..color = Colors.white.withValues(alpha: 0.62),
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
                  color.withValues(alpha: graph.isDemo ? 0.025 : 0.045),
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
            Colors.white.withValues(alpha: graph.isDemo ? 0.01 : 0.018),
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
