/*
 * FLauncher
 * Copyright (C) 2026  Niklas Neugebauer
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';

/// How the focus ring looks: a stroke [gap] outside the tile, with a faint white [halo] stroke around it.
@immutable
class RingStyle {
  static const double haloWidth = 6;

  final Color color;
  final double gap;
  final double halo;

  const RingStyle({this.color = Palette.brass, this.gap = 0, this.halo = 0});

  @override
  bool operator ==(Object other) =>
      other is RingStyle && other.color == color && other.gap == gap && other.halo == halo;

  @override
  int get hashCode => Object.hash(color, gap, halo);
}

/// Paints the ring around a tile of the painter's size, outside its bounds, with corners following [radius].
class FocusRingPainter extends CustomPainter {
  final RingStyle style;
  final double radius;

  const FocusRingPainter({required this.style, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    const width = Shapes.focusRing;
    final tile = Offset.zero & size;
    RRect around(double outset) => RRect.fromRectAndRadius(tile.inflate(outset), Radius.circular(radius + outset));
    if (style.halo > 0) {
      canvas.drawRRect(
        around(style.gap + width + RingStyle.haloWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = RingStyle.haloWidth
          ..color = Colors.white.withValues(alpha: style.halo),
      );
    }
    canvas.drawRRect(
      around(style.gap + width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = style.color,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter oldDelegate) => oldDelegate.style != style || oldDelegate.radius != radius;
}
