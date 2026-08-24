import 'package:flutter/widgets.dart';

/// Layer 0 of the design wiring: PALETTES — plug-and-play color skins.
///
/// Every palette is an `abstract final class` exposing the SAME static const
/// slots (the palette contract below). `tokens.dart` selects one via a single
/// typedef line:
///
///     typedef _Palette = NorthstarStudio;   // ← swap this line, re-run, done
///
/// Because the slots are `static const`, the whole chain stays const —
/// no call site anywhere in the app changes when the palette does.
///
/// To add a palette from a new marketing mockup
/// (see flutter_app/marketing/color-palette/*.jpg):
///   1. Copy an existing class below, rename it, fill in the hex values.
///   2. Point the typedef in tokens.dart at it.
///   3. `flutter run` — the entire app re-skins.
/// Keep the slot names identical; add new slots to ALL palettes at once.
///
/// PALETTE CONTRACT (what each slot means):
///   ink / inkSoft          — primary text & headings / secondary dark text
///   canvas / canvasDim     — app background / subtle section background
///   surface                — cards and sheets
///   primary(+Deep,+Soft)   — THE action color: buttons, links, active states
///   secondary              — secondary call-to-actions and accents
///   success / info /       — semantic learning states, each with a Soft
///   mastery / warning /      tinted background variant
///   danger(+Soft)          — invalid, errors, destructive
///   muted / mutedDim       — tertiary text, captions, disabled

/// ACTIVE — "Northstar Studio", a calm premium black/gold learning palette.
/// Gold carries action and mastery; green and coral remain semantic feedback
/// colors rather than brand accents.
abstract final class NorthstarStudio {
  static const ink = Color(0xFF17130D);
  static const inkSoft = Color(0xFF746F65);
  static const canvas = Color(0xFFFBFAF7);
  static const canvasDim = Color(0xFFF4F0E6);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFFF2B84B);
  static const primaryDeep = Color(0xFFB97823);
  static const primarySoft = Color(0xFFFFF1CC);
  static const secondary = Color(0xFFB97823);
  static const success = Color(0xFF2D8A5B);
  static const successSoft = Color(0xFFE8F4ED);
  static const info = Color(0xFFB97823);
  static const infoSoft = Color(0xFFFFF1CC);
  static const mastery = Color(0xFFB97823);
  static const masterySoft = Color(0xFFFBF2E4);
  static const warning = Color(0xFFB97823);
  static const warningSoft = Color(0xFFFBF2E4);
  static const danger = Color(0xFFC95757);
  static const dangerSoft = Color(0xFFFBECEC);
  static const muted = Color(0xFF746F65);
  static const mutedDim = Color(0xFF746F65);
}

/// Previous identity slot retained for palette API compatibility. It now
/// follows the same neutral/gold contract as the active appearance.
abstract final class ProSystemAzure {
  static const ink = Color(0xFF17130D);
  static const inkSoft = Color(0xFF746F65);
  static const canvas = Color(0xFFFBFAF7);
  static const canvasDim = Color(0xFFF4F0E6);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFFF2B84B);
  static const primaryDeep = Color(0xFFB97823);
  static const primarySoft = Color(0xFFFFF1CC);
  static const secondary = Color(0xFFB97823);
  static const success = Color(0xFF2D8A5B);
  static const successSoft = Color(0xFFE7F6EC);
  static const info = Color(0xFFB97823);
  static const infoSoft = Color(0xFFFFF1CC);
  static const mastery = Color(0xFFB97823);
  static const masterySoft = Color(0xFFFFF1CC);
  static const warning = Color(0xFFB97823);
  static const warningSoft = Color(0xFFFFF1CC);
  static const danger = Color(0xFFC95757);
  static const dangerSoft = Color(0xFFFBE9EB);
  static const muted = Color(0xFF746F65);
  static const mutedDim = Color(0xFF746F65);
}

/// Previous identity slot retained for compatibility with old imports.
abstract final class PasseportHeritage {
  static const ink = Color(0xFF17130D);
  static const inkSoft = Color(0xFF746F65);
  static const canvas = Color(0xFFFBFAF7);
  static const canvasDim = Color(0xFFF4F0E6);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFFF2B84B);
  static const primaryDeep = Color(0xFFB97823);
  static const primarySoft = Color(0xFFFFF1CC);
  static const secondary = Color(0xFFB97823);
  static const success = Color(0xFF2D8A5B);
  static const successSoft = Color(0xFFE5F4EF);
  static const info = Color(0xFFB97823);
  static const infoSoft = Color(0xFFFFF1CC);
  static const mastery = Color(0xFFB97823);
  static const masterySoft = Color(0xFFFFF1CC);
  static const warning = Color(0xFFB97823);
  static const warningSoft = Color(0xFFFFF1CC);
  static const danger = Color(0xFFC95757);
  static const dangerSoft = Color(0xFFFBEAEC);
  static const muted = Color(0xFF746F65);
  static const mutedDim = Color(0xFF746F65);
}
