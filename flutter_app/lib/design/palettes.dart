import 'package:flutter/widgets.dart';

/// Layer 0 of the design wiring: PALETTES — plug-and-play color skins.
///
/// Every palette is an `abstract final class` exposing the SAME static const
/// slots (the palette contract below). `tokens.dart` selects one via a single
/// typedef line:
///
///     typedef _Palette = ConfidentMomentum;   // ← swap this line, re-run, done
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
abstract final class ConfidentMomentum {
  static const ink = Color(0xFF172033); // Dark Navy — text, headings
  static const inkSoft = Color(0xFF35415A);
  static const canvas = Color(0xFFF6F8FC);
  static const canvasDim = Color(0xFFEDF1F8);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFF2474FF); // Primary Azure Blue
  static const primaryDeep = Color(0xFF1658D7);
  static const primarySoft = Color(0xFFE8F0FF);
  static const secondary = Color(0xFF18A6A1); // Vibrant Teal
  static const success = Color(0xFF31B36B); // Success Emerald
  static const successSoft = Color(0xFFE7F7EE);
  static const info = Color(0xFF18A6A1); // teal doubles as info
  static const infoSoft = Color(0xFFE4F7F6);
  static const mastery = Color(0xFFFFB547); // Amber — demonstrated mastery
  static const masterySoft = Color(0xFFFFF3DE);
  static const warning = Color(0xFFFFB547); // Warning Amber
  static const warningSoft = Color(0xFFFFF3DE);
  static const danger = Color(0xFFFF6368); // Error Crimson
  static const dangerSoft = Color(0xFFFFE9EA);
  static const muted = Color(0xFF94A0B8); // Surface Gray — captions, disabled
  static const mutedDim = Color(0xFF657089); // Dark Gray
}

/// Previous identity — warm paper + navy ink + bordeaux + gold ("ParleSprint
/// heritage"). Kept so a one-line typedef flip can restore it for comparison.
