import 'package:flutter/material.dart';
import '../config/theme.dart';

class PasseportCard extends StatelessWidget {
  const PasseportCard({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Passeport.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
      ),
      child: child,
    );
  }
}
