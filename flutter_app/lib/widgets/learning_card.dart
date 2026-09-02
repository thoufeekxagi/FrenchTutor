import 'package:flutter/material.dart';

import '../design/tokens.dart';

class LearningCard extends StatelessWidget {
  const LearningCard({
    super.key,
    required this.child,
    this.padding = DesignTokens.space4,
    this.color,
    this.borderColor,
    this.onTap,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final double padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      decoration: BoxDecoration(
        color: color ?? DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(color: borderColor ?? DesignTokens.hairline),
        boxShadow: DesignTokens.surfaceShadow,
      ),
      clipBehavior: clipBehavior,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );

    if (onTap == null) return surface;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: surface,
      ),
    );
  }
}
