import 'package:flutter/material.dart';

class PizzaColors {
  const PizzaColors._();

  static const dough = Color(0xFFFFF3DD);
  static const crust = Color(0xFFE7A450);
  static const crustDeep = Color(0xFF9A5424);
  static const tomato = Color(0xFFE65336);
  static const tomatoDeep = Color(0xFFA93426);
  static const basil = Color(0xFF637A3A);
  static const basilDeep = Color(0xFF354A2A);
  static const ink = Color(0xFF231A14);
  static const muted = Color(0xFF78665C);
  static const paper = Color(0xFFFFFCF7);
  static const paperAlt = Color(0xFFF4E8DC);
  static const blueCheese = Color(0xFF315A7B);
  static const line = Color(0xFFE6D2BF);
}

ThemeData buildPizzaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PizzaColors.tomato,
    brightness: Brightness.light,
    primary: PizzaColors.tomato,
    secondary: PizzaColors.basil,
    tertiary: PizzaColors.blueCheese,
    surface: PizzaColors.paper,
    error: PizzaColors.tomatoDeep,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: PizzaColors.dough,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: PizzaColors.ink,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1.0,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        color: PizzaColors.ink,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.08,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        color: PizzaColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: PizzaColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: PizzaColors.ink,
        fontSize: 16,
        height: 1.45,
        letterSpacing: 0,
      ),
      bodyMedium: TextStyle(
        color: PizzaColors.ink,
        fontSize: 14,
        height: 1.35,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        color: PizzaColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PizzaColors.paper,
      foregroundColor: PizzaColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: PizzaColors.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PizzaColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PizzaColors.tomato,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PizzaColors.ink,
        side: const BorderSide(color: PizzaColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(44, 44),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: PizzaColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: PizzaColors.tomato,
      inactiveTrackColor: PizzaColors.line,
      thumbColor: PizzaColors.tomato,
      overlayColor: PizzaColors.tomato.withValues(alpha: 0.12),
      trackHeight: 6,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PizzaColors.paper,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PizzaColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PizzaColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PizzaColors.tomato, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: PizzaColors.line,
      thickness: 1,
      space: 1,
    ),
  );
}
