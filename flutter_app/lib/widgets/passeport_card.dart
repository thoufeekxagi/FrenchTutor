import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Shared Guided Momentum surface for content that needs visual grouping.
///
/// Prefer open composition when a section does not need a distinct surface.
///
/// Web note: this one widget backs ~56 surfaces across the app, which makes it
/// the highest-leverage place to carry the web design language. On mobile a card
/// is a soft shadow with no border (the iOS look). The web reference aesthetic
/// (ElevenLabs / shadcn) defines a card as a 1px hairline border with essentially
/// no shadow — depth comes from the border, not from lift. Branching here
/// restyles every card in the app at once rather than screen by screen, and
/// keeps both looks in one place so they cannot drift apart.
/// See docs/web_migration/07_web_ui_redesign.md.
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
        border: kIsWeb ? Border.all(color: DesignTokens.hairline) : null,
        // Keeping the mobile shadow as well would look muddy against a neutral
        // canvas — on web the hairline alone does the separating.
        boxShadow: kIsWeb ? null : DesignTokens.cardShadow,
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}
