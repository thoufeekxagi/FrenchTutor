import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../design/tokens.dart';

/// Streamlined, High-Conversion Goal Selection Step for ParleSprint.
/// Optimized for low cognitive load and zero-scroll above-the-fold layout.
class AppleGoalView extends StatelessWidget {
  const AppleGoalView({
    super.key,
    required this.selectedGoal,
    required this.onGoalSelected,
    required this.onContinue,
    required this.onBack,
  });

  final String? selectedGoal;
  final ValueChanged<String> onGoalSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  static const _goals = [
    (
      id: 'tef_canada',
      emoji: '🍁',
      title: 'Canada Immigration',
      subtitle: 'TEF / TCF Canada',
    ),
    (
      id: 'everyday',
      emoji: '✈️',
      title: 'Travel & Daily French',
      subtitle: 'Real conversations',
    ),
    (
      id: 'unsure',
      emoji: '🌱',
      title: 'Complete Beginner',
      subtitle: 'Start from scratch',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignTokens.canvas,
      child: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Step Progress
            _TopStepHeader(onBack: onBack),

            // Content Area (Fits perfectly above the fold)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Headline
                    Text(
                      'What is your main goal?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    Text(
                      'Personalizes your daily coach.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Streamlined Goal Cards
                    for (final goal in _goals)
                      _GoalCard(
                        emoji: goal.emoji,
                        title: goal.title,
                        subtitle: goal.subtitle,
                        isSelected: selectedGoal == goal.id,
                        onTap: () => onGoalSelected(goal.id),
                      ),

                    const Spacer(),
                  ],
                ),
              ),
            ),

            // Bottom CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: selectedGoal != null ? onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0062CC),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
                    ),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  child: const Text('Continue →'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopStepHeader extends StatelessWidget {
  const _TopStepHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(
                  CupertinoIcons.chevron_back,
                  size: 22,
                  color: Color(0xFF0F172A),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'STEP 1 OF 3',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48), // Spacer to balance back button
            ],
          ),
        ),
        Container(
          height: 3,
          width: double.infinity,
          color: const Color(0xFFE2E8F0),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.33,
            child: Container(
              color: const Color(0xFF0062CC),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF0062CC) : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? const Color(0xFF0062CC).withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? const Color(0xFF0062CC)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0062CC)
                        : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        size: 13,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
