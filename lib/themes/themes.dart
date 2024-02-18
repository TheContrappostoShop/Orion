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

extension ColorBrightness on Color {
  Color withBrightness(double factor) {
    assert(factor >= 0);

    final hsl = HSLColor.fromColor(this);
    final increasedLightness = (hsl.lightness * factor).clamp(0.0, 1.0);

    return hsl.withLightness(increasedLightness).toColor();
  }
}
