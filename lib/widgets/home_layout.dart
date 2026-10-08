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

/// Geometry of the home screen: one row of large "main app" tiles above a grid of every other app, of which the
/// first row peeks in at the bottom edge of the initial view.
class HomeLayout {
  static const double sidePadding = 32;
  static const double gap = 16;
  static const int gridColumns = 6;
  static const double headingTop = 24;
  static const double headingBottom = 12;
  static const double peekFraction = 0.35;
  static const double aspectRatio = 16 / 9;

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

  /// Space under the grid so the "Apps" heading can always be scrolled to the top edge, even with few apps.
  double bottomSpacer(int count) => max(gap, height - headingBlockHeight - gridContentHeight(count));
}
