import 'package:flutter/material.dart';
import '../config/theme.dart';

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
    final labelWidget = Text(isLoading ? (loadingLabel ?? label) : label);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Passeport.maroon,
          disabledBackgroundColor: isLoading
              ? Passeport.maroon
              : Passeport.slate.withValues(alpha: 0.35),
          disabledForegroundColor: isLoading ? Colors.white : null,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: Passeport.body(15, weight: FontWeight.w600),
          elevation: 0,
        ),
        child: isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  labelWidget,
                ],
              )
            : icon == null
            ? labelWidget
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  labelWidget,
                ],
              ),
      ),
    );
  }
}
