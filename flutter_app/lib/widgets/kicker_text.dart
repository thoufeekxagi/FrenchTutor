import 'package:flutter/material.dart';
import '../config/theme.dart';

class KickerText extends StatelessWidget {
  const KickerText(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Passeport.mono(10, weight: FontWeight.w500).copyWith(
        letterSpacing: 0.8,
        color: color ?? Passeport.brass,
      ),
    );
  }
}
