import 'package:flutter/material.dart';
import '../config/theme.dart';

class PasseportPrimaryButton extends StatelessWidget {
  const PasseportPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Text(label);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Passeport.maroon,
          disabledBackgroundColor: Passeport.slate.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: Passeport.body(15, weight: FontWeight.w600),
          elevation: 0,
        ),
        child: icon == null
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
