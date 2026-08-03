/// Reusable web layout primitives — the shared vocabulary every screen uses
/// when it renders inside `WebAppShell` on a wide viewport.
///
/// Design language is modelled on the ElevenLabs dashboard (the reference the
/// founder picked): a light neutral canvas, white surfaces separated by 1px
/// hairlines rather than heavy shadows, generous whitespace, small muted
/// secondary text, and colour reserved for the single primary action. The
/// *structure* is borrowed; every colour/type value still comes from this
/// app's own tokens, never the reference's palette.
///
/// These are web-shaped on purpose (max-width columns, hover affordances,
/// multi-column grids) and are only mounted above
/// `DesignTokens.breakpointExpanded` — mobile keeps its own phone-native
/// screens untouched.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Widest the content column ever gets. Beyond this, whitespace grows instead
/// of line lengths — long measure is the single fastest way to make a web app
/// feel unconsidered.
const double kWebContentMaxWidth = 1120.0;

/// Standard page gutter on desktop. Deliberately larger than mobile's 20pt
/// `screenMargin`: a browser window has room to breathe and matching the
/// phone value is what makes a stretched mobile layout look cramped.
const double kWebGutter = 32.0;

/// A scrollable, max-width, centred page body.
///
/// Wrap a screen's content in this to give it desktop proportions. Pass
/// [header] for a page title block that scrolls with the content.
class WebPage extends StatelessWidget {
  const WebPage({
    super.key,
    required this.children,
    this.header,
    this.maxWidth = kWebContentMaxWidth,
  });

  final List<Widget> children;
  final Widget? header;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: kWebGutter,
        vertical: DesignTokens.space6,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null) ...[
                header!,
                const SizedBox(height: DesignTokens.space6),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Page-level title block: large title plus optional supporting line.
class WebPageHeader extends StatelessWidget {
  const WebPageHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Passeport.display(28)),
        if (subtitle != null) ...[
          const SizedBox(height: DesignTokens.space2),
          Text(
            subtitle!,
            style: Passeport.body(
              15,
            ).copyWith(color: DesignTokens.mutedDim, height: 1.45),
          ),
        ],
      ],
    );
  }
}

/// Section divider row: a bold section title with an optional trailing action
/// on the right, mirroring the reference's "Templates … View all" pattern.
class WebSectionHeader extends StatelessWidget {
  const WebSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Passeport.display(18))),
          if (actionLabel != null && onAction != null)
            WebTextAction(label: actionLabel!, onTap: onAction!),
        ],
      ),
    );
  }
}

/// A quiet text link/button for section actions. No Material ripple — the app
/// disables splashes globally, and a hover tint is the correct web affordance.
class WebTextAction extends StatefulWidget {
  const WebTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<WebTextAction> createState() => _WebTextActionState();
}

class _WebTextActionState extends State<WebTextAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.minTapTarget,
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: Passeport.body(13, weight: FontWeight.w600).copyWith(
                  color: _hovered
                      ? DesignTokens.primaryDeep
                      : DesignTokens.primary,
                ),
              ),
              const SizedBox(width: DesignTokens.space1),
              Icon(
                CupertinoIcons.chevron_right,
                size: 13,
                color: _hovered
                    ? DesignTokens.primaryDeep
                    : DesignTokens.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The workhorse surface: white card, hairline border, soft radius. Depth
/// comes from the border plus a whisper of shadow on hover, never Material
/// elevation.
class WebCard extends StatefulWidget {
  const WebCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(DesignTokens.space5),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<WebCard> createState() => _WebCardState();
}

class _WebCardState extends State<WebCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final card = AnimatedContainer(
      duration: DesignTokens.durationFast,
      curve: DesignTokens.curveStandard,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        border: Border.all(
          color: interactive && _hovered
              ? DesignTokens.primary.withValues(alpha: 0.35)
              : DesignTokens.hairline,
        ),
        boxShadow: interactive && _hovered ? DesignTokens.cardShadow : null,
      ),
      child: widget.child,
    );

    if (!interactive) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}

/// Responsive tile grid. Tiles reflow to fill the available width, each at
/// least [minTileWidth] wide — the reference's template-card row behaviour.
class WebCardGrid extends StatelessWidget {
  const WebCardGrid({
    super.key,
    required this.children,
    this.minTileWidth = 260.0,
    this.spacing = DesignTokens.space4,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // How many tiles fit at >= minTileWidth, accounting for the gaps
        // between them. Always at least one so a narrow window still renders.
        var columns = ((available + spacing) / (minTileWidth + spacing))
            .floor();
        if (columns < 1) columns = 1;
        if (columns > children.length) columns = children.length;
        final tileWidth = (available - spacing * (columns - 1)) / columns;

        // Laid out as explicit rows rather than a Wrap so every tile in a row
        // can share the tallest tile's height. A Wrap sizes each child
        // independently, which leaves card bottoms ragged whenever one
        // description wraps to an extra line — the single most obvious "this
        // was not designed" tell in a card grid.
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final end = (start + columns).clamp(0, children.length);
          final rowChildren = children.sublist(start, end);
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) SizedBox(width: spacing),
                    SizedBox(
                      width: tileWidth,
                      // Trailing slots in a partly-filled last row stay empty
                      // so the remaining tiles keep their column width instead
                      // of stretching to fill the gap.
                      child: i < rowChildren.length ? rowChildren[i] : null,
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// Small pill — used for suggestion chips and quiet metadata badges.
class WebChip extends StatelessWidget {
  const WebChip({super.key, required this.label, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? DesignTokens.mutedDim;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space3,
        vertical: DesignTokens.space2,
      ),
      decoration: BoxDecoration(
        color: DesignTokens.canvasDim,
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tint),
            const SizedBox(width: DesignTokens.space1 + 2),
          ],
          Text(
            label,
            style: Passeport.body(
              12,
              weight: FontWeight.w500,
            ).copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}
