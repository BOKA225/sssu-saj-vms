import 'package:flutter/material.dart';

/// Identité visuelle commune aux deux versions (bleu, blanc, vert).
const bleuSssu = Color(0xFF0B4F8A);
const vertSssu = Color(0xFF1E8E4E);

ThemeData themeSssu() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: bleuSssu, primary: bleuSssu, secondary: vertSssu),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(backgroundColor: bleuSssu, foregroundColor: Colors.white),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
