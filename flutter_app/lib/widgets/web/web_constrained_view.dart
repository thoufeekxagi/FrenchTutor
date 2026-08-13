import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class WebConstrainedView extends StatelessWidget {
  const WebConstrainedView({
    super.key,
    required this.child,
    this.maxWidth = 920,
    this.padding = const EdgeInsets.fromLTRB(32, 24, 32, 40),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < DesignTokens.breakpointExpanded) {
      return child;
    }
    return ColoredBox(
      color: DesignTokens.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
