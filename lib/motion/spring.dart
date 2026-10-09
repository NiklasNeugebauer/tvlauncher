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

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// A spring described the way a designer tunes it: [response] is the period of the undamped oscillation (the
/// move peaks after about two thirds of it and settles at about one), [overshoot] the fraction by which it passes
/// the target before coming back (0 = critically damped).
@immutable
class SpringSpec {
  final Duration response;
  final double overshoot;

  const SpringSpec({required this.response, this.overshoot = 0});

  double get stiffness => pow(2 * pi / max(0.016, response.inMicroseconds / 1e6), 2).toDouble();

  double get dampingRatio {
    if (overshoot <= 0) {
      return 1;
    }
    final l = log(overshoot);
    return -l / sqrt(pi * pi + l * l);
  }

  double get damping => 2 * dampingRatio * sqrt(stiffness);

  SpringDescription get description =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: stiffness, ratio: dampingRatio);

  @override
  bool operator ==(Object other) => other is SpringSpec && other.response == response && other.overshoot == overshoot;

  @override
  int get hashCode => Object.hash(response, overshoot);
}

/// One value on a spring, stepped by its owner's ticker. A new [target] keeps the current value and velocity, so a
/// move is redirected mid-flight instead of restarting.
class SpringState {
  // Stiff springs are unstable with a 16 ms explicit step; integrate in slices no longer than this.
  static const double _maxSlice = 1 / 240;

  double value;
  double velocity = 0;
  double target;

  SpringState(this.value) : target = value;

  void jumpTo(double value) {
    this.value = value;
    target = value;
    velocity = 0;
  }

  /// Advances by [dt] seconds; true once within [tolerance] of the target and nearly still, when it snaps there.
  bool step(double dt, SpringSpec spec, {double tolerance = 0.5}) {
    final k = spec.stiffness;
    final c = spec.damping;
    var left = dt;
    while (left > 0) {
      final h = min(left, _maxSlice);
      velocity += (-k * (value - target) - c * velocity) * h;
      value += velocity * h;
      left -= h;
    }
    if ((value - target).abs() < tolerance && velocity.abs() < tolerance * 10) {
      jumpTo(target);
      return true;
    }
    return false;
  }
}

/// Animates [value] on a spring whenever it changes, like an implicit animation; a change mid-flight retargets
/// from the current value and velocity. With [spec] null the value jumps.
class SpringBuilder extends StatefulWidget {
  final double value;
  final SpringSpec? spec;
  final Widget Function(BuildContext context, double value, Widget? child) builder;
  final Widget? child;

  const SpringBuilder({super.key, required this.value, required this.spec, required this.builder, this.child});

  @override
  State<SpringBuilder> createState() => _SpringBuilderState();
}

class _SpringBuilderState extends State<SpringBuilder> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(vsync: this, value: widget.value);

  @override
  void didUpdateWidget(SpringBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value && widget.spec == oldWidget.spec) {
      return;
    }
    final spec = widget.spec;
    if (spec == null) {
      _controller.value = widget.value;
      return;
    }
    final velocity = _controller.isAnimating ? _controller.velocity : 0.0;
    _controller.animateWith(
      SpringSimulation(spec.description, _controller.value, widget.value, velocity, tolerance: _tolerance),
    );
  }

  // Values here are scales and fractions as well as pixels, so settle tighter than the default 1e-3.
  static const Tolerance _tolerance = Tolerance(distance: 1e-4, velocity: 1e-3);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => widget.builder(context, _controller.value, child),
    child: widget.child,
  );
}
