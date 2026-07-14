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
  static const slate = DesignTokens.slate;
  static const slateDim = DesignTokens.slateDim;
  static const text = DesignTokens.text;
  static final hairline = DesignTokens.hairline;
  static final hairlineLight = DesignTokens.hairlineLight;

  static TextStyle display(double size, {FontWeight weight = FontWeight.w500}) =>
      DesignTokens.display(size, weight: weight);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.body(size, weight: weight);

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w400}) =>
      DesignTokens.mono(size, weight: weight);

  static ThemeData themeData() => AppTheme.themeData();
}
