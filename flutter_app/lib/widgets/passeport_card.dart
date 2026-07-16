import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Shared Guided Momentum surface for content that needs visual grouping.
///
/// Prefer open composition when a section does not need a distinct surface.
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
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        boxShadow: DesignTokens.cardShadow,
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}
