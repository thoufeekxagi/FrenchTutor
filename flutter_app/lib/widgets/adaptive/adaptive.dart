import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
      activeTrackColor: DesignTokens.maroon,
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
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel,
              style: destructive ? const TextStyle(color: DesignTokens.maroonDeep) : null),
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
              child: Text(title, style: DesignTokens.body(13).copyWith(color: DesignTokens.slateDim)),
            ),
          for (final a in actions)
            ListTile(
              title: Text(a.label,
                  style: a.destructive ? const TextStyle(color: DesignTokens.maroonDeep) : null),
              onTap: () => Navigator.of(context).pop(a.value),
            ),
        ],
      ),
    ),
  );
}

/// Loading spinner: CupertinoActivityIndicator on Apple platforms.
class PSProgressIndicator extends StatelessWidget {
  const PSProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return AppTheme.isCupertino
        ? const CupertinoActivityIndicator()
        : const CircularProgressIndicator(color: DesignTokens.maroon);
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

/// Constrains wide layouts (web/tablet) to a readable centered column;
/// pass-through on phones.
class PSContentColumn extends StatelessWidget {
  const PSContentColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < DesignTokens.breakpointMedium) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: DesignTokens.contentMaxWidth),
        child: child,
      ),
    );
  }
}
