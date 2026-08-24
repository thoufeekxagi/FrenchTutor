import 'package:flutter/material.dart';

import '../design/tokens.dart';

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
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
  final bool isLoading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      isLoading ? (loadingLabel ?? label) : label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final child = isLoading
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    DesignTokens.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.space2),
              text,
            ],
          )
        : icon == null
        ? text
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: DesignTokens.space2),
              text,
            ],
          );

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: DesignTokens.primary,
          disabledBackgroundColor: isLoading
              ? DesignTokens.primary
              : DesignTokens.muted.withValues(alpha: 0.35),
          disabledForegroundColor: isLoading ? DesignTokens.onPrimary : null,
          foregroundColor: DesignTokens.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(15, weight: FontWeight.w700),
        ),
        child: child,
      ),
    );
  }
}
