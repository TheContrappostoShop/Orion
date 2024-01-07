import 'package:flutter/material.dart';

final ThemeData themeLight = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff6750a4),
    brightness: Brightness.light,
  ),
  useMaterial3: true,
);

final ThemeData themeDark = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff6750a4),
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);
