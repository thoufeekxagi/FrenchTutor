import 'package:flutter/material.dart';

import '../../design/tokens.dart';

abstract final class SpeakColors {
  static const background = DesignTokens.canvas;
  static const blue = DesignTokens.primary;
  static const blueSoft = DesignTokens.primarySoft;
  static const navy = DesignTokens.ink;
  static const inkSoft = DesignTokens.inkSoft;
  static const line = DesignTokens.canvasDim;
  static const green = DesignTokens.success;
  static const orange = DesignTokens.mastery;
}

class SpeakScaffold extends StatelessWidget {
  const SpeakScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpeakColors.background,
      body: SafeArea(child: child),
    );
  }
}

class SpeakHeader extends StatelessWidget {
  const SpeakHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?leading,
          if (leading != null) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DesignTokens.display(28)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: DesignTokens.body(
                      13,
                    ).copyWith(color: SpeakColors.inkSoft),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SpeakPill extends StatelessWidget {
  const SpeakPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: selected ? SpeakColors.blue : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? SpeakColors.blue : SpeakColors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : SpeakColors.inkSoft,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: DesignTokens.body(
              12,
              weight: FontWeight.w600,
            ).copyWith(color: selected ? Colors.white : SpeakColors.inkSoft),
          ),
        ],
      ),
    );
    return onTap == null
        ? child
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: child,
          );
  }
}

class SpeakSectionTitle extends StatelessWidget {
  const SpeakSectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onTap,
  });

  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: DesignTokens.display(20))),
        if (action != null)
          GestureDetector(
            onTap: onTap,
            child: Text(
              action!,
              style: DesignTokens.body(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: SpeakColors.blue),
            ),
          ),
      ],
    );
  }
}

class SpeakCard extends StatelessWidget {
  const SpeakCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SpeakColors.line),
      ),
      child: child,
    );
  }
}

class SpeakPrimaryButton extends StatelessWidget {
  const SpeakPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: onTap == null ? SpeakColors.line : SpeakColors.blue,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: DesignTokens.body(15, weight: FontWeight.w700).copyWith(
                color: onTap == null ? SpeakColors.inkSoft : Colors.white,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(
                icon,
                color: onTap == null ? SpeakColors.inkSoft : Colors.white,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SpeakProgressBar extends StatelessWidget {
  const SpeakProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        minHeight: 6,
        value: value.clamp(0, 1),
        backgroundColor: SpeakColors.line,
        valueColor: const AlwaysStoppedAnimation(SpeakColors.blue),
      ),
    );
  }
}

class SpeakStat extends StatelessWidget {
  const SpeakStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 6),
        Text(value, style: DesignTokens.body(15, weight: FontWeight.w700)),
        Text(
          label,
          style: DesignTokens.body(10).copyWith(color: SpeakColors.inkSoft),
        ),
      ],
    );
  }
}
