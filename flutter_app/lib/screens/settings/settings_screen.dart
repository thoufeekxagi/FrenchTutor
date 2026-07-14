import 'package:flutter/material.dart';
import '../../config/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
              Text('Settings', style: Passeport.display(24)),
              const SizedBox(height: 4),
              Text('App configuration', style: Passeport.body(14).copyWith(color: Passeport.slateDim)),
              Expanded(
                child: Center(
                  child: Text('Settings — Phase 2', style: Passeport.body(13).copyWith(color: Passeport.slate)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
