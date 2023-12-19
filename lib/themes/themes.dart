import 'package:flutter/material.dart';

final ThemeData themeLight = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.purple,
      primary: Colors.red,
      // ···
      brightness: Brightness.light,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(
        shape: MaterialStateProperty.resolveWith<OutlinedBorder>((_) {
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    }))));

final ThemeData themeDark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      primary: Colors.purple,
      seedColor: Colors.purpleAccent,
      // ···
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          
            backgroundColor: MaterialStateProperty.resolveWith<Color?>(
      (Set<MaterialState> states) {
        return themeDark.primaryColor.withOpacity(0.7);
      },
    ), shape: MaterialStateProperty.resolveWith<OutlinedBorder>((_) {
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    }))));
