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

import 'dart:typed_data';

import 'package:tvlauncher/background/banner_hue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List pixels(List<List<int>> rgb) => Uint8List.fromList([
    for (final p in rgb) ...[...p, 255],
  ]);

  test("a red logo on white gives red", () {
    final hue = BannerHue.hueOfPixels(
      pixels([
        ...List.filled(6, [255, 255, 255]),
        ...List.filled(4, [230, 30, 30]),
      ]),
    );

    expect(hue, closeTo(0, 1));
  });

  test("the colour with more weight wins, as a circular mean", () {
    final hue = BannerHue.hueOfPixels(
      pixels([
        ...List.filled(3, [0, 0, 255]),
        ...List.filled(1, [0, 255, 255]),
      ]),
    );

    expect(hue, inInclusiveRange(200, 240));
  });

  test("a small logo on a plain ground still gives its colour", () {
    final onWhite = BannerHue.hueOfPixels(
      pixels([
        ...List.filled(19, [255, 255, 255]),
        [230, 30, 30],
      ]),
    );
    final onBlack = BannerHue.hueOfPixels(
      pixels([
        ...List.filled(19, [10, 10, 10]),
        [230, 30, 30],
      ]),
    );

    expect(onWhite, closeTo(0, 1));
    expect(onBlack, closeTo(0, 1));
  });

  test("a grey banner has no hue", () {
    expect(BannerHue.hueOfPixels(pixels(List.filled(10, [200, 200, 200]))), isNull);
    expect(
      BannerHue.hueOfPixels(
        pixels([
          ...List.filled(49, [20, 20, 20]),
          [255, 0, 0],
        ]),
      ),
      isNull,
    );
    expect(BannerHue.hueOfPixels(pixels(List.filled(10, [140, 120, 120]))), isNull);
  });

  test("a multicolour logo has no hue", () {
    final hue = BannerHue.hueOfPixels(
      pixels([
        ...List.filled(10, [255, 255, 255]),
        [230, 30, 30],
        [30, 230, 30],
        [30, 30, 230],
      ]),
    );

    expect(hue, isNull);
  });
}
