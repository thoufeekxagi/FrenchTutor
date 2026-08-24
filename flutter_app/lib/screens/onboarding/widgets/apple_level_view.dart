import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../design/tokens.dart';

/// Luxury Apple-Standard Level Calibration Step for ParleSprint.
/// Features vector squircle badge icons, CEFR level cards, 3-segment daily
/// commitment selector, and 54px solid action CTA.
class AppleLevelView extends StatelessWidget {
  const AppleLevelView({
    super.key,
    required this.selectedLevel,
    required this.sessionLength,
    required this.onLevelSelected,
    required this.onSessionLengthChanged,
    required this.onContinue,
    required this.onBack,
  });

  final String? selectedLevel;
  final String sessionLength;
  final ValueChanged<String> onLevelSelected;
  final ValueChanged<String> onSessionLengthChanged;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  static const _levels = [
    (
      id: 'a1',
      icon: CupertinoIcons.sparkles,
      title: 'A1 · Just Starting',
      subtitle: 'No prior French knowledge',
    ),
    (
      id: 'a2',
      icon: CupertinoIcons.chat_bubble_text_fill,
      title: 'A2 · Elementary',
      subtitle: 'Basic phrases & greetings',
    ),
    (
      id: 'b1',
      icon: CupertinoIcons.quote_bubble_fill,
      title: 'B1 · Intermediate',
      subtitle: 'Simple conversations',
    ),
    (
      id: 'b2',
      icon: CupertinoIcons.star_fill,
      title: 'B2 · Advanced',
      subtitle: 'Polishing fluency & precision',
    ),
  ];

  static const _lengths = [
    (id: 'quick', label: '5 min'),
    (id: 'standard', label: '15 min'),
    (id: 'deep', label: '30 min'),
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

            // Scrollable Content Canvas
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Headline
                    Text(
                      'Where are you starting from?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: DesignTokens.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    Text(
                      'Sets your vocabulary level and speech pace.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: DesignTokens.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Level Selection Cards
                    for (final lvl in _levels)
                      _LevelCard(
                        icon: lvl.icon,
                        title: lvl.title,
                        subtitle: lvl.subtitle,
                        isSelected: selectedLevel == lvl.id,
                        onTap: () => onLevelSelected(lvl.id),
                      ),

                    const SizedBox(height: 16),

                    // Daily Commitment Segmented Row
                    Text(
                      'DAILY COMMITMENT',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: DesignTokens.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _SessionLengthSegmented(
                      lengths: _lengths,
                      selected: sessionLength,
                      onChanged: onSessionLengthChanged,
                    ),
                  ],
                ),
              ),
            ),

            // Bottom CTA Area
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: selectedLevel != null ? onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesignTokens.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: DesignTokens.canvasDim,
                    disabledForegroundColor: DesignTokens.muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusPill,
                      ),
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
                icon: Icon(
                  CupertinoIcons.chevron_back,
                  size: 22,
                  color: DesignTokens.ink,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'STEP 2 OF 3',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: DesignTokens.inkSoft,
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
          color: DesignTokens.canvasDim,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.66,
            child: Container(color: DesignTokens.primary),
          ),
        ),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
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
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? DesignTokens.primarySoft : DesignTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? DesignTokens.primary : DesignTokens.canvasDim,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? DesignTokens.primary.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Vector Squircle Badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? DesignTokens.primary.withValues(alpha: 0.12)
                      : DesignTokens.canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: isSelected
                      ? DesignTokens.primary
                      : DesignTokens.inkSoft,
                ),
              ),
              const SizedBox(width: 14),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DesignTokens.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: DesignTokens.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Apple Checkmark or Radio
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? DesignTokens.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? DesignTokens.primary
                        : DesignTokens.canvasDim,
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

class _SessionLengthSegmented extends StatelessWidget {
  const _SessionLengthSegmented({
    required this.lengths,
    required this.selected,
    required this.onChanged,
  });

  final List<({String id, String label})> lengths;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: DesignTokens.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesignTokens.canvasDim),
      ),
      child: Row(
        children: lengths.map((item) {
          final isItemActive = selected == item.id;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(item.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isItemActive ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isItemActive
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  item.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isItemActive
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: isItemActive
                        ? DesignTokens.ink
                        : DesignTokens.inkSoft,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
