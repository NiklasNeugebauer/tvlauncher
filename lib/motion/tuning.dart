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

import 'package:flauncher/motion/spring.dart';
import 'package:flutter/foundation.dart';

/// One number that can be tuned on the wall: from "Band & motion" in steps of [step], or in the config file.
@immutable
class TuningParam {
  final String key;
  final String label;
  final double defaultValue;
  final double min;
  final double max;
  final double step;
  final String unit;

  const TuningParam(this.key, this.label, this.defaultValue, this.min, this.max, this.step, {this.unit = ""});

  double clamp(double value) {
    final steps = ((value - min) / step).round();
    final snapped = min + steps * step;
    // Round away the float noise of the snap so the file stays readable.
    return double.parse(snapped.clamp(min, max).toStringAsFixed(4));
  }

  String format(double value) {
    final digits = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);
    return "${value.toStringAsFixed(digits)}$unit";
  }
}

/// The tunable numbers of the motion, with the polish plan's values as defaults.
abstract final class Tune {
  static const focusResponse = TuningParam("focusResponseMs", "Focus spring", 300, 100, 800, 10, unit: " ms");
  static const focusOvershoot = TuningParam("focusOvershoot", "Focus overshoot", 0.06, 0, 0.3, 0.01);

  static const List<TuningParam> all = [focusResponse, focusOvershoot];
}

/// Current values of every [TuningParam]; unset ones read as their default.
class Tuning extends ChangeNotifier {
  final Map<String, double> _values = {};

  double operator [](TuningParam param) => _values[param.key] ?? param.defaultValue;

  void operator []=(TuningParam param, double value) {
    final clamped = param.clamp(value);
    if (this[param] == clamped) {
      return;
    }
    _values[param.key] = clamped;
    notifyListeners();
  }

  void stepBy(TuningParam param, int steps) => this[param] = this[param] + param.step * steps;

  /// The focus move: the ring, and the tile's lift and scale.
  SpringSpec get focusSpring => SpringSpec(
    response: Duration(milliseconds: this[Tune.focusResponse].round()),
    overshoot: this[Tune.focusOvershoot],
  );

  Map<String, double> toJson() => {for (final param in Tune.all) param.key: this[param]};

  /// Takes the values in [json] and drops the others back to their defaults; true if anything changed.
  bool load(Map<String, dynamic>? json) {
    final next = <String, double>{};
    for (final param in Tune.all) {
      final value = json?[param.key];
      if (value is num) {
        next[param.key] = param.clamp(value.toDouble());
      }
    }
    if (mapEquals(next, _values)) {
      return false;
    }
    _values
      ..clear()
      ..addAll(next);
    notifyListeners();
    return true;
  }
}
