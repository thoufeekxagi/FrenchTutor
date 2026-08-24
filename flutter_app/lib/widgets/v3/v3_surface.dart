import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';

/// Shared dark surface primitives for the V3 product shell.
///
/// These widgets deliberately contain no navigation or product state. They
/// give the remaining destinations the same visual language as the approved
/// reading, listening, and speaking screens without changing their data
/// contracts.
class V3Scaffold extends StatelessWidget {
  const V3Scaffold({
    super.key,
    required this.child,
    this.floatingActionButton,
    this.backgroundColor,
  });

  final Widget child;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final dark = DesignTokens.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: DesignTokens.nightCanvas,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor ?? DesignTokens.nightCanvas,
        floatingActionButton: floatingActionButton,
        body: SafeArea(child: child),
      ),
    );
  }
}

class V3Header extends StatelessWidget {
  const V3Header({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 4),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.display(
                    28,
                  ).copyWith(color: DesignTokens.nightText),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    style: DesignTokens.body(
                      12,
                    ).copyWith(color: DesignTokens.nightMuted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class V3BackButton extends StatelessWidget {
  const V3BackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back',
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_rounded),
      color: DesignTokens.nightText,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}

class V3IconButton extends StatelessWidget {
  const V3IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.accent,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: accent ?? DesignTokens.nightText,
      style: IconButton.styleFrom(
        backgroundColor: DesignTokens.nightSurface,
        side: BorderSide(color: DesignTokens.nightHairline),
        shape: const CircleBorder(),
      ),
    );
  }
}

class V3SectionLabel extends StatelessWidget {
  const V3SectionLabel(this.text, {super.key, this.padding = EdgeInsets.zero});

  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: DesignTokens.label(
          11,
        ).copyWith(color: DesignTokens.nightAccent, letterSpacing: 1.5),
      ),
    );
  }
}

class V3Card extends StatelessWidget {
  const V3Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.raised = false,
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool raised;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: raised
            ? DesignTokens.nightSurfaceRaised
            : DesignTokens.nightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? DesignTokens.nightHairline),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: card),
    );
  }
}

class V3Row extends StatelessWidget {
  const V3Row({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.onTap,
    this.accent,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? DesignTokens.nightAccent;
    return V3Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 23),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(
                    15,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Text(
              value!,
              style: DesignTokens.body(
                12,
                weight: FontWeight.w700,
              ).copyWith(color: accentColor),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: DesignTokens.nightMuted),
          ],
        ],
      ),
    );
  }
}

class V3PrimaryButton extends StatelessWidget {
  const V3PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: DesignTokens.nightAccent,
        foregroundColor: Colors.black,
        disabledBackgroundColor: DesignTokens.nightHairline,
        disabledForegroundColor: DesignTokens.nightMuted,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: DesignTokens.body(15, weight: FontWeight.w800),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class V3Toggle extends StatelessWidget {
  const V3Toggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: DesignTokens.nightAccent,
      activeTrackColor: DesignTokens.nightAccentSoft,
      inactiveTrackColor: DesignTokens.nightHairline,
    );
  }
}

Future<T?> showV3Picker<T>({
  required BuildContext context,
  required String title,
  required List<V3PickerOption<T>> options,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: DesignTokens.nightSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: DesignTokens.display(
                  22,
                ).copyWith(color: DesignTokens.nightText),
              ),
              const SizedBox(height: 6),
              for (final option in options) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    option.icon,
                    color: option.value == selected
                        ? DesignTokens.nightAccent
                        : DesignTokens.nightMuted,
                  ),
                  title: Text(
                    option.label,
                    style: DesignTokens.body(
                      15,
                      weight: FontWeight.w700,
                    ).copyWith(color: DesignTokens.nightText),
                  ),
                  subtitle: option.description == null
                      ? null
                      : Text(
                          option.description!,
                          style: DesignTokens.body(
                            12,
                          ).copyWith(color: DesignTokens.nightMuted),
                        ),
                  trailing: option.value == selected
                      ? Icon(
                          Icons.check_rounded,
                          color: DesignTokens.nightAccent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option.value),
                ),
                if (option != options.last)
                  Divider(color: DesignTokens.nightHairline, height: 1),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class V3PickerOption<T> {
  const V3PickerOption({
    required this.value,
    required this.label,
    this.description,
    this.icon = Icons.check_circle_outline_rounded,
  });

  final T value;
  final String label;
  final String? description;
  final IconData icon;
}

class V3EmptyState extends StatelessWidget {
  const V3EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return V3Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: DesignTokens.nightAccent, size: 25),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.body(
                    15,
                    weight: FontWeight.w700,
                  ).copyWith(color: DesignTokens.nightText),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: DesignTokens.body(
                    12,
                  ).copyWith(color: DesignTokens.nightMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
