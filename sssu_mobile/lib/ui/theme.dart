import 'package:flutter/material.dart';

/// Identité visuelle commune (bleu, blanc, vert), boutons larges pour le terrain.
const bleuSssu = Color(0xFF0B4F8A);
const vertSssu = Color(0xFF1E8E4E);

ThemeData themeSssu() {
  final couleurs = ColorScheme.fromSeed(seedColor: bleuSssu, primary: bleuSssu, secondary: vertSssu);
  return ThemeData(
    colorScheme: couleurs,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(backgroundColor: bleuSssu, foregroundColor: Colors.white),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 17)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
