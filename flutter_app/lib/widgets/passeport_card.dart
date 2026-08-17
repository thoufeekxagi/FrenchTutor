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
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final double padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return LearningCard(
      padding: padding,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

/// Neutral migration alias used by routes that have moved to the current
/// visual language while retaining the shared surface implementation.
typedef ModernCard = PasseportCard;
