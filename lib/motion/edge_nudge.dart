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

import 'package:flutter/widgets.dart';

/// Moves its child a few pixels toward a D-pad press that found nothing to focus, and springs it back, so a press
/// at the end of a row is never a dead key. [EdgeNudge.of] finds the nudge around the focused widget.
class EdgeNudge extends StatefulWidget {
  final double distance;
  final Duration duration;

  /// Called as a nudge starts, for whatever draws around the child and has to follow it.
  final VoidCallback? onNudge;
  final Widget child;

  const EdgeNudge({super.key, required this.distance, required this.duration, this.onNudge, required this.child});

  static EdgeNudgeState? of(BuildContext context) => context.findAncestorStateOfType<EdgeNudgeState>();

  @override
  State<EdgeNudge> createState() => EdgeNudgeState();
}

class EdgeNudgeState extends State<EdgeNudge> with SingleTickerProviderStateMixin {
  // Out fast (the first quarter, eased out), back slower: reads as a bump against a wall.
  static const double _peakAt = 0.25;

  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  Offset _direction = Offset.zero;

  @override
  void didUpdateWidget(EdgeNudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Bumps toward [direction]; a nudge already running restarts from where it is.
  void nudge(AxisDirection direction) {
    _direction = switch (direction) {
      AxisDirection.left => Offset(-1, 0),
      AxisDirection.right => Offset(1, 0),
      AxisDirection.up => Offset(0, -1),
      AxisDirection.down => Offset(0, 1),
    };
    _controller.forward(from: 0);
    widget.onNudge?.call();
  }

  static double _shape(double t) {
    if (t < _peakAt) {
      return Curves.easeOutCubic.transform(t / _peakAt);
    }
    return 1 - Curves.easeInOutCubic.transform((t - _peakAt) / (1 - _peakAt));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) =>
        Transform.translate(offset: _direction * widget.distance * max(0, _shape(_controller.value)), child: child),
    child: widget.child,
  );
}
