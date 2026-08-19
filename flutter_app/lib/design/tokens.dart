import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palettes.dart';

/// THE palette switch. Point this at any class in palettes.dart and the whole
/// app re-skins — screens only ever see the semantic tokens below, never a
/// palette directly, so swapping is one line + rebuild. See palettes.dart for
/// the slot contract and how to add a palette from a marketing mockup.
typedef _Palette = NorthstarStudio;

/// Layer 1 of the design wiring (PILOT_PLAN.md Phase 0.2): pure constants.
/// Semantic tokens — colors, type, spacing, radius, motion — with NO platform
/// or widget knowledge. Colors come from the active palette (typedef above);
/// Layer 2 (AppTheme) maps these to Material/Cupertino themes; Layer 3
/// (widgets/adaptive) renders per platform. A palette swap should only ever
/// touch the typedef; a structural redesign only this file + design skills.
///
/// Typography rules from the Northstar Studio reference:
///  - Plus Jakarta Sans carries confident headings and display moments.
///  - Inter carries reading, controls, labels, and data on every platform.
///  - No decorative type or monospace treatment in learner-facing content.
abstract final class DesignTokens {
  // --- Colors — every value comes from the active palette (typedef above).
  // Semantic names are canonical; the legacy names (parchment/card/maroon/
  // brass/sage/sky/slate) are aliases kept while older call sites migrate.
  static const ink = _Palette.ink;
  static const inkSoft = _Palette.inkSoft;
  static const canvas = _Palette.canvas;
  static const canvasDim = _Palette.canvasDim;
  static const surface = _Palette.surface;
  static const primary = _Palette.primary;
  static const primaryDeep = _Palette.primaryDeep;
  static const primarySoft = _Palette.primarySoft;
  static const secondary = _Palette.secondary;
  static const success = _Palette.success;
  static const successSoft = _Palette.successSoft;
  static const info = _Palette.info;
  static const infoSoft = _Palette.infoSoft;
  static const mastery = _Palette.mastery;
  static const masterySoft = _Palette.masterySoft;
  static const warning = _Palette.warning;
  static const warningSoft = _Palette.warningSoft;
  static const danger = _Palette.danger;
  static const dangerSoft = _Palette.dangerSoft;
  static const muted = _Palette.muted;
  static const mutedDim = _Palette.mutedDim;
  static const text = ink;

  // Legacy aliases (Passeport era) — migrate call sites, don't add new uses.
  static const parchment = canvas;
  static const parchmentDim = canvasDim;
  static const card = surface;
  static const maroon = primary;
  static const maroonDeep = primaryDeep;
  static const brass = mastery;
  static const sage = success;
  static const sky = info;
  static const slate = muted;
  static const slateDim = mutedDim;

  static final hairline = ink.withValues(alpha: 0.09);
  static final hairlineLight = canvas.withValues(alpha: 0.16);

  /// The shared full-bleed brand gradient — onboarding, sign-in, and any
  /// other gate-flow screen that wants the same identity all draw from this
  /// one definition instead of redeclaring it, so they never drift apart.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, primaryDeep],
  );

  // V3 night surface used by the redesigned Home experience. Keeping these
  // values here makes the dark/gold skin reusable by the next screen without
  // scattering brand colors through individual widgets.
  static const nightCanvas = Color(0xFF08090B);
  static const nightSurface = Color(0xFF151619);
  static const nightSurfaceRaised = Color(0xFF1D1E21);
  static const nightText = Color(0xFFF7F5F0);
  static const nightMuted = Color(0xFFA7A7A8);
  static const nightAccent = Color(0xFFF2B84B);
  static const nightAccentSoft = Color(0xFF3A2C17);
  static const nightHairline = Color(0xFF303136);
  static const nightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B0C0F), Color(0xFF1A1712)],
  );

  /// Surfaces rely on tonal layers and hairline borders instead of elevation.
  static List<BoxShadow> get surfaceShadow => const [];

  /// Compatibility name for screens that still use the original card widget.
  static List<BoxShadow> get cardShadow => surfaceShadow;

  // --- Spacing (4pt base grid) ---
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space7 = 28.0;
  static const space8 = 32.0;
  static const screenMargin = 20.0;

  // --- Radius ---
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusCard = 18.0;
  static const radiusLarge = 24.0;
  static const radiusPill = 100.0;

  // --- Hit targets (Apple HIG minimum) ---
  static const minTapTarget = 48.0;

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

  /// Display voice — Plus Jakarta Sans for confident, geometric headings.
  static TextStyle display(double size, {FontWeight weight = FontWeight.w700}) {
    final resolved = size >= 22
        ? (weight.value < FontWeight.w600.value ? FontWeight.w600 : weight)
        : (weight.value < FontWeight.w600.value ? FontWeight.w600 : weight);
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: resolved,
      color: ink,
      letterSpacing: size >= 22 ? -0.5 : -0.2,
    );
  }

  /// The UI voice — Inter for reading and controls on every platform.
  static TextStyle body(double size, {FontWeight weight = FontWeight.w400}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: ink,
      letterSpacing: -0.1,
    );
  }

  /// Compact metadata and badges use Inter with a little tracking.
  static TextStyle label(double size, {FontWeight weight = FontWeight.w700}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: ink,
      letterSpacing: 0.35,
    );
  }

  /// Backwards-compatible alias for metadata styles.
  static TextStyle mono(double size, {FontWeight weight = FontWeight.w600}) =>
      label(size, weight: weight);
}
