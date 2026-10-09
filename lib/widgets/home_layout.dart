/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'dart:math';

import 'package:flutter/painting.dart';

/// Geometry of the home screen: one row of large "main app" tiles above a grid of every other app, of which the
/// first row peeks in at the bottom edge of the initial view. Once in the grid, the view shows whole rows only: it
/// moves between "windows" of rows so nothing rests half cut off under the clock.
class HomeLayout {
  static const double sidePadding = 32;
  static const double gap = 16;
  static const int gridColumns = 6;
  static const double headingTop = 24;
  static const double headingBottom = 12;
  static const double peekFraction = 0.35;
  static const double aspectRatio = 16 / 9;

  /// Where the hero row sits in its zone: below centre, toward the glow rising from the bottom of the screen.
  static const Alignment heroAlignment = Alignment(0, 0.3);

  final double width;
  final double height;
  final double headingHeight;

  const HomeLayout({required this.width, required this.height, required this.headingHeight});

  double get availableWidth => width - 2 * sidePadding;

  double get gridTileWidth => (availableWidth - (gridColumns - 1) * gap) / gridColumns;

  double get gridTileHeight => gridTileWidth / aspectRatio;

  double get headingBlockHeight => headingTop + headingHeight + headingBottom;

  double get peekHeight => headingBlockHeight + peekFraction * gridTileHeight;

  double get heroZoneHeight => height - peekHeight;

  /// Four tiles fill the width; more tiles shrink so they always share one row.
  double heroTileWidth(int count) {
    final fourAcross = (availableWidth - 3 * gap) / 4;
    final fitAll = count == 0 ? fourAcross : (availableWidth - (count - 1) * gap) / count;
    final maxHeight = 0.7 * heroZoneHeight;
    return min(min(fourAcross, fitAll), maxHeight * aspectRatio);
  }

  double heroTileHeight(int count) => heroTileWidth(count) / aspectRatio;

  double gridContentHeight(int count) {
    final rows = (count / gridColumns).ceil();
    return rows == 0 ? 0 : rows * gridTileHeight + (rows - 1) * gap;
  }

  double get rowPitch => gridTileHeight + gap;

  double get gridTop => heroZoneHeight + headingBlockHeight;

  /// Whole grid rows that fit under the "Apps" heading when it sits at the top edge.
  int get rowsUnderHeading => max(1, ((height - headingBlockHeight) / rowPitch).floor());

  /// Whole grid rows that fit once the heading has scrolled away, with a gap above and below.
  int get rowsPerWindow => max(1, ((height - gap) / rowPitch).floor());

  /// Scroll offset of grid window [window]: 0 shows the heading and the first rows, window k > 0 starts at row k.
  double windowOffset(int window) => window == 0 ? heroZoneHeight : gridTop + window * rowPitch - gap;

  /// The window that shows grid row [row] when coming from window [current] (-1 for the hero): the current one
  /// if the row is already whole in it, otherwise the nearest one that has the row at its leading edge.
  int windowFor(int row, int current) {
    if (current >= 0) {
      final first = current == 0 ? 0 : current;
      final last = current == 0 ? rowsUnderHeading - 1 : current + rowsPerWindow - 1;
      if (row >= first && row <= last) {
        return current;
      }
      if (row < first) {
        return row < rowsUnderHeading ? 0 : row;
      }
    }
    return row < rowsUnderHeading ? 0 : max(1, row - rowsPerWindow + 1);
  }

  /// Space under the grid so every window can be scrolled to, even with few apps.
  double bottomSpacer(int count) {
    final rows = (count / gridColumns).ceil();
    final lastWindow = windowFor(max(0, rows - 1), -1);
    final needed = windowOffset(lastWindow) + height - gridTop - gridContentHeight(count);
    return max(gap, needed);
  }
}
