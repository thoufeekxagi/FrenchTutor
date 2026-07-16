import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/tokens.dart';

export '../design/tokens.dart';

/// Back-compat alias: existing screens reference `Passeport.*`. The real
/// definitions live in the design wiring (lib/design/) — tokens for values,
/// AppTheme for platform mapping. New code should import those directly;
/// existing call sites migrate screen-by-screen during Phase 4.
abstract final class Passeport {
  static const ink = DesignTokens.ink;
  static const inkSoft = DesignTokens.inkSoft;
  static const parchment = DesignTokens.parchment;
  static const parchmentDim = DesignTokens.parchmentDim;
  static const card = DesignTokens.card;
  static const maroon = DesignTokens.maroon;
  static const maroonDeep = DesignTokens.maroonDeep;
  static const brass = DesignTokens.brass;
  static const sage = DesignTokens.sage;
  static const sky = DesignTokens.sky;
  static const primarySoft = DesignTokens.primarySoft;
  static const successSoft = DesignTokens.successSoft;
  static const infoSoft = DesignTokens.infoSoft;
  static const masterySoft = DesignTokens.masterySoft;
  static const slate = DesignTokens.slate;
  static const slateDim = DesignTokens.slateDim;
  static const text = DesignTokens.text;
  static final hairline = DesignTokens.hairline;
  static final hairlineLight = DesignTokens.hairlineLight;

  // Semantic names (canonical since the plug-and-play palette layer) — prefer
  // these over the legacy Passeport-era names above in new code.
  static const canvas = DesignTokens.canvas;
  static const canvasDim = DesignTokens.canvasDim;
  static const surface = DesignTokens.surface;
  static const primary = DesignTokens.primary;
  static const primaryDeep = DesignTokens.primaryDeep;
  static const secondary = DesignTokens.secondary;
  static const success = DesignTokens.success;
  static const info = DesignTokens.info;
  static const mastery = DesignTokens.mastery;
  static const warning = DesignTokens.warning;
  static const warningSoft = DesignTokens.warningSoft;
  static const danger = DesignTokens.danger;
  static const dangerSoft = DesignTokens.dangerSoft;
  static const muted = DesignTokens.muted;
  static const mutedDim = DesignTokens.mutedDim;

  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w500,
  }) => DesignTokens.display(size, weight: weight);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(size, weight: weight);

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.mono(size, weight: weight);

  static ThemeData themeData() => AppTheme.themeData();
}
