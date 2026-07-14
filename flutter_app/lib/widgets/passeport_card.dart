import 'package:flutter/material.dart';
import '../config/theme.dart';

class PasseportCard extends StatelessWidget {
  const PasseportCard({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Passeport.hairline, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Passeport.card,
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: child,
        ),
      ),
    );
  }
}
