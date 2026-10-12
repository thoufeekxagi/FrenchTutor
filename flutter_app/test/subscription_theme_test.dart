import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:french_tutor/design/appearance_colors.dart';
import 'package:french_tutor/design/tokens.dart';
import 'package:french_tutor/services/app_appearance_settings.dart';

void main() {
  final appearance = AppAppearanceSettings.shared;

  tearDown(() {
    appearance.adoptDarkMode(false);
  });

  test('light appearance resolves readable neutral and blue roles', () {
    appearance.adoptDarkMode(false);

    expect(DesignTokens.canvas, AppearanceColors.lightCanvas);
    expect(DesignTokens.surface, AppearanceColors.lightSurface);
    expect(DesignTokens.ink, AppearanceColors.lightText);
    expect(DesignTokens.primary, AppearanceColors.blueLight);
    expect(DesignTokens.primarySoft, AppearanceColors.blueSoftLight);
    expect(DesignTokens.mastery, AppearanceColors.goldDeep);
    expect(
      _contrast(DesignTokens.onPrimary, DesignTokens.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(DesignTokens.ink, DesignTokens.primarySoft),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('dark appearance resolves readable neutral and blue roles', () {
    appearance.adoptDarkMode(true);

    expect(DesignTokens.canvas, AppearanceColors.darkCanvas);
    expect(DesignTokens.surface, AppearanceColors.darkSurface);
    expect(DesignTokens.ink, AppearanceColors.darkText);
    expect(DesignTokens.primary, AppearanceColors.blueDark);
    expect(DesignTokens.primarySoft, AppearanceColors.blueSoftDark);
    expect(DesignTokens.mastery, AppearanceColors.gold);
    expect(
      _contrast(DesignTokens.onPrimary, DesignTokens.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(DesignTokens.ink, DesignTokens.primarySoft),
      greaterThanOrEqualTo(4.5),
    );
  });
}

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
