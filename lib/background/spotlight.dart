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

import 'package:flutter/widgets.dart';

/// Where the background's light should be: the focused tile, and the hue of its app when it has one. Tiles report
/// here; the background measures the tile itself every frame, so the light follows scrolling and the tile's lift.
class Spotlight extends ChangeNotifier {
  BuildContext? _tile;
  double? _hue;
  int _landings = 0;

  /// The tile the light is on; it stays on the last one when focus leaves the tiles.
  BuildContext? get tile => _tile;

  /// The app's hue in degrees, or null for a grey or unknown banner (the light stays warm then).
  double? get hue => _hue;

  /// Counts focus landings, so the background pulses once per landing.
  int get landings => _landings;

  void focus(BuildContext tile, double? hue) {
    _tile = tile;
    _hue = hue;
    _landings++;
    notifyListeners();
  }

  /// The lit tile moved (reordered): the light follows it, without a new landing.
  void follow(BuildContext tile) {
    if (_tile == tile) {
      notifyListeners();
    }
  }

  /// The hue of [tile]'s app became known after it was focused.
  void updateHue(BuildContext tile, double? hue) {
    if (_tile == tile && _hue != hue) {
      _hue = hue;
      notifyListeners();
    }
  }
}
