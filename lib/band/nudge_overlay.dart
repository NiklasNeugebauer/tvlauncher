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

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';

/// Drawn over the whole frame while nudging: a 1 px outline of the full frame (so cropping by overscan or keystone
/// shows on the wall), the band's outline, and a readout of the values with the controls.
class NudgeOverlay extends StatelessWidget {
  final BandController controller;
  final Rect band;

  const NudgeOverlay({super.key, required this.controller, required this.band});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frame = Offset.zero & constraints.biggest;
      final spaceAbove = band.top - frame.top;
      final spaceBelow = frame.bottom - band.bottom;
      final readout = _readout(context);
      return IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _OutlinePainter(band))),
            // In the larger black area, or over the band's middle when it fills the frame.
            if (spaceAbove >= 64 || spaceBelow >= 64)
              Positioned(
                left: 0,
                right: 0,
                top: spaceAbove >= spaceBelow ? 0 : band.bottom,
                height: spaceAbove >= spaceBelow ? spaceAbove : spaceBelow,
                child: Center(child: readout),
              )
            else
              Center(child: readout),
          ],
        ),
      );
    },
  );

  Widget _readout(BuildContext context) {
    final geometry = controller.geometry;
    final textTheme = Theme.of(context).textTheme;
    String percent(double value) => "${(value * 100).round()} %";
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Palette.brass),
          borderRadius: BorderRadius.circular(Shapes.rowRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Height ${percent(geometry.height)}   ·   Position ${percent(geometry.position)}   ·   Edge ${geometry.edge.name}",
              key: Key("nudge-values"),
              style: textTheme.titleMedium!.copyWith(color: Palette.cream),
            ),
            SizedBox(height: 4),
            Text(
              "↑↓ height   ←→ position   OK edge   Back done",
              style: textTheme.bodySmall!.copyWith(color: Palette.creamDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlinePainter extends CustomPainter {
  final Rect band;

  _OutlinePainter(this.band);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Palette.brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect((Offset.zero & size).deflate(0.5), paint);
    canvas.drawRect(band.deflate(0.5), paint..color = Palette.brass.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) => oldDelegate.band != band;
}
