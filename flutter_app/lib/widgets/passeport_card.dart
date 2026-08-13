import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'learning_card.dart';

/// Shared Guided Momentum surface for content that needs visual grouping.
///
/// Prefer open composition when a section does not need a distinct surface.
///
/// This compatibility name delegates to the shared learning surface so older
/// routes and the newer Stitch-aligned routes cannot drift apart.
class PasseportCard extends StatelessWidget {
  const PasseportCard({
    super.key,
    required this.child,
    this.padding = DesignTokens.space4,
  });

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return LearningCard(padding: padding, child: child);
  }
}
