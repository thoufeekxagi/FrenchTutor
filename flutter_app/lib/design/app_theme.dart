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
      scaffoldBackgroundColor: DesignTokens.parchment,
      colorScheme: const ColorScheme.light(
        primary: DesignTokens.maroon,
        secondary: DesignTokens.brass,
        surface: DesignTokens.card,
        onPrimary: DesignTokens.parchment,
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
            for (final p in TargetPlatform.values) p: const FadeUpwardsPageTransitionsBuilder(),
          },
        },
      ),
      // No ink ripple anywhere — one ParleSprint vibe on every platform; taps
      // acknowledge with a quiet highlight fade, never a spreading splash.
      splashFactory: NoSplash.splashFactory,
      highlightColor: DesignTokens.ink.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        backgroundColor: DesignTokens.parchment,
        foregroundColor: DesignTokens.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: isCupertino,
        titleTextStyle: DesignTokens.display(20),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: DesignTokens.maroon,
        unselectedLabelColor: DesignTokens.slate,
        indicatorColor: DesignTokens.maroon,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DesignTokens.card,
        selectedItemColor: DesignTokens.maroon,
        unselectedItemColor: DesignTokens.slate,
        elevation: 8,
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
