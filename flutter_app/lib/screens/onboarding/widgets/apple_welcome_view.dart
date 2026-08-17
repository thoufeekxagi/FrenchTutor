import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../design/tokens.dart';

/// Apple-Standard Welcome Screen for ParleSprint.
/// Matches the verified Stitch design specification with high-contrast
/// typography, the official dual-bubble conversational brand mark, the
/// TEF/TCF trust badge, and Apple HIG compliant touch targets.
class AppleWelcomeView extends StatelessWidget {
  const AppleWelcomeView({
    super.key,
    required this.onGetStarted,
    this.onAlreadyHaveAccount,
  });

  final VoidCallback onGetStarted;
  final VoidCallback? onAlreadyHaveAccount;

  static const _brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      DesignTokens.primaryDeep,
      DesignTokens.primary,
      DesignTokens.secondary,
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: _brandGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // Brand Mark: Overlapping Conversation Bubbles + Wordmark
              const _BrandHeader(),

              const Spacer(flex: 3),

              // Centerpiece Editorial Card
              const _ValuePropositionCard(),

              const Spacer(flex: 4),

              // Primary Action: Get Started
              _PrimaryActionButton(onPressed: onGetStarted),

              const SizedBox(height: 12),

              // Secondary Action: I already have an account
              _SecondarySignInButton(
                onPressed: onAlreadyHaveAccount ?? onGetStarted,
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 88,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: const [
              Positioned(
                left: 10,
                top: 6,
                child: Icon(
                  CupertinoIcons.bubble_left_fill,
                  size: 46,
                  color: Colors.white,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 6,
                child: Icon(
                  CupertinoIcons.bubble_right_fill,
                  size: 38,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'ParleSprint',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.6,
          ),
        ),
      ],
    );
  }
}

class _ValuePropositionCard extends StatelessWidget {
  const _ValuePropositionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: DesignTokens.primaryDeep.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'French for the\nmoments that\nmatter.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: DesignTokens.ink,
              height: 1.22,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'A live tutor who talks with you every day, not flashcards about someday.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w400,
              color: DesignTokens.inkSoft,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: DesignTokens.canvas,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: DesignTokens.canvasDim),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  size: 15,
                  color: DesignTokens.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  'Built for TEF / TCF Canada learners',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DesignTokens.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: DesignTokens.primary,
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
        child: const Text('Get Started'),
      ),
    );
  }
}

class _SecondarySignInButton extends StatelessWidget {
  const _SecondarySignInButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignTokens.minTapTarget,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        child: Text(
          'I already have an account',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
