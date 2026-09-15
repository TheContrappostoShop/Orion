/*
* Orion - Screen Type Visual
* Copyright (C) 2026 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'dart:math';

import 'package:flutter/material.dart';

import 'leveling_configs.dart';

/// Painted visual for a [LevelingScreenType] — a shared rounded rectangle
/// outline, differentiated by what sits inside:
///   * tempered glass → a "sparkly clean" sparkle in the top-left corner
///   * wave release film → a honeycomb (hexagon) grid across the surface
///
/// Shared between the leveling wizard's selection step and the leveling
/// settings screen so both render identically.
class ScreenTypeVisual extends StatelessWidget {
  const ScreenTypeVisual({
    super.key,
    required this.screenType,
    required this.color,
  });

  final LevelingScreenType screenType;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ScreenTypePainter(screenType: screenType, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class ScreenTypePainter extends CustomPainter {
  ScreenTypePainter({required this.screenType, required this.color});

  final LevelingScreenType screenType;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.015
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.85);
    final fill = Paint()..color = color.withValues(alpha: 0.12);

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(s * 0.10),
    );

    canvas.drawRRect(rrect, fill);
    switch (screenType) {
      case LevelingScreenType.temperedGlass:
        _paintSparkle(canvas, s);
      case LevelingScreenType.waveReleaseFilm:
        _paintHexGrid(canvas, size, rrect);
    }
    canvas.drawRRect(rrect, outline);
  }

  /// A four-pointed "clean" sparkle in the top-left corner.
  void _paintSparkle(Canvas canvas, double s) {
    final center = Offset(s * 0.20, s * 0.20);
    final outer = s * 0.075;
    final inner = outer * 0.20;
    final path = Path()
      ..moveTo(center.dx, center.dy - outer)
      ..quadraticBezierTo(
          center.dx + inner, center.dy - inner, center.dx + outer, center.dy)
      ..quadraticBezierTo(
          center.dx + inner, center.dy + inner, center.dx, center.dy + outer)
      ..quadraticBezierTo(
          center.dx - inner, center.dy + inner, center.dx - outer, center.dy)
      ..quadraticBezierTo(
          center.dx - inner, center.dy - inner, center.dx, center.dy - outer)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// A honeycomb of pointy-top hexagons clipped to the rectangle.
  void _paintHexGrid(Canvas canvas, Size size, RRect clip) {
    // Finer cells with a thinner, lighter stroke than the outer outline.
    final hexR = size.shortestSide * 0.050;
    final hexStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.0075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.85);
    final dx = sqrt(3) * hexR;
    final dy = 1.5 * hexR;
    canvas.save();
    canvas.clipRRect(clip);
    final rows = (size.height / dy).ceil() + 2;
    final cols = (size.width / dx).ceil() + 2;
    for (int row = 0; row < rows; row++) {
      final offsetX = row.isOdd ? dx / 2 : 0.0;
      for (int col = 0; col < cols; col++) {
        canvas.drawPath(
          _hexagonPath(Offset(offsetX + col * dx - dx, row * dy - dy), hexR),
          hexStroke,
        );
      }
    }
    canvas.restore();
  }

  Path _hexagonPath(Offset center, double r) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i * 60 - 90) * pi / 180;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant ScreenTypePainter oldDelegate) =>
      oldDelegate.screenType != screenType || oldDelegate.color != color;
}
