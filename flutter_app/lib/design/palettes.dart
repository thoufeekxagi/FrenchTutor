import 'package:flutter/widgets.dart';

/// Layer 0 of the design wiring: PALETTES — plug-and-play color skins.
///
/// Every palette is an `abstract final class` exposing the SAME static const
/// slots (the palette contract below). `tokens.dart` selects one via a single
/// typedef line:
///
///     typedef _Palette = ProSystemAzure;   // ← swap this line, re-run, done
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

/// ACTIVE — "Pro System Azure" (marketing/color-palette/pro_system_azure.jpg).
/// Professional azure-blue system: Dribbble-quality spec, high-trust neutrals.
abstract final class ProSystemAzure {
  static const ink = Color(0xFF1C1E21); // Dark Navy — text, headings
  static const inkSoft = Color(0xFF33383F);
  static const canvas = Color(0xFFF8F9FA); // Off-White Base
  static const canvasDim = Color(0xFFEEF0F2);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFF007BFF); // Primary Azure Blue
  static const primaryDeep = Color(0xFF0063CE);
  static const primarySoft = Color(0xFFE5F1FF);
  static const secondary = Color(0xFF17A2B8); // Vibrant Teal
  static const success = Color(0xFF28A745); // Success Emerald
  static const successSoft = Color(0xFFE7F6EC);
  static const info = Color(0xFF17A2B8); // teal doubles as info
  static const infoSoft = Color(0xFFE4F5F8);
  static const mastery = Color(0xFFFFC107); // Amber — demonstrated mastery
  static const masterySoft = Color(0xFFFFF6DC);
  static const warning = Color(0xFFFFC107); // Warning Amber
  static const warningSoft = Color(0xFFFFF6DC);
  static const danger = Color(0xFFDC3545); // Error Crimson
  static const dangerSoft = Color(0xFFFBE9EB);
  static const muted = Color(0xFFA0A0A0); // Surface Gray — captions, disabled
  static const mutedDim = Color(0xFF707070); // Dark Gray
}

/// Previous identity — warm paper + navy ink + bordeaux + gold ("Passeport
/// heritage"). Kept so a one-line typedef flip can restore it for comparison.
abstract final class PasseportHeritage {
  static const ink = Color(0xFF182338);
  static const inkSoft = Color(0xFF293751);
  static const canvas = Color(0xFFF7F7F4);
  static const canvasDim = Color(0xFFEEF1F5);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFFD1495B);
  static const primaryDeep = Color(0xFFB53648);
  static const primarySoft = Color(0xFFFBEAEC);
  static const secondary = Color(0xFF5A7FC3);
  static const success = Color(0xFF3D9E83);
  static const successSoft = Color(0xFFE5F4EF);
  static const info = Color(0xFF5A7FC3);
  static const infoSoft = Color(0xFFEAF0FA);
  static const mastery = Color(0xFFD5A13D);
  static const masterySoft = Color(0xFFFAF2DF);
  static const warning = Color(0xFFD5A13D);
  static const warningSoft = Color(0xFFFAF2DF);
  static const danger = Color(0xFFB53648);
  static const dangerSoft = Color(0xFFFBEAEC);
  static const muted = Color(0xFF9AA5B5);
  static const mutedDim = Color(0xFF667085);
}
