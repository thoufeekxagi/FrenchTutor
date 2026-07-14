import 'package:flutter/material.dart';
import '../../config/theme.dart';

class MocksScreen extends StatelessWidget {
  const MocksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Passeport.parchment,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text('Mock Exams', style: Passeport.display(24)),
              const SizedBox(height: 4),
              Text('TEF / TCF practice', style: Passeport.body(14).copyWith(color: Passeport.slateDim)),
              const Expanded(
                child: Center(child: Text('Coming soon')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
