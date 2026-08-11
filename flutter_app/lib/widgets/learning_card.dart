import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Shared Guided Momentum surface for content that needs visual grouping.
///
/// Prefer open composition when a section does not need a distinct surface.
class LearningCard extends StatelessWidget {
  const LearningCard({
    super.key,
    required this.child,
    this.padding = DesignTokens.space4,
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final double padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: color ?? DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: borderColor ?? DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        child: content,
      ),
    );
  }
}
