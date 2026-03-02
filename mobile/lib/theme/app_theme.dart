import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: const Color(0xFF4CAF50), // Green — primary
      secondary: const Color(0xFF81C784), // Light green
      surface: const Color(0xFF1E1E2E), // Dark card background
      error: const Color(0xFFE53935), // Red — critical
      onPrimary: Colors.white,
      onSurface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E2E),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF1E1E2E),
      elevation: 0,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  );
}
