import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../design/tokens.dart';

/// Luxury Apple-Standard Goal Selection Step for ParleSprint.
/// Features custom-tinted vector icon squircle badges (no raw emojis),
/// high-contrast hierarchy, 8pt spacing rhythm, and a zero-scroll above-the-fold layout.
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
      icon: CupertinoIcons.doc_text_fill,
      title: 'Canada Immigration',
      subtitle: 'TEF / TCF Canada prep',
    ),
    (
      id: 'everyday',
      icon: CupertinoIcons.airplane,
      title: 'Travel & Daily French',
      subtitle: 'Real-world conversations',
    ),
    (
      id: 'unsure',
      icon: CupertinoIcons.book_fill,
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

            // Content Area (Comfortable above-the-fold layout)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Headline
                    Text(
                      'What is your main goal?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 27,
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
                        fontSize: 14.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Luxury Selection Cards with Vector Badges
                    for (final goal in _goals)
                      _LuxuryGoalCard(
                        icon: goal.icon,
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

            // Bottom 54px CTA Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
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
                      letterSpacing: 1.2,
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

class _LuxuryGoalCard extends StatelessWidget {
  const _LuxuryGoalCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFF0062CC) : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? const Color(0xFF0062CC).withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.03),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Tinted Vector Squircle Badge
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0062CC).withValues(alpha: 0.12)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0062CC).withValues(alpha: 0.24)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? const Color(0xFF0062CC)
                      : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 16),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Apple Selection Indicator
              Container(
                width: 24,
                height: 24,
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
                        size: 14,
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
