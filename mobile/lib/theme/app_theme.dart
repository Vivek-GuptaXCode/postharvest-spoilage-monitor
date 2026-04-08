import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: const Color(0xFF00E5A0),
      secondary: const Color(0xFF00B4D8),
      tertiary: const Color(0xFFFFB703),
      surface: const Color(0xFF0D1117),
      surfaceContainerHighest: const Color(0xFF161B22),
      error: const Color(0xFFFF4757),
      onPrimary: Colors.black,
      onSurface: Colors.white,
      onSurfaceVariant: const Color(0xFF8B949E),
    ),
    scaffoldBackgroundColor: const Color(0xFF0A0E1A),
    cardTheme: CardThemeData(
      color: const Color(0xFF0D1117),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF21262D), width: 1),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0D1117),
      indicatorColor: const Color(0xFF00E5A0).withAlpha(30),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.spaceGrotesk(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF00E5A0),
          );
        }
        return GoogleFonts.spaceGrotesk(
          fontSize: 11,
          color: const Color(0xFF8B949E),
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFF00E5A0), size: 22);
        }
        return const IconThemeData(color: Color(0xFF8B949E), size: 22);
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF161B22),
      selectedColor: const Color(0xFF00E5A0).withAlpha(30),
      labelStyle: GoogleFonts.spaceGrotesk(fontSize: 12),
      side: const BorderSide(color: Color(0xFF21262D)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.dark().textTheme).copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(
        fontSize: 57, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -2,
      ),
      headlineLarge: GoogleFonts.spaceGrotesk(
        fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -1,
      ),
      headlineMedium: GoogleFonts.spaceGrotesk(
        fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.spaceGrotesk(
        fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white,
      ),
      titleMedium: GoogleFonts.spaceGrotesk(
        fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white,
      ),
      bodyLarge: GoogleFonts.dmMono(fontSize: 16, color: Colors.white),
      bodyMedium: GoogleFonts.spaceGrotesk(fontSize: 14, color: const Color(0xFFB0B8C4)),
      bodySmall: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF8B949E)),
      labelLarge: GoogleFonts.spaceGrotesk(
        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white,
      ),
      labelSmall: GoogleFonts.dmMono(fontSize: 10, color: const Color(0xFF8B949E), letterSpacing: 0.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF161B22),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF21262D)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF21262D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF00E5A0), width: 1.5),
      ),
      labelStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF8B949E)),
      hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF8B949E)),
      prefixIconColor: const Color(0xFF8B949E),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(const Color(0xFF00E5A0)),
        foregroundColor: WidgetStateProperty.all(Colors.black),
        textStyle: WidgetStateProperty.all(
          GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF21262D),
      thickness: 1,
    ),
  );
}

// ─── Design Tokens ─────────────────────────────────────────────────────────

class AppColors {
  static const background = Color(0xFF0A0E1A);
  static const surface = Color(0xFF0D1117);
  static const surfaceElevated = Color(0xFF161B22);
  static const border = Color(0xFF21262D);

  static const neonGreen = Color(0xFF00E5A0);
  static const neonBlue = Color(0xFF00B4D8);
  static const neonAmber = Color(0xFFFFB703);
  static const neonRed = Color(0xFFFF4757);
  static const neonPurple = Color(0xFFBD5FFF);

  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFB0B8C4);
  static const textMuted = Color(0xFF8B949E);

  // Gradients
  static const gradientGreen = LinearGradient(
    colors: [Color(0xFF00E5A0), Color(0xFF00B4D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientRed = LinearGradient(
    colors: [Color(0xFFFF4757), Color(0xFFFF6B9D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientAmber = LinearGradient(
    colors: [Color(0xFFFFB703), Color(0xFFFB8500)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientPurple = LinearGradient(
    colors: [Color(0xFFBD5FFF), Color(0xFF7B2FBE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const gradientSurface = LinearGradient(
    colors: [Color(0xFF161B22), Color(0xFF0D1117)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
