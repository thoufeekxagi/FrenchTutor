import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/tokens.dart';

export '../design/tokens.dart';

/// Back-compat alias: existing screens reference `Passeport.*`. The real
/// definitions live in the design wiring (lib/design/) — tokens for values,
/// AppTheme for platform mapping. New code should import those directly;
/// existing call sites migrate screen-by-screen during Phase 4.
abstract final class Passeport {
  static Color get ink => DesignTokens.ink;
  static Color get inkSoft => DesignTokens.inkSoft;
  static Color get parchment => DesignTokens.parchment;
  static Color get parchmentDim => DesignTokens.parchmentDim;
  static Color get card => DesignTokens.card;
  static Color get maroon => DesignTokens.maroon;
  static Color get maroonDeep => DesignTokens.maroonDeep;
  static Color get brass => DesignTokens.brass;
  static Color get sage => DesignTokens.sage;
  static Color get sky => DesignTokens.sky;
  static Color get primarySoft => DesignTokens.primarySoft;
  static Color get successSoft => DesignTokens.successSoft;
  static Color get infoSoft => DesignTokens.infoSoft;
  static Color get masterySoft => DesignTokens.masterySoft;
  static Color get slate => DesignTokens.slate;
  static Color get slateDim => DesignTokens.slateDim;
  static Color get text => DesignTokens.text;
  static final hairline = DesignTokens.hairline;
  static final hairlineLight = DesignTokens.hairlineLight;

  // Semantic names (canonical since the plug-and-play palette layer) — prefer
  // these over the legacy Passeport-era names above in new code.
  static Color get canvas => DesignTokens.canvas;
  static Color get canvasDim => DesignTokens.canvasDim;
  static Color get surface => DesignTokens.surface;
  static Color get primary => DesignTokens.primary;
  static Color get primaryReadable => DesignTokens.primaryReadable;
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

  static ThemeData themeData({bool? darkMode}) =>
      AppTheme.themeData(darkMode: darkMode);
}
