import 'package:flutter/material.dart';

class AppTheme {
  // Luminous white & executive glass palette
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardTranslucent = Color(0xF2FFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderFocus = Color(0xFF2563EB);

  // Backwards compatibility aliases for dark theme callers
  static const Color darkCard = Color(0xFFFFFFFF);
  static const Color darkBorder = Color(0xFFE2E8F0);
  static const Color darkBackground = Color(0xFFF8FAFC);
  static const Color darkCardTranslucent = Color(0xF2FFFFFF);

  // Glass highlights & borders
  static final Color glassFill = Colors.white.withValues(alpha: 0.85);
  static const Color glassBorder = Color(0xFFE2E8F0);
  static const Color glassBorderHighlight = Color(0xFFCBD5E1);

  // Executive Light Background Gradient
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF8FAFC),
      Color(0xFFF1F5F9),
      Color(0xFFE2E8F0),
      Color(0xFFF8FAFC),
    ],
    stops: [0.0, 0.35, 0.75, 1.0],
  );

  // Executive Vibrant Accents
  static const Color primaryColor = Color(0xFF2563EB); // Electric Royal Blue
  static const Color primaryGlow = Color(0xFF3B82F6);
  static const Color accentColor = Color(0xFF0284C7); // Sky Cyan
  static const Color successColor = Color(0xFF059669); // Emerald
  static const Color warningColor = Color(0xFFD97706); // Amber
  static const Color dangerColor = Color(0xFFDC2626); // Crimson
  static const Color violetColor = Color(0xFF7C3AED);

  // High-contrast Typography for crisp white canvas
  static const Color textPrimary = Color(0xFF0F172A); // Rich dark slate
  static const Color textSecondary = Color(0xFF475569); // Medium slate
  static const Color textMuted = Color(0xFF64748B); // Muted slate

  static final List<Color> avatarColors = [
    const Color(0xFF2563EB), // Sapphire
    const Color(0xFF059669), // Emerald
    const Color(0xFF7C3AED), // Violet
    const Color(0xFFD97706), // Amber
    const Color(0xFFDB2777), // Rose
    const Color(0xFF0891B2), // Cyan
  ];

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: accentColor,
        surface: lightCard,
        error: dangerColor,
        onSurface: textPrimary,
      ),
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        indicatorColor: primaryColor.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: primaryColor,
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
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primaryColor.withValues(alpha: 0.25),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: lightBorder),
          backgroundColor: Colors.white,
          foregroundColor: textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primaryColor.withValues(alpha: 0.12),
        side: const BorderSide(color: lightBorder, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  // Backwards compatibility getter
  static ThemeData get darkTheme => lightTheme;
}
