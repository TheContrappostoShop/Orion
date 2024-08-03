/*
* Orion - Themes
* Copyright (C) 2024 TheContrappostoShop
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';

final ThemeData themeLight = ThemeData(
  fontFamily: 'AtkinsonHyperlegible',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff6750a4),
    brightness: Brightness.light,
  ),
  appBarTheme: const AppBarTheme(
    titleTextStyle: TextStyle(
      fontFamily: 'AtkinsonHyperlegible',
      fontSize: 30,
      color: Colors.black,
    ),
    centerTitle: true,
    toolbarHeight: 65,
    iconTheme: IconThemeData(size: 30),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontFamily: 'AtkinsonHyperlegible', fontSize: 20),
    titleLarge: TextStyle(
        fontFamily: 'AtkinsonHyperlegible', fontSize: 20), // For AppBar title
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    selectedLabelStyle:
        TextStyle(fontFamily: 'AtkinsonHyperlegible', fontSize: 18),
    unselectedLabelStyle:
        TextStyle(fontFamily: 'AtkinsonHyperlegible', fontSize: 18),
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
  fontFamily: 'AtkinsonHyperlegible',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff6750a4),
    brightness: Brightness.dark,
  ),
  appBarTheme: const AppBarTheme(
    titleTextStyle: TextStyle(
      fontFamily: 'AtkinsonHyperlegible',
      fontSize: 30,
      color: Colors.white,
    ),
    centerTitle: true,
    toolbarHeight: 65,
    iconTheme: IconThemeData(size: 30),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontFamily: 'AtkinsonHyperlegible', fontSize: 20),
    titleLarge: TextStyle(
        fontFamily: 'AtkinsonHyperlegible', fontSize: 20), // For AppBar title
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    selectedLabelStyle:
        TextStyle(fontFamily: 'AtkinsonHyperlegible', fontSize: 18),
    unselectedLabelStyle:
        TextStyle(fontFamily: 'AtkinsonHyperlegible', fontSize: 18),
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
