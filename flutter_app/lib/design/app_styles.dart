import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'tokens.dart';

export 'tokens.dart';

/// Back-compat alias: existing screens reference `AppStyles.*`. The real
/// definitions live in the design wiring (lib/design/) — tokens for values,
/// AppTheme for platform mapping. New code should import those directly;
/// existing call sites migrate screen-by-screen during Phase 4.
abstract final class AppStyles {
  static Color get ink => DesignTokens.ink;
  static Color get inkSoft => DesignTokens.inkSoft;
  static Color get primarySoft => DesignTokens.primarySoft;
  static Color get successSoft => DesignTokens.successSoft;
  static Color get infoSoft => DesignTokens.infoSoft;
  static Color get masterySoft => DesignTokens.masterySoft;
  static Color get text => DesignTokens.text;
  static final hairline = DesignTokens.hairline;
  static final hairlineLight = DesignTokens.hairlineLight;

  // Semantic names (canonical since the plug-and-play palette layer) — prefer
  // these over the legacy ParleSprint-era names above in new code.
  static Color get canvas => DesignTokens.canvas;
  static Color get canvasDim => DesignTokens.canvasDim;
  static Color get surface => DesignTokens.surface;
  static Color get primary => DesignTokens.primary;
  static Color get primaryDeep => DesignTokens.primaryDeep;
  static Color get secondary => DesignTokens.secondary;
  static Color get success => DesignTokens.success;
  static Color get info => DesignTokens.info;
  static Color get mastery => DesignTokens.mastery;
  static Color get warning => DesignTokens.warning;
  static Color get warningSoft => DesignTokens.warningSoft;
  static Color get danger => DesignTokens.danger;
  static Color get dangerSoft => DesignTokens.dangerSoft;
  static Color get muted => DesignTokens.muted;
  static Color get mutedDim => DesignTokens.mutedDim;

  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w500,
  }) => DesignTokens.display(size, weight: weight);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(size, weight: weight);

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w600}) =>
      DesignTokens.mono(size, weight: weight);

  static TextStyle label(double size, {FontWeight weight = FontWeight.w700}) =>
      DesignTokens.label(size, weight: weight);

  static ThemeData themeData({bool? darkMode}) =>
      AppTheme.themeData(darkMode: darkMode);
}
