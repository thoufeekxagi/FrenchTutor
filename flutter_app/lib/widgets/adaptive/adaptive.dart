import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/app_theme.dart';
import '../../design/tokens.dart';

/// Layer 3 of the design wiring: platform-adaptive primitives. One call site
/// in screen code; per-platform rendering decided here. Screens never import
/// package:flutter/cupertino.dart or branch on platform themselves.

/// iOS pill toggle on Apple platforms, Material switch elsewhere.
class PSSwitch extends StatelessWidget {
  const PSSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: DesignTokens.primary,
    );
  }
}

/// Confirm/alert dialog: CupertinoAlertDialog on Apple platforms.
/// Returns true when the primary action is chosen.
Future<bool> showPSConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  if (AppTheme.isCupertino) {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: destructive
                ? const TextStyle(color: DesignTokens.primary)
                : null,
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Action sheet: CupertinoActionSheet on Apple platforms, Material bottom
/// sheet elsewhere. Returns the tapped action's value.
Future<T?> showPSActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<({String label, T value, bool destructive})> actions,
}) {
  if (AppTheme.isCupertino) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: title != null ? Text(title) : null,
        actions: [
          for (final a in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: a.destructive,
              onPressed: () => Navigator.of(context).pop(a.value),
              child: Text(a.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.all(DesignTokens.space4),
              child: Text(
                title,
                style: DesignTokens.body(
                  13,
                ).copyWith(color: DesignTokens.slateDim),
              ),
            ),
          for (final a in actions)
            ListTile(
              title: Text(
                a.label,
                style: a.destructive
                    ? const TextStyle(color: DesignTokens.primary)
                    : null,
              ),
              onTap: () => Navigator.of(context).pop(a.value),
            ),
        ],
      ),
    ),
  );
}

/// Branded modal sheet with platform-native presentation mechanics.
Future<T?> showPSModalSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  if (AppTheme.isCupertino) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (context) =>
          Material(type: MaterialType.transparency, child: builder(context)),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: builder,
  );
}

/// Loading spinner: CupertinoActivityIndicator on Apple platforms.
class PSProgressIndicator extends StatelessWidget {
  const PSProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return AppTheme.isCupertino
        ? const CupertinoActivityIndicator()
        : const CircularProgressIndicator(color: DesignTokens.primary);
  }
}

/// Haptics facade — no-op on web, system haptics elsewhere. Use for grade
/// taps, stage completion, call connect. Never for decoration.
abstract final class PSHaptics {
  static void light() {
    if (!kIsWeb) HapticFeedback.lightImpact();
  }

  static void success() {
    if (!kIsWeb) HapticFeedback.mediumImpact();
  }

  static void selection() {
    if (!kIsWeb) HapticFeedback.selectionClick();
  }
}

/// Brand segmented control — same quiet pill selector on every platform
/// (replaces Material's SegmentedButton, whose outlined look breaks the vibe).
class PSSegmented<T> extends StatelessWidget {
  const PSSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<({T value, String label})> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.space1),
      decoration: BoxDecoration(
        color: DesignTokens.parchmentDim,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
      ),
      child: Row(
        children: segments.map((seg) {
          final isSelected = seg.value == selected;
          return Expanded(
            child: Semantics(
              button: true,
              selected: isSelected,
              label: seg.label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  PSHaptics.selection();
                  onChanged(seg.value);
                },
                child: AnimatedContainer(
                  duration: DesignTokens.durationFast,
                  curve: DesignTokens.curveStandard,
                  constraints: const BoxConstraints(
                    minHeight: DesignTokens.minTapTarget,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.space2,
                    vertical: DesignTokens.space2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? DesignTokens.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      DesignTokens.radiusSmall,
                    ),
                    border: Border.all(
                      color: isSelected
                          ? DesignTokens.hairline
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    seg.label,
                    textAlign: TextAlign.center,
                    style:
                        DesignTokens.body(
                          13,
                          weight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ).copyWith(
                          color: isSelected
                              ? DesignTokens.text
                              : DesignTokens.slateDim,
                        ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Date picker: iOS-style wheel in a bottom sheet on every platform — the
/// Material calendar dialog is the single most jarring "different app" moment.
Future<DateTime?> showPSDatePicker(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) async {
  DateTime selected = initial;
  final confirmed = await showPSModalSheet<bool>(
    context,
    builder: (context) => DecoratedBox(
      decoration: const BoxDecoration(
        color: DesignTokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusCard),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 300,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      'Done',
                      style: DesignTokens.body(
                        15,
                        weight: FontWeight.w600,
                      ).copyWith(color: DesignTokens.primary),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: initial,
                  minimumDate: first,
                  maximumDate: last,
                  onDateTimeChanged: (d) => selected = d,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return confirmed == true ? selected : null;
}

/// Constrains wide layouts (web/tablet) to a readable centered column;
/// pass-through on phones.
///
/// This is wired into ~10 screens (dashboard, path, labs, progress, settings,
/// notes, history), which makes it the single highest-leverage control over how
/// the app reads on a desktop browser.
///
/// It used to cap everything at `DesignTokens.contentMaxWidth` (560), which is
/// the right measure for the Daily Path column on a tablet but is *phone width*
/// on a 1440px monitor — the direct cause of interior screens looking like "a
/// phone screenshot in the middle of the screen". On web the cap now depends on
/// what the content actually is:
///
///  - [measure] `PSMeasure.reading` (~720) for prose and single-column forms,
///    where long lines genuinely hurt legibility.
///  - [measure] `PSMeasure.content` (~1080, the web default) for dashboards,
///    lists and card grids, which have structure and can use the room.
///
/// Native tablet keeps the original 560 column: there the narrow measure was a
/// deliberate reading decision, not an accident, and iOS is locked.
/// See docs/web_migration/07_web_ui_redesign.md.
enum PSMeasure {
  /// Prose and single-column forms.
  reading(720.0),

  /// Dashboards, lists, card grids.
  content(1080.0);

  const PSMeasure(this.webMaxWidth);

  final double webMaxWidth;
}

class PSContentColumn extends StatelessWidget {
  const PSContentColumn({
    super.key,
    required this.child,
    this.measure = PSMeasure.content,
  });

  final Widget child;
  final PSMeasure measure;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < DesignTokens.breakpointMedium) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kIsWeb ? measure.webMaxWidth : DesignTokens.contentMaxWidth,
        ),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Wraps a screen-bottom action (a primary button, usually) so it clears
/// the home indicator on notched iPhones/iPads instead of sitting flush
/// against it — a plain `Container`/`Padding` with a fixed vertical inset
/// only clears devices with no inset at all, and reads as cut off on every
/// other device. `SafeArea(top: false)` adds the real device inset, and the
/// extra 8px on top of it is deliberate breathing room so the button still
/// looks intentionally placed rather than merely "not clipped."
class PSBottomActionBar extends StatelessWidget {
  const PSBottomActionBar({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor ?? DesignTokens.canvas,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: child,
        ),
      ),
    );
  }
}
