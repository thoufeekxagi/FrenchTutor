import 'package:flutter/material.dart';

/// The only palette values used by the application-wide appearance system.
///
/// Both appearances use the same gold action color. The surfaces and text
/// invert around it so navigation, practice screens, and nested lesson flows
/// keep the same hierarchy in either mode.
abstract final class AppearanceColors {
  // Dark appearance.
  static const darkCanvas = Color(0xFF08090B);
  static const darkSurface = Color(0xFF151619);
  static const darkRaised = Color(0xFF1D1E21);
  static const darkText = Color(0xFFF7F5F0);
  static const darkMuted = Color(0xFFA7A7A8);
  static const darkHairline = Color(0xFF303136);

  // Light appearance.
  static const lightCanvas = Color(0xFFFBFAF7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightRaised = Color(0xFFF4F0E6);
  static const lightText = Color(0xFF17130D);
  static const lightMuted = Color(0xFF746F65);
  static const lightHairline = Color(0xFFE4DED1);

  // Shared brand and semantic states.
  static const gold = Color(0xFFF2B84B);
  static const goldDeep = Color(0xFFB97823);
  static const goldSoftDark = Color(0xFF3A2C17);
  static const goldSoftLight = Color(0xFFFFF1CC);
  static const success = Color(0xFF2D8A5B);
  static const successSoftDark = Color(0xFF153522);
  static const successSoftLight = Color(0xFFE8F4ED);
  static const danger = Color(0xFFC95757);
  static const dangerSoftDark = Color(0xFF3D1D1D);
  static const dangerSoftLight = Color(0xFFF9E7E7);
}
