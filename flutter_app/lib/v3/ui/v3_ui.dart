import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/adaptive/adaptive.dart' show PSHaptics;

/// V3 type scale. Left-aligned, large, tight. Headlines carry the screen;
/// nothing is centered unless it is a single glyph (a checkmark, a ring).
abstract final class V3Type {
  /// Oversized editorial headline (launch, welcome, big numbers).
  static TextStyle hero(double size, {Color? color}) =>
      DesignTokens.display(size, weight: FontWeight.w800).copyWith(
        color: color ?? DesignTokens.ink,
        letterSpacing: -size * 0.04,
        height: 0.98,
      );

  static TextStyle title(double size, {Color? color}) =>
      DesignTokens.display(size, weight: FontWeight.w800).copyWith(
        color: color ?? DesignTokens.ink,
        letterSpacing: -size * 0.025,
        height: 1.06,
      );

  static TextStyle body([double size = 16, Color? color]) =>
      DesignTokens.body(size).copyWith(
        color: color ?? DesignTokens.inkSoft,
        height: 1.45,
        letterSpacing: -0.1,
      );

  /// Long-form reading text (story sentences). Same family as the rest of
  /// the app, one step lighter than [strong]; never a different font.
  static TextStyle reading(double size, {Color? color}) =>
      DesignTokens.body(size, weight: FontWeight.w500).copyWith(
        color: color ?? DesignTokens.ink,
        height: 1.42,
        letterSpacing: -0.2,
      );

  static TextStyle strong([double size = 16, Color? color]) =>
      DesignTokens.body(
        size,
        weight: FontWeight.w700,
      ).copyWith(color: color ?? DesignTokens.ink, letterSpacing: -0.15);

  static TextStyle eyebrow([Color? color]) => DesignTokens.label(
    11,
  ).copyWith(color: color ?? DesignTokens.primary, letterSpacing: 1.8);
}

/// Press feedback for every V3 control: a quick scale, a selection haptic and
/// one clean semantics node (label on the control itself, never a wrapper).
class V3Pressable extends StatefulWidget {
  const V3Pressable({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.haptic = true,
    this.selected,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool haptic;
  final bool? selected;

  @override
  State<V3Pressable> createState() => _V3PressableState();
}

class _V3PressableState extends State<V3Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.label,
      selected: widget.selected,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                if (widget.haptic) PSHaptics.selection();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

enum V3ButtonKind { primary, dark, ghost }

class V3Button extends StatelessWidget {
  const V3Button({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = V3ButtonKind.primary,
    this.loading = false,
    this.trailingArrow = true,
  });

  final String label;
  final VoidCallback? onTap;
  final V3ButtonKind kind;
  final bool loading;
  final bool trailingArrow;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      V3ButtonKind.primary => (
        DesignTokens.primary,
        DesignTokens.onPrimary,
        null,
      ),
      V3ButtonKind.dark => (DesignTokens.ink, DesignTokens.canvas, null),
      V3ButtonKind.ghost => (
        Colors.transparent,
        DesignTokens.ink,
        DesignTokens.hairline,
      ),
    };
    final enabled = onTap != null && !loading;
    return V3Pressable(
      label: label,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled || loading ? 1 : 0.4,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  loading ? 'One moment' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    16,
                    weight: FontWeight.w700,
                  ).copyWith(color: fg, letterSpacing: -0.15),
                ),
              ),
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                )
              else if (trailingArrow)
                Icon(Icons.arrow_forward_rounded, color: fg, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calm text-only action, left aligned.
class V3TextAction extends StatelessWidget {
  const V3TextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return V3Pressable(
      label: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: DesignTokens.body(
            15,
            weight: FontWeight.w700,
          ).copyWith(color: DesignTokens.primary),
        ),
      ),
    );
  }
}

enum V3Tone { none, correct, wrong }

/// A selectable row: big title, quiet subtitle, a check that fills on select.
/// [tone] shows the result after an answer is checked.
class V3OptionCard extends StatelessWidget {
  const V3OptionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.selected,
    required this.onTap,
    this.tone = V3Tone.none,
  });

  final String title;
  final String? subtitle;
  final String? leading;
  final bool selected;
  final VoidCallback? onTap;
  final V3Tone tone;

  @override
  Widget build(BuildContext context) {
    final label = subtitle == null ? title : '$title, $subtitle';
    final marked = selected || tone != V3Tone.none;
    final accent = switch (tone) {
      V3Tone.correct => DesignTokens.success,
      V3Tone.wrong => DesignTokens.danger,
      V3Tone.none => DesignTokens.primary,
    };
    final soft = switch (tone) {
      V3Tone.correct => DesignTokens.successSoft,
      V3Tone.wrong => DesignTokens.dangerSoft,
      V3Tone.none => DesignTokens.primarySoft,
    };
    return V3Pressable(
      label: label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          color: marked ? soft : DesignTokens.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: marked ? accent : DesignTokens.hairline,
            width: marked ? 1.6 : 1,
          ),
          boxShadow: marked ? const [] : DesignTokens.surfaceShadow,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(
                width: 44,
                child: Text(
                  leading!,
                  style: V3Type.title(26, color: DesignTokens.primary),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: V3Type.strong(17)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: V3Type.body(13.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: marked ? accent : Colors.transparent,
                border: Border.all(
                  color: marked ? accent : DesignTokens.hairline,
                  width: 1.6,
                ),
              ),
              child: marked
                  ? Icon(
                      tone == V3Tone.wrong
                          ? Icons.close_rounded
                          : Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented progress: one segment per step, filled up to [current].
class V3Segments extends StatelessWidget {
  const V3Segments({super.key, required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    // Many steps do not fit as separate segments on a small screen, so long
    // lessons get one smooth bar instead.
    if (count > 12) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: (current + 1) / count,
          minHeight: 4,
          backgroundColor: DesignTokens.hairline,
          color: DesignTokens.primary,
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: i <= current
                    ? DesignTokens.primary
                    : DesignTokens.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Soft entrance: fade and rise, optionally staggered with [delayMs].
class V3FadeIn extends StatefulWidget {
  const V3FadeIn({super.key, required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  State<V3FadeIn> createState() => _V3FadeInState();
}

class _V3FadeInState extends State<V3FadeIn>
    with SingleTickerProviderStateMixin {
  static const _rise = 520;

  // One controller drives delay and motion, so it follows the frame clock
  // (no real-time timers) and behaves the same in tests and on device.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delayMs + _rise),
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delayMs / (widget.delayMs + _rise),
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - _a.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Plain left-aligned screen frame with the standard 24pt gutter.
class V3Screen extends StatelessWidget {
  const V3Screen({
    super.key,
    required this.child,
    this.background,
    this.padding = const EdgeInsets.fromLTRB(24, 12, 24, 20),
  });

  final Widget child;
  final Color? background;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background ?? DesignTokens.canvas,
      body: SafeArea(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// On wide screens (iPad, landscape) keeps content in a readable column at the
/// top, instead of stretching lines across 1 000+ points. On a phone it adds
/// nothing. Content stays left-aligned inside the column.
class V3Width extends StatelessWidget {
  const V3Width({super.key, required this.child, this.maxWidth = 680});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
