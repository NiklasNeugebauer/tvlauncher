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

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// The dominant hue of a banner, for the App colour light: the circular mean of the pixels' hues, weighted by
/// saturation and value, so the logo's colour wins over grey and black. Null when the banner is nearly grey.
abstract final class BannerHue {
  static const int _sampleWidth = 32;
  static const double _minChroma = 0.12;

  static final Map<int, Future<double?>> _cache = {};

  /// Decodes once per banner (keyed by its bytes' identity and length) at a tiny size.
  static Future<double?> of(Uint8List banner) =>
      _cache.putIfAbsent(Object.hash(identityHashCode(banner), banner.length), () => _compute(banner));

  static Future<double?> _compute(Uint8List banner) async {
    try {
      final codec = await ui.instantiateImageCodec(banner, targetWidth: _sampleWidth);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();
      return data == null ? null : hueOfPixels(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// [rgba] is 4 bytes per pixel.
  static double? hueOfPixels(Uint8List rgba) {
    var x = 0.0, y = 0.0, weight = 0.0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final hsv = HSVColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
      final w = hsv.saturation * hsv.value;
      final angle = hsv.hue * pi / 180;
      x += cos(angle) * w;
      y += sin(angle) * w;
      weight += w;
    }
    final pixels = rgba.length ~/ 4;
    if (pixels == 0 || sqrt(x * x + y * y) / pixels < _minChroma || weight == 0) {
      return null;
    }
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }
}
