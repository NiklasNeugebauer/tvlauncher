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

import 'package:flutter/painting.dart';

/// How the lit band meets the black frame around it.
enum BandEdge {
  /// A crisp rectangle across the full width, like a letterboxed film.
  hard,

  /// The background fades into black over [BandGeometry.softFade], like lamp light falling off.
  soft,

  /// A panel with margins on every side and rounded corners, floating on the wall.
  inset,
}

/// Where the home screen sits in the projected frame: a band of [height] (fraction of the frame) whose free space
/// above and below is split by [position] (0 = top, 1 = bottom). Everything outside the band is black.
class BandGeometry {
  static const double step = 0.05;
  static const double minHeight = 0.3;
  static const double insetMargin = 24;
  static const double insetRadius = 20;
  static const double softFade = 72;

  final double height;
  final double position;
  final BandEdge edge;

  const BandGeometry({required this.height, required this.position, required this.edge});

  /// Chosen on the wall on 2026-10-08.
  static const BandGeometry release = BandGeometry(height: 0.6, position: 0.6, edge: BandEdge.hard);

  /// The band's rectangle inside a frame of [frame] size.
  Rect rect(Size frame) {
    final bandHeight = frame.height * height;
    final top = (frame.height - bandHeight) * position;
    final band = Rect.fromLTWH(0, top, frame.width, bandHeight);
    return edge == BandEdge.inset ? band.deflate(insetMargin) : band;
  }

  double get cornerRadius => edge == BandEdge.inset ? insetRadius : 0;

  BandGeometry copyWith({double? height, double? position, BandEdge? edge}) => BandGeometry(
    height: _snap((height ?? this.height).clamp(minHeight, 1.0)),
    position: _snap((position ?? this.position).clamp(0.0, 1.0)),
    edge: edge ?? this.edge,
  );

  BandGeometry nextEdge() => copyWith(edge: BandEdge.values[(edge.index + 1) % BandEdge.values.length]);

  Map<String, Object> toJson() => {"height": height, "position": position, "edge": edge.name};

  static BandGeometry fromJson(Map<String, dynamic> json) => release.copyWith(
    height: (json["height"] as num?)?.toDouble(),
    position: (json["position"] as num?)?.toDouble(),
    edge: BandEdge.values.where((edge) => edge.name == json["edge"]).firstOrNull,
  );

  // Steps add up to values like 0.6000000001; keep them on the 5 % grid so the readout and the JSON stay clean.
  static double _snap(double value) => ((value / step).round() * step * 1000).round() / 1000;

  @override
  bool operator ==(Object other) =>
      other is BandGeometry && other.height == height && other.position == position && other.edge == edge;

  @override
  int get hashCode => Object.hash(height, position, edge);

  @override
  String toString() => "BandGeometry(height: $height, position: $position, edge: ${edge.name})";
}
