import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'appearance_colors.dart';
import '../services/app_appearance_settings.dart';

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
  // --- Colors — one runtime appearance source for every screen.
  // Semantic names are canonical; the legacy names (parchment/card/maroon/
  // brass/sage/sky/slate) remain aliases while older call sites migrate.
  static bool get isDark => AppAppearanceSettings.shared.darkMode;

  static Color get ink =>
      isDark ? AppearanceColors.darkText : AppearanceColors.lightText;
  static Color get inkSoft =>
      isDark ? AppearanceColors.darkMuted : AppearanceColors.lightMuted;
  static Color get canvas =>
      isDark ? AppearanceColors.darkCanvas : AppearanceColors.lightCanvas;
  static Color get canvasDim =>
      isDark ? AppearanceColors.darkSurface : AppearanceColors.lightRaised;
  static Color get surface =>
      isDark ? AppearanceColors.darkSurface : AppearanceColors.lightSurface;
  // The bright gold is comfortable on the dark canvas. In light mode the
  // darker gold is the action/accent role so labels and icons do not wash out
  // against white surfaces.
  static Color get primary =>
      isDark ? AppearanceColors.gold : AppearanceColors.goldDeep;
  static Color get primaryReadable => primary;
  static Color get primaryDeep => AppearanceColors.goldDeep;
  static Color get primarySoft =>
      isDark ? AppearanceColors.goldSoftDark : AppearanceColors.goldSoftLight;
  // Secondary/info are semantic slots, not a second brand color. They share
  // the gold accent so legacy screens cannot reintroduce a competing hue.
  static Color get secondary => AppearanceColors.goldDeep;
  static Color get success => AppearanceColors.success;
  static Color get successSoft => isDark
      ? AppearanceColors.successSoftDark
      : AppearanceColors.successSoftLight;
  static Color get info => AppearanceColors.goldDeep;
  static Color get infoSoft => primarySoft;
  static Color get mastery => AppearanceColors.goldDeep;
  static Color get masterySoft => primarySoft;
  static Color get warning => AppearanceColors.goldDeep;
  static Color get warningSoft => primarySoft;
  static Color get danger => AppearanceColors.danger;
  static Color get dangerSoft => isDark
      ? AppearanceColors.dangerSoftDark
      : AppearanceColors.dangerSoftLight;
  static Color get muted =>
      isDark ? AppearanceColors.darkMuted : AppearanceColors.lightMuted;
  static Color get mutedDim => isDark
      ? AppearanceColors.darkMuted.withValues(alpha: 0.78)
      : AppearanceColors.lightMuted.withValues(alpha: 0.84);
  static Color get text => ink;
  static Color get onPrimary => const Color(0xFF000000);

  // Legacy aliases (Passeport era) — migrate call sites, don't add new uses.
  static Color get parchment => canvas;
  static Color get parchmentDim => canvasDim;
  static Color get card => surface;
  static Color get maroon => primary;
  static Color get maroonReadable => primaryReadable;
  static Color get maroonDeep => primaryDeep;
  static Color get brass => mastery;
  static Color get sage => success;
  static Color get sky => info;
  static Color get slate => muted;
  static Color get slateDim => mutedDim;

  static Color get hairline => ink.withValues(alpha: 0.09);
  static Color get hairlineLight => canvas.withValues(alpha: 0.16);

  /// The shared full-bleed brand gradient — onboarding, sign-in, and any
  /// other gate-flow screen that wants the same identity all draw from this
  /// one definition instead of redeclaring it, so they never drift apart.
  static LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [canvas, primarySoft],
  );

  // V3 night surface used by the redesigned Home experience. Keeping these
  // values here makes the dark/gold skin reusable by the next screen without
  // scattering brand colors through individual widgets.
  static Color get nightCanvas => canvas;
  static Color get nightSurface => surface;
  static Color get nightSurfaceRaised =>
      isDark ? AppearanceColors.darkRaised : AppearanceColors.lightRaised;
  static Color get nightText => ink;
  static Color get nightMuted => muted;
  static Color get nightAccent => primary;
  static Color get nightAccentSoft => primarySoft;
  static Color get nightHairline => hairline;
  static LinearGradient get nightGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [canvas, isDark ? AppearanceColors.darkRaised : primarySoft],
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
