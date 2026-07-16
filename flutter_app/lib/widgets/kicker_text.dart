import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Compact metadata label used to introduce a section.
class KickerText extends StatelessWidget {
  const KickerText(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: DesignTokens.mono(
        11,
        weight: FontWeight.w600,
      ).copyWith(color: color ?? DesignTokens.slateDim),
    );
  }
}
