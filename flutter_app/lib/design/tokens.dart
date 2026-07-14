import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Layer 1 of the design wiring (PILOT_PLAN.md Phase 0.2): pure constants.
/// The Passeport identity — colors, type, spacing, radius, motion — with NO
/// platform or widget knowledge. Layer 2 (AppTheme) maps these to Material/
/// Cupertino themes; Layer 3 (widgets/adaptive) renders per platform.
/// A visual redesign should only ever touch this file + the design skills.
///
/// Typography rules (from ux-design/passeport style mockups):
///  - Serif (Playfair) is a DISPLAY voice only — the "Bonjour !" greeting,
///    screen titles, flashcard French words. Never below 22pt: small serif
///    reads as a dated "Times New Roman" app, which is exactly the failure
///    mode the mockups avoid. display() enforces this automatically.
///  - Everything else is Inter — an SF Pro-metrics sans that renders
///    identically on iOS/Android/web (one vibe, no Roboto bleed-through).
///  - No monospace anywhere; labels/badges are letterspaced Inter.
abstract final class DesignTokens {
  // --- Palette — warm paper + navy ink + bordeaux + real gold (see mockups) ---
  static const ink = Color(0xFF1B2A4A);
  static const inkSoft = Color(0xFF25375C);
  static const parchment = Color(0xFFF7F4EC); // warm paper, not near-white
  static const parchmentDim = Color(0xFFEFEAE0);
  static const card = Color(0xFFFFFFFF);
  static const maroon = Color(0xFF8E3B3B); // deep bordeaux, per mockup chips
  static const maroonDeep = Color(0xFF6E2C2C);
  static const brass = Color(0xFFB08D4A); // real gold — was mistakenly blue
  static const slate = Color(0xFF95A0B2);
  static const slateDim = Color(0xFF606C80);
  static const text = ink;
  static final hairline = ink.withValues(alpha: 0.10);
  static final hairlineLight = parchment.withValues(alpha: 0.16);

  /// Soft card shadow — depth via a whisper of ink, never Material elevation.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: ink.withValues(alpha: 0.06),
          blurRadius: 14,
          offset: const Offset(0, 3),
        ),
      ];

  // --- Spacing (4pt base grid) ---
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const screenMargin = 20.0;

  // --- Radius ---
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusCard = 16.0;
  static const radiusPill = 100.0;

  // --- Hit targets (Apple HIG minimum) ---
  static const minTapTarget = 44.0;

  // --- Motion: iOS-calibrated — quick, low-bounce, never elastic ---
  static const durationFast = Duration(milliseconds: 200);
  static const durationMedium = Duration(milliseconds: 300);
  static const durationSlow = Duration(milliseconds: 450);
  static const curveStandard = Curves.easeOutCubic;
  static const curveEmphasized = Curves.easeInOutCubic;

  // --- Responsive breakpoints (web/tablet) ---
  static const breakpointMedium = 600.0; // >= : centered content, rail nav
  static const breakpointExpanded = 1024.0;
  static const contentMaxWidth = 560.0; // Daily Path column on wide screens

  // --- Typography ---

  /// Editorial serif for HERO moments only. Below 22pt this silently returns
  /// the sans voice — a central guard so no call site can ship small serif.
  static TextStyle display(double size, {FontWeight weight = FontWeight.w500}) {
    if (size < 22) {
      return GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight.value < FontWeight.w600.value ? FontWeight.w600 : weight,
          color: ink,
          letterSpacing: -0.2);
    }
    return GoogleFonts.playfairDisplay(fontSize: size, fontWeight: weight, color: ink);
  }

  /// The UI voice — Inter everywhere (SF Pro look, identical cross-platform).
  static TextStyle body(double size, {FontWeight weight = FontWeight.w400}) {
    return GoogleFonts.inter(fontSize: size, fontWeight: weight, color: ink, letterSpacing: -0.1);
  }

  /// Labels, badges, kickers, numbers — letterspaced Inter medium (the old
  /// JetBrains Mono techy look is gone; mockups use quiet spaced caps).
  static TextStyle mono(double size, {FontWeight weight = FontWeight.w500}) {
    return GoogleFonts.inter(fontSize: size, fontWeight: weight, color: ink, letterSpacing: 0.4);
  }
}
