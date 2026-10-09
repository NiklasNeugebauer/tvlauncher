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
  static const focusOut = TuningParam("focusOutMs", "Focus out", 120, 40, 400, 10, unit: " ms");
  static const holdFocus = TuningParam("holdFocusMs", "Focus while held", 120, 40, 400, 10, unit: " ms");
  static const lift = TuningParam("liftPx", "Lift", 8, 0, 20, 1, unit: " px");
  static const focusScale = TuningParam("focusScale", "Focus scale", 1.1, 1, 1.3, 0.01);
  static const dimBrightness = TuningParam("dimBrightness", "Unfocused brightness", 0.72, 0.3, 1, 0.02);
  static const dimSaturation = TuningParam("dimSaturation", "Unfocused saturation", 0.85, 0, 1, 0.05);
  static const ringGap = TuningParam("ringGapPx", "Ring gap", 4, 0, 12, 1, unit: " px");
  static const ringHalo = TuningParam("ringHalo", "Ring halo", 0.08, 0, 0.4, 0.02);
  static const ringHaloWidth = TuningParam("ringHaloPx", "Ring halo width", 3, 0, 8, 1, unit: " px");
  static const sheen = TuningParam("sheenOpacity", "Sheen", 0.22, 0, 0.6, 0.02);
  static const sheenLength = TuningParam("sheenMs", "Sheen length", 900, 300, 2000, 50, unit: " ms");
  static const pressScale = TuningParam("pressScale", "Press scale", 0.96, 0.85, 1, 0.01);
  static const pressDown = TuningParam("pressDownMs", "Press down", 80, 20, 300, 10, unit: " ms");
  static const pressUp = TuningParam("pressUpMs", "Press up", 180, 60, 500, 10, unit: " ms");
  static const nudge = TuningParam("nudgePx", "Edge nudge", 9, 0, 24, 1, unit: " px");
  static const nudgeLength = TuningParam("nudgeMs", "Edge nudge length", 280, 120, 600, 20, unit: " ms");
  static const lightStrength = TuningParam("lightStrength", "Light strength", 1, 0.4, 2, 0.05);
  static const grid = TuningParam("gridPx", "Diamond grid", 15, 8, 40, 1, unit: " px");
  static const spotStiffness = TuningParam("spotStiffness", "Spotlight spring", 120, 30, 400, 10);
  static const ambientFps = TuningParam("ambientFps", "Shimmer rate (0 = off)", 30, 0, 60, 5, unit: " fps");
  static const panelIn = TuningParam("panelInMs", "Panel in", 380, 100, 1000, 20, unit: " ms");
  static const panelOut = TuningParam("panelOutMs", "Panel out", 240, 80, 800, 20, unit: " ms");
  static const rowStagger = TuningParam("rowStaggerMs", "Row stagger", 40, 0, 120, 5, unit: " ms");
  static const panelScale = TuningParam("panelScale", "Launcher behind panel", 0.97, 0.9, 1, 0.01);
  static const panelLight = TuningParam("panelLight", "Light behind panel", 0.4, 0, 1, 0.05);
  static const panelBlur = TuningParam("panelBlurPx", "Panel blur (0 = off)", 0, 0, 20, 1, unit: " px");

  static const List<TuningParam> all = [
    focusResponse,
    focusOvershoot,
    focusOut,
    holdFocus,
    lift,
    focusScale,
    dimBrightness,
    dimSaturation,
    ringGap,
    ringHalo,
    ringHaloWidth,
    sheen,
    sheenLength,
    pressScale,
    pressDown,
    pressUp,
    nudge,
    nudgeLength,
    lightStrength,
    grid,
    spotStiffness,
    ambientFps,
    panelIn,
    panelOut,
    rowStagger,
    panelScale,
    panelLight,
    panelBlur,
  ];
}

/// Current values of every [TuningParam]; unset ones read as their default.
class Tuning extends ChangeNotifier {
  /// The defaults, for widgets pumped without a band (tests, a panel on its own).
  static final Tuning defaults = Tuning();

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
  SpringSpec get focusSpring => SpringSpec(response: _ms(Tune.focusResponse), overshoot: this[Tune.focusOvershoot]);

  /// Leaving focus: quicker than arriving, without overshoot.
  SpringSpec get focusOutSpring => _critical(Tune.focusOut);

  /// Focus moves while a direction key repeats: short and without overshoot, so the row runs instead of bouncing.
  SpringSpec get holdSpring => _critical(Tune.holdFocus);

  SpringSpec get pressDownSpring => _critical(Tune.pressDown);

  SpringSpec get pressUpSpring => SpringSpec(response: _ms(Tune.pressUp), overshoot: this[Tune.focusOvershoot]);

  Duration get sheenDuration => _ms(Tune.sheenLength);

  Duration get nudgeDuration => _ms(Tune.nudgeLength);

  // A critically damped spring is within 2 % of its target after about 0.93 of its response, so the param reads
  // as the length of the move.
  SpringSpec _critical(TuningParam param) => SpringSpec(response: _ms(param));

  Duration _ms(TuningParam param) => Duration(milliseconds: this[param].round());

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
