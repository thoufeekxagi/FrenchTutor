import 'package:flutter/material.dart';

import 'primary_action_button.dart';

class PasseportPrimaryButton extends StatelessWidget {
  const PasseportPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Shows a spinner + [loadingLabel] instead of the idle label/icon, and
  /// disables the tap — for actions that trigger a real async wait (an LLM
  /// generation call) rather than an instant local action. Distinct from
  /// merely passing `onPressed: null`: an instantly-greyed button with no
  /// other signal reads as broken/unresponsive, not "working on it."
  final bool isLoading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return PrimaryActionButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      isLoading: isLoading,
      loadingLabel: loadingLabel,
    );
  }
}
