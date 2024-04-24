import 'package:flutter/material.dart';

final ThemeData themeLight = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff6750a4),
    brightness: Brightness.light,
  ),
  appBarTheme: const AppBarTheme(
    titleTextStyle: TextStyle(fontSize: 26, color: Colors.black),
    centerTitle: true,
    toolbarHeight: 65,
    iconTheme: IconThemeData(size: 30),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 20),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    selectedLabelStyle: TextStyle(fontSize: 16),
    unselectedLabelStyle: TextStyle(fontSize: 16),
    selectedIconTheme: IconThemeData(size: 30),
    unselectedIconTheme: IconThemeData(size: 30),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      minimumSize: MaterialStateProperty.all<Size>(
          const Size(88, 50)), // Set the width and height
    ),
  ),
  useMaterial3: true,
);

final ThemeData themeDark = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff6750a4),
    brightness: Brightness.dark,
  ),
  appBarTheme: const AppBarTheme(
    titleTextStyle: TextStyle(fontSize: 26, color: Colors.white),
    centerTitle: true,
    toolbarHeight: 65,
    iconTheme: IconThemeData(size: 30),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 20),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    selectedLabelStyle: TextStyle(fontSize: 16),
    unselectedLabelStyle: TextStyle(fontSize: 16),
    selectedIconTheme: IconThemeData(size: 30),
    unselectedIconTheme: IconThemeData(size: 30),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      minimumSize: MaterialStateProperty.all<Size>(
          const Size(88, 50)), // Set the width and height
    ),
  ),
  useMaterial3: true,
);

extension ColorBrightness on Color {
  Color withBrightness(double factor) {
    assert(factor >= 0);

    final hsl = HSLColor.fromColor(this);
    final increasedLightness = (hsl.lightness * factor).clamp(0.0, 1.0);

    return hsl.withLightness(increasedLightness).toColor();
  }
}
