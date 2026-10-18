import 'package:flutter/material.dart';

/// The only palette values used by the application-wide appearance system.
///
/// V3 direction (see docs/v3/DESIGN_SYSTEM.md): light by default with white
/// and cool gray surfaces, one calm blue action color (cool blues read as
/// trustworthy and calm for a high-stakes exam), green for correct, and gold
/// kept only for mastery and targets. Dark appearance stays black and uses a
/// lighter blue so contrast holds. Every pairing below meets WCAG AA for its
/// intended use (text 4.5:1, large text and icons 3:1).
abstract final class AppearanceColors {
  // Dark appearance (black).
  static const darkCanvas = Color(0xFF08090B);
  static const darkSurface = Color(0xFF151619);
  static const darkRaised = Color(0xFF1D1E21);
  static const darkText = Color(0xFFF7F5F0);
  static const darkMuted = Color(0xFFA7A7A8);
  static const darkHairline = Color(0xFF303136);

  // Light appearance (white and cool grays).
  static const lightCanvas = Color(0xFFF5F6F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightRaised = Color(0xFFECEEF2);
  static const lightText = Color(0xFF14171C);
  static const lightMuted = Color(0xFF5F6673);
  static const lightHairline = Color(0xFFE1E4EA);

  // Action blue.
  static const blueLight = Color(0xFF2563EB);
  static const blueDeep = Color(0xFF1D4ED8);
  static const blueDark = Color(0xFF6B9BFF);
  static const blueSoftLight = Color(0xFFE8EFFE);
  static const blueSoftDark = Color(0xFF14213F);
  static const onBlueLight = Color(0xFFFFFFFF);
  static const onBlueDark = Color(0xFF08090B);

  // Gold: mastery, targets and the exam goal only. Never an action color.
  static const gold = Color(0xFFF2B84B);
  static const goldDeep = Color(0xFFB97823);
  static const goldSoftDark = Color(0xFF3A2C17);
  static const goldSoftLight = Color(0xFFFFF1CC);

  // Semantic states.
  static const successLight = Color(0xFF15803D);
  static const successDark = Color(0xFF4ADE80);
  static const successSoftDark = Color(0xFF12301F);
  static const successSoftLight = Color(0xFFE7F6EC);
  static const dangerLight = Color(0xFFC62828);
  static const dangerDark = Color(0xFFF87171);
  static const dangerSoftDark = Color(0xFF3D1D1D);
  static const dangerSoftLight = Color(0xFFFCE9E9);

  // Home's small practice tiles keep their category tint while the main
  // action remains the shared blue accent.
  static const homeFlame = Color(0xFFF28B35);
  static const homeViolet = Color(0xFF8053D7);
  static const homeVioletSoft = Color(0xFFF1EBFF);
  static const homeTeal = Color(0xFF0F766E);
  static const homeTealSoft = Color(0xFFE3F5F1);
  static const homeAmber = Color(0xFFE99424);
  static const homeAmberSoft = Color(0xFFFFF3E3);
  static const homePathCanvas = Color(0xFFF7FAFF);

  static Color homeFlameFor(bool dark) =>
      dark ? const Color(0xFFFFA45B) : homeFlame;
  static Color homeVioletFor(bool dark) =>
      dark ? const Color(0xFFBDA2FF) : homeViolet;
  static Color homeVioletSoftFor(bool dark) =>
      dark ? const Color(0xFF2B2140) : homeVioletSoft;
  static Color homeTealFor(bool dark) =>
      dark ? const Color(0xFF53C8B7) : homeTeal;
  static Color homeTealSoftFor(bool dark) =>
      dark ? const Color(0xFF15332F) : homeTealSoft;
  static Color homeAmberFor(bool dark) =>
      dark ? const Color(0xFFFFC36E) : homeAmber;
  static Color homeAmberSoftFor(bool dark) =>
      dark ? const Color(0xFF3A2C17) : homeAmberSoft;

  static Color accentFor(bool dark) => dark ? blueDark : blueLight;
  static Color accentSoftFor(bool dark) => dark ? blueSoftDark : blueSoftLight;
  static Color onAccentFor(bool dark) => dark ? onBlueDark : onBlueLight;
  static Color successFor(bool dark) => dark ? successDark : successLight;
  static Color dangerFor(bool dark) => dark ? dangerDark : dangerLight;
}
