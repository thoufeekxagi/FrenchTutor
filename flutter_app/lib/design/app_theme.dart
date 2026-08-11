import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  static ThemeData themeData() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: DesignTokens.canvas,
      colorScheme: const ColorScheme.light(
        primary: DesignTokens.primary,
        secondary: DesignTokens.secondary,
        surface: DesignTokens.surface,
        onPrimary: Colors.white,
        onSecondary: DesignTokens.ink,
        onSurface: DesignTokens.ink,
      ),
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
      highlightColor: DesignTokens.ink.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        backgroundColor: DesignTokens.canvas,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: isCupertino,
        titleTextStyle: DesignTokens.display(20),
      ),
      dividerTheme: DividerThemeData(
        color: DesignTokens.hairline,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DesignTokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          borderSide: BorderSide(color: DesignTokens.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          borderSide: BorderSide(color: DesignTokens.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          borderSide: const BorderSide(color: DesignTokens.info, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(44, 52),
          backgroundColor: DesignTokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(15, weight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 56),
          backgroundColor: DesignTokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(15, weight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: DesignTokens.primary,
          side: BorderSide(color: DesignTokens.hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
          ),
          textStyle: DesignTokens.body(14, weight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: DesignTokens.primary,
          textStyle: DesignTokens.body(14, weight: FontWeight.w700),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DesignTokens.primary
              : DesignTokens.canvasDim,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: DesignTokens.primary,
        textColor: DesignTokens.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: DesignTokens.primary,
        inactiveTrackColor: DesignTokens.primarySoft,
        thumbColor: DesignTokens.primary,
        overlayColor: DesignTokens.primary.withValues(alpha: 0.1),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DesignTokens.primary,
        linearTrackColor: DesignTokens.canvasDim,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: DesignTokens.primary,
        unselectedLabelColor: DesignTokens.muted,
        indicatorColor: DesignTokens.primary,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DesignTokens.surface,
        selectedItemColor: DesignTokens.primary,
        unselectedItemColor: DesignTokens.mutedDim,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: DesignTokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          side: BorderSide(color: DesignTokens.hairline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: DesignTokens.surface,
        indicatorColor: DesignTokens.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) =>
              DesignTokens.body(
                11,
                weight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              ).copyWith(
                color: states.contains(WidgetState.selected)
                    ? DesignTokens.primary
                    : DesignTokens.mutedDim,
              ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? DesignTokens.primary
                : DesignTokens.mutedDim,
            size: 23,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: DesignTokens.surface,
        selectedColor: DesignTokens.primarySoft,
        side: BorderSide(color: DesignTokens.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        ),
        labelStyle: DesignTokens.body(13, weight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: DesignTokens.surface,
        modalBackgroundColor: DesignTokens.surface,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: DesignTokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: DesignTokens.ink,
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
