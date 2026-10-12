import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Inspect-first helper for on-device tests.
///
/// Never script a tap against a widget you have not seen. Call [capture] on a
/// screen once, read `artifacts/e2e/probe.json` and the PNG, then write the
/// real assertions against the labels, keys and texts it listed.
class Probe {
  Probe(this.binding);

  final IntegrationTestWidgetsFlutterBinding binding;

  /// Pumps frames until the visible content has stopped changing for [quiet],
  /// or [timeout] elapses. A frame-idle check is not enough: the app is idle
  /// while it waits on async startup work and would be captured mid-loading.
  /// Never use `pumpAndSettle` on this app: live animations keep it from
  /// settling and the test hangs.
  Future<void> settle(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 30),
    Duration quiet = const Duration(milliseconds: 2500),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var last = '';
    var stableSince = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final now = _signature(tester);
      if (now != last) {
        last = now;
        stableSince = DateTime.now();
      } else if (now.isNotEmpty &&
          DateTime.now().difference(stableSince) >= quiet) {
        return;
      }
    }
  }

  String _signature(WidgetTester tester) {
    final texts = <String>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is Text) texts.add(w.data ?? w.textSpan?.toPlainText() ?? '');
      e.visitChildren(visit);
    }

    tester.binding.rootElement?.visitChildren(visit);
    return texts.join('|');
  }

  /// Waits for [finder] to match. On timeout the failure message carries the
  /// current screen description so the next step is a fact, not a guess.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    await capture(tester, 'timeout_${DateTime.now().millisecondsSinceEpoch}');
    throw TimeoutException(
      'Not found within $timeout: $finder\n'
      'Visible now: ${describe(tester)}',
    );
  }

  /// Waits until a tappable with [label] is on screen. On timeout the failure
  /// carries a screenshot and the tappable labels that were visible.
  Future<void> waitForLabel(
    WidgetTester tester,
    String label, {
    bool startsWith = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    List<String> labels = const [];
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 150));
      labels = (describe(tester)['tappable']! as List)
          .map((e) => (e as Map)['label'] as String)
          .toList();
      final hit = startsWith
          ? labels.any((l) => l.startsWith(label))
          : labels.contains(label);
      if (hit) return;
    }
    await capture(tester, 'timeout_${DateTime.now().millisecondsSinceEpoch}');
    throw TimeoutException(
      'No tappable "$label" within $timeout. Visible tappables: $labels',
    );
  }

  /// Taps a tappable semantics node by its label, using the exact rect the
  /// probe reports. Semantics rects are physical pixels (they include the
  /// device pixel ratio), so the tap point is divided by it.
  ///
  /// [startsWith] matches the beginning of the label (for rows whose label is
  /// "Title\nSubtitle"). Returns false when nothing matched.
  Future<bool> tapLabel(
    WidgetTester tester,
    String label, {
    bool startsWith = false,
  }) async {
    final nodes = (describe(tester)['tappable']! as List).cast<Map>();
    final hit = nodes.where((n) {
      final l = n['label'] as String;
      return startsWith ? l.startsWith(label) : l == label;
    });
    if (hit.isEmpty) return false;
    final r = (hit.first['rect'] as Map).cast<String, double>();
    final dpr = tester.view.devicePixelRatio;
    if (hit.first['oversized'] == true) {
      // The node's rect spans much of the screen (an app semantics bug), so its
      // centre is not the control. Tap the visible text instead.
      final text = find.text(label);
      if (text.evaluate().isEmpty) return false;
      await tester.tap(text.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 150));
      return true;
    }
    final point = Offset(
      (r['x']! + r['w']! / 2) / dpr,
      (r['y']! + r['h']! / 2) / dpr,
    );
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 150));
    return true;
  }

  /// Visible-content fingerprint, used to detect a screen that did not change.
  String fingerprint(WidgetTester tester) => _signature(tester);

  /// Takes a screenshot and records everything interactive on screen.
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot(name);
    // Merge, never replace: takeScreenshot stores its bytes in
    // reportData['screenshots'] and replacing the map would delete them.
    binding.reportData ??= <String, dynamic>{};
    binding.reportData![name] = describe(tester);
  }

  /// Everything a test may legitimately target on the current screen.
  Map<String, Object?> describe(WidgetTester tester) {
    final keys = <Map<String, Object?>>[];
    final texts = <String>[];
    void visit(Element element) {
      final widget = element.widget;
      final key = widget.key;
      if (key is ValueKey<String>) {
        final box = element.renderObject;
        Rect? rect;
        if (box is RenderBox && box.attached && box.hasSize) {
          rect = box.localToGlobal(Offset.zero) & box.size;
        }
        keys.add({
          'key': key.value,
          'type': widget.runtimeType.toString(),
          if (rect != null) 'rect': _rect(rect),
        });
      }
      if (widget is Text) {
        final text = widget.data ?? widget.textSpan?.toPlainText();
        if (text != null && text.trim().isNotEmpty) texts.add(text.trim());
      }
      element.visitChildren(visit);
    }

    tester.binding.rootElement?.visitChildren(visit);

    final semantics = <Map<String, Object?>>[];
    for (final view in tester.binding.renderViews) {
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) _walk(root, Matrix4.identity(), semantics);
    }

    return {
      'texts': texts.toSet().toList(),
      'keys': keys,
      'semantics': semantics,
      'tappable': semantics
          .where((n) => n['tap'] == true && (n['label'] as String).isNotEmpty)
          .map((n) {
            final h = (n['rect']! as Map)['h']! as double;
            return {
              'label': n['label'],
              'rect': n['rect'],
              if (h > 0.5 * tester.view.physicalSize.height) 'oversized': true,
            };
          })
          .toList(),
    };
  }

  void _walk(
    SemanticsNode node,
    Matrix4 parent,
    List<Map<String, Object?>> out,
  ) {
    final matrix = parent.clone();
    final transform = node.transform;
    if (transform != null) matrix.multiply(transform);
    final data = node.getSemanticsData();
    final label = data.label.trim();
    if (label.isNotEmpty ||
        data.hasAction(SemanticsAction.tap) ||
        data.flagsCollection.isTextField) {
      out.add({
        'label': label,
        if (data.hint.isNotEmpty) 'hint': data.hint,
        if (data.value.isNotEmpty) 'value': data.value,
        'tap': data.hasAction(SemanticsAction.tap),
        'button': data.flagsCollection.isButton,
        'textField': data.flagsCollection.isTextField,
        'rect': _rect(MatrixUtils.transformRect(matrix, node.rect)),
      });
    }
    node.visitChildren((child) {
      _walk(child, matrix, out);
      return true;
    });
  }

  Map<String, double> _rect(Rect r) => {
    'x': r.left.roundToDouble(),
    'y': r.top.roundToDouble(),
    'w': r.width.roundToDouble(),
    'h': r.height.roundToDouble(),
  };
}
