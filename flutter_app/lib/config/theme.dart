import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class Passeport {
  // Palette — pastel take on the French flag (bleu / blanc / rouge)
  static const ink = Color(0xFF1B2A4A);
  static const inkSoft = Color(0xFF25375C);
  static const parchment = Color(0xFFFAF9F6);
  static const parchmentDim = Color(0xFFEDF1F7);
  static const card = Color(0xFFFFFFFF);
  static const maroon = Color(0xFFC8433E);
  static const maroonDeep = Color(0xFFA83229);
  static const brass = Color(0xFF6B8FC4);
  static const slate = Color(0xFF95A0B2);
  static const slateDim = Color(0xFF606C80);
  static const text = Color(0xFF1B2A4A);
  static final hairline = ink.withValues(alpha: 0.12);
  static final hairlineLight = parchment.withValues(alpha: 0.16);

  static TextStyle display(double size, {FontWeight weight = FontWeight.w500}) {
    return GoogleFonts.playfairDisplay(fontSize: size, fontWeight: weight, color: ink);
  }

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400}) {
    return TextStyle(fontSize: size, fontWeight: weight, color: ink);
  }

  static TextStyle mono(double size, {FontWeight weight = FontWeight.w400}) {
    return GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: ink);
  }

  static ThemeData themeData() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: parchment,
      colorScheme: const ColorScheme.light(
        primary: maroon,
        secondary: brass,
        surface: card,
        onPrimary: parchment,
        onSecondary: ink,
        onSurface: ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: parchment,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: display(20),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: maroon,
        unselectedLabelColor: slate,
        indicatorColor: maroon,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: maroon,
        unselectedItemColor: slate,
        elevation: 8,
      ),
    );
  }
}
