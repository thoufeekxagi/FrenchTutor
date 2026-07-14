import 'package:flutter/material.dart';
import '../config/theme.dart';

class PasseportPrimaryButton extends StatelessWidget {
  const PasseportPrimaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Passeport.maroon,
          foregroundColor: Passeport.parchment,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: Passeport.body(15, weight: FontWeight.w500),
          elevation: 0,
        ),
        child: Text(label),
      ),
    );
  }
}
