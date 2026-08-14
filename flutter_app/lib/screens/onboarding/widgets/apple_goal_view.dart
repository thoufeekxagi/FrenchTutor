import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../design/tokens.dart';

/// Apple-Standard Goal & Motivation Setup Step for ParleSprint.
/// Matches the verified Stitch design specification with step progress indicator,
/// high-contrast typography, interactive goal cards, and Apple HIG touch targets.
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
      title: 'TEF / TCF Canada',
      subtitle: 'Immigration points, Express Entry, and CLB 7+ prep',
      icon: CupertinoIcons.doc_text_fill,
    ),
    (
      id: 'everyday',
      title: 'Everyday French',
      subtitle: 'Travel, real-world confidence, and social conversations',
      icon: CupertinoIcons.chat_bubble_2_fill,
    ),
    (
      id: 'unsure',
      title: 'Build the Foundations',
      subtitle: 'Pronunciation, core grammar, and beginner structure',
      icon: CupertinoIcons.compass_fill,
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

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Eyebrow
                    Text(
                      'YOUR GOAL',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Headline
                    Text(
                      'What should French unlock for you?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Subtitle
                    Text(
                      'Your answer tailors every speaking session, vocabulary drill, and AI coach recommendation.',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        color: const Color(0xFF64748B),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Interactive Goal Cards
                    for (final goal in _goals)
                      _GoalCard(
                        title: goal.title,
                        subtitle: goal.subtitle,
                        icon: goal.icon,
                        isSelected: selectedGoal == goal.id,
                        onTap: () => onGoalSelected(goal.id),
                      ),
                  ],
                ),
              ),
            ),

            // Bottom CTA Area
            _BottomActionArea(
              enabled: selectedGoal != null,
              onContinue: onContinue,
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
    return Padding(
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
            child: Column(
              children: [
                Text(
                  'STEP 1 OF 3',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    height: 4,
                    width: 140,
                    color: const Color(0xFFE2E8F0),
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 4,
                      width: 140 * 0.33,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0062CC),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48), // Balancing spacer
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0062CC).withValues(alpha: 0.12)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? const Color(0xFF0062CC)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 16),
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
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF64748B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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

class _BottomActionArea extends StatelessWidget {
  const _BottomActionArea({
    required this.enabled,
    required this.onContinue,
  });

  final bool enabled;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: enabled ? onContinue : null,
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
          const SizedBox(height: 10),
          Text(
            'You can change this anytime in Settings',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
