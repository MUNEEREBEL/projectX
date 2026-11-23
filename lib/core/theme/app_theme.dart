import 'package:flutter/material.dart';

class AppTheme {
  // Deep space obsidian glass palette
  static const Color darkBg = Color(0xFF090D16);
  static const Color darkCard = Color(0xFF131824);
  static const Color darkCardTranslucent = Color(0x99131824);
  static const Color darkBorder = Color(0xFF222938);
  static const Color darkBorderFocus = Color(0xFF38BDF8);

  // Glass highlights & borders
  static final Color glassFill = Colors.white.withValues(alpha: 0.06);
  static final Color glassBorder = Colors.white.withValues(alpha: 0.12);
  static final Color glassBorderHighlight = Colors.white.withValues(alpha: 0.22);

  // Cosmic Background Gradient
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF070A10),
      Color(0xFF0B101B),
      Color(0xFF0F172A),
      Color(0xFF070A10),
    ],
    stops: [0.0, 0.35, 0.75, 1.0],
  );

  // Executive Vibrant Accents
  static const Color primaryColor = Color(0xFF2563EB); // Electric Royal Blue
  static const Color primaryGlow = Color(0xFF3B82F6);
  static const Color accentColor = Color(0xFF38BDF8); // Cyan Glow
  static const Color successColor = Color(0xFF10B981); // Emerald Glow
  static const Color warningColor = Color(0xFFF59E0B); // Amber Glow
  static const Color dangerColor = Color(0xFFEF4444); // Crimson Glow
  static const Color violetColor = Color(0xFF8B5CF6);

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static final List<Color> avatarColors = [
    const Color(0xFF3B82F6), // Sapphire
    const Color(0xFF10B981), // Emerald
    const Color(0xFF8B5CF6), // Violet
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEC4899), // Rose
    const Color(0xFF06B6D4), // Cyan
  ];

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: darkCard,
        error: dangerColor,
        onSurface: textPrimary,
      ),
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        color: darkCardTranslucent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 20),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: primaryColor.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: -0.2,
            );
          }
          return const TextStyle(color: textMuted, fontSize: 12, letterSpacing: -0.2);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorderFocus, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primaryColor.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: glassBorder),
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          foregroundColor: textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        selectedColor: primaryColor.withValues(alpha: 0.25),
        side: BorderSide(color: glassBorder, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}
