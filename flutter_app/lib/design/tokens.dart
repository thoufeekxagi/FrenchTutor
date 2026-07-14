import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Layer 1 of the design wiring (PILOT_PLAN.md Phase 0.2): pure constants.
/// The Passeport identity — colors, type, spacing, radius, motion — with NO
/// platform or widget knowledge. Layer 2 (AppTheme) maps these to Material/
/// Cupertino themes; Layer 3 (widgets/adaptive) renders per platform.
/// A visual redesign should only ever touch this file + the design skills.
abstract final class DesignTokens {
  // --- Palette — pastel take on the French flag (bleu / blanc / rouge) ---
  static const ink = Color(0xFF1B2A4A);
  static const inkSoft = Color(0xFF25375C);
  static const parchment = Color(0xFFFAF9F6);
  static const parchmentDim = Color(0xFFEDF1F7);
  static const card = Color(0xFFFFFFFF);
  static const maroon = Color(0xFFC8433E);
  static const maroonDeep = Color(0xFFA83229);
  static const brass = Color(0xFF6B8FC4);
  static const slate = Color(0xFF95A0B2);
  static const slateDim = Color(0xFF606C80);
  static const text = ink;
  static final hairline = ink.withValues(alpha: 0.12);
  static final hairlineLight = parchment.withValues(alpha: 0.16);

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
  static const radiusMedium = 10.0;
  static const radiusCard = 14.0;
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
  static TextStyle display(double size, {FontWeight weight = FontWeight.w500}) {
    return GoogleFonts.playfairDisplay(fontSize: size, fontWeight: weight, color: ink);
  }

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400}) {
    return TextStyle(fontSize: size, fontWeight: weight, color: ink);
  }

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w400}) {
    return GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: ink);
  }
}
