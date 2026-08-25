import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'appearance_colors.dart';
import '../services/app_appearance_settings.dart';
import 'tokens.dart';

/// Layer 2 of the design wiring: maps DesignTokens onto Flutter themes and
/// owns every per-platform decision that lives at the theme level —
/// page transitions, scroll physics, ripple suppression. Screens must never
/// check `Platform.isIOS` themselves; they inherit this.
abstract final class AppTheme {
  static bool get isCupertino =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static ThemeData themeData({bool? darkMode}) {
    final dark = darkMode ?? AppAppearanceSettings.shared.darkMode;
    final canvas = dark
        ? AppearanceColors.darkCanvas
        : AppearanceColors.lightCanvas;
    final surface = dark
        ? AppearanceColors.darkSurface
        : AppearanceColors.lightSurface;
    final raised = dark
        ? AppearanceColors.darkRaised
        : AppearanceColors.lightRaised;
    final ink = dark ? AppearanceColors.darkText : AppearanceColors.lightText;
    final muted = dark
        ? AppearanceColors.darkMuted
        : AppearanceColors.lightMuted;
    final hairline = dark
        ? AppearanceColors.darkHairline
        : AppearanceColors.lightHairline;
    final accent = dark ? AppearanceColors.gold : AppearanceColors.goldDeep;
    final goldSoft = dark
        ? AppearanceColors.goldSoftDark
        : AppearanceColors.goldSoftLight;

    return ThemeData(
      useMaterial3: true,
      // `parchment` is an alias of `canvas`, so this is already the neutral
      // canvas the web reference design is built on — no per-platform branch
      // needed here. Screens that set their own background use the same token.
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: Colors.black,
        secondary: AppearanceColors.goldDeep,
        onSecondary: Colors.black,
        surface: surface,
        onSurface: ink,
        error: AppearanceColors.danger,
        onError: Colors.white,
      ),
      // Keep the neutral container roles in the same black/gold or
      // white/gold family instead of inheriting Material's blue defaults.
      extensions: const <ThemeExtension<dynamic>>[],
      textTheme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
      ).textTheme.apply(bodyColor: ink, displayColor: ink),
      canvasColor: canvas,
      cardColor: surface,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.28 : 0.08),
      primaryColor: accent,
      hintColor: muted,
      unselectedWidgetColor: muted,
      dialogBackgroundColor: surface,
      dividerColor: hairline,
      applyElevationOverlayColor: dark,
      // Material's generated defaults are intentionally overridden below.
      // The explicit roles are what keep legacy Material widgets on-brand.
      colorSchemeSeed: null,
      // `onPrimary` is black in both appearances because gold is the action
      // surface in both appearances.
      // ignore: deprecated_member_use
      primarySwatch: null,
      // iOS: native push/pop with edge-swipe back. Android: platform default.
      // Web: fade (no horizontal slabs sliding on a desktop browser).
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: const ZoomPageTransitionsBuilder(),
          if (kIsWeb) ...{
            for (final p in TargetPlatform.values)
              p: const FadeUpwardsPageTransitionsBuilder(),
          },
        },
      ),
      // No ink ripple anywhere — one ParleSprint vibe on every platform; taps
      // acknowledge with a quiet highlight fade, never a spreading splash.
      splashFactory: NoSplash.splashFactory,
      highlightColor: ink.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        // On web an app bar is a toolbar: white, left-aligned title, separated
        // from the content by a hairline rather than by colour. Mobile keeps the
        // parchment iOS-style bar.
        backgroundColor: kIsWeb ? surface : canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: isCupertino,
        titleTextStyle: DesignTokens.display(
          kIsWeb ? 17 : 20,
        ).copyWith(color: ink),
        shape: kIsWeb ? Border(bottom: BorderSide(color: hairline)) : null,
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 56),
          backgroundColor: accent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(
            15,
            weight: FontWeight.w700,
          ).copyWith(color: Colors.black),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 56),
          backgroundColor: accent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(
            15,
            weight: FontWeight.w700,
          ).copyWith(color: Colors.black),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: AppearanceColors.goldDeep,
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(
            14,
            weight: FontWeight.w700,
          ).copyWith(color: AppearanceColors.goldDeep),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppearanceColors.goldDeep,
          textStyle: DesignTokens.body(
            14,
            weight: FontWeight.w700,
          ).copyWith(color: AppearanceColors.goldDeep),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : raised,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: DesignTokens.primary,
        textColor: ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: goldSoft,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.1),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: raised,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppearanceColors.goldDeep,
        unselectedLabelColor: muted,
        indicatorColor: accent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: muted,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          side: BorderSide(color: hairline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: goldSoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) =>
              DesignTokens.body(
                11,
                weight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              ).copyWith(
                color: states.contains(WidgetState.selected)
                    ? AppearanceColors.goldDeep
                    : muted,
              ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppearanceColors.goldDeep
                : muted,
            size: 23,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: goldSoft,
        side: BorderSide(color: hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        ),
        labelStyle: DesignTokens.body(
          13,
          weight: FontWeight.w600,
        ).copyWith(color: ink),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: DesignTokens.body(14).copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        ),
      ),
    );
  }
}

/// iOS-style bouncing scroll everywhere (clamping physics is the single most
/// felt "Android port" tell on iOS; bounce is also fine on Android/web here).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
