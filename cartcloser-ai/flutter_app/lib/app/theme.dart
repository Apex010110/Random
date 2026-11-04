import 'package:flutter/material.dart';

/// Visual identity shared with the pitch deck: midnight navy, cyan + emerald accents, restrained coral.
class CC {
  static const ink = Color(0xFF070B1B);
  static const navy = Color(0xFF0D1631);
  static const navy2 = Color(0xFF141E3D);
  static const line = Color(0xFF243055);
  static const cyan = Color(0xFF3CE7E2);
  static const green = Color(0xFF25D366);
  static const coral = Color(0xFFFF6B70);
  static const amber = Color(0xFFFFC65C);
  static const white = Color(0xFFF5F7FB);
  static const muted = Color(0xFFA9B3CC);
  static const dim = Color(0xFF6E7A99);
  // simulated chat palette (own colours, not WhatsApp's brand assets)
  static const chatBg = Color(0xFF0B141A);
  static const chatIn = Color(0xFF1F2C34);
  static const chatOut = Color(0xFF005C4B);
  static const chatHead = Color(0xFF1A252D);

  static const fonts = 'Inter';
  static const fallback = ['NotoNaskhArabic'];
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: CC.cyan,
    brightness: Brightness.dark,
    surface: CC.navy,
    primary: CC.cyan,
    secondary: CC.green,
    error: CC.coral,
  ).copyWith(onPrimary: CC.ink, onSecondary: CC.ink, surfaceContainerHighest: CC.navy2, outline: CC.line);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: CC.fonts, fontFamilyFallback: CC.fallback);
  return base.copyWith(
    scaffoldBackgroundColor: CC.ink,
    canvasColor: CC.ink,
    textTheme: base.textTheme.apply(bodyColor: CC.white, displayColor: CC.white, fontFamilyFallback: CC.fallback),
    appBarTheme: const AppBarTheme(backgroundColor: CC.ink, surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: CC.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: CC.line)),
    ),
    dividerTheme: const DividerThemeData(color: CC.line, space: 1),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: CC.navy2,
      side: const BorderSide(color: CC.line),
      labelStyle: const TextStyle(color: CC.white, fontSize: 13),
      shape: const StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: CC.white,
        side: const BorderSide(color: CC.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CC.navy2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CC.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CC.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: CC.cyan, width: 1.5)),
      labelStyle: const TextStyle(color: CC.muted),
      hintStyle: const TextStyle(color: CC.dim),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: CC.navy,
      indicatorColor: CC.cyan.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: CC.ink,
      indicatorColor: CC.cyan.withValues(alpha: 0.18),
      selectedIconTheme: const IconThemeData(color: CC.cyan),
      unselectedIconTheme: const IconThemeData(color: CC.muted),
      selectedLabelTextStyle: const TextStyle(color: CC.cyan, fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelTextStyle: const TextStyle(color: CC.muted, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: CC.navy2,
      contentTextStyle: const TextStyle(color: CC.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: CC.line)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? CC.ink : CC.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? CC.green : CC.navy2),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? CC.green : Colors.transparent),
      checkColor: WidgetStateProperty.all(CC.ink),
      side: const BorderSide(color: CC.muted, width: 1.5),
    ),
  );
}
