import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// The house card: white on warm paper, generous radius, depth from a
/// whisper-soft shadow — no borders, no Material elevation (see
/// ux-design/passeport style mockups).
class PasseportCard extends StatelessWidget {
  const PasseportCard({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.card,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        boxShadow: DesignTokens.cardShadow,
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: child,
      ),
    );
  }
}
