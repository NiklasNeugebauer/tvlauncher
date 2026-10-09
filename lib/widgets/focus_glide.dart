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

import 'package:flauncher/motion/spring.dart';
import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// One focus ring for the whole home screen that slides from tile to tile instead of jumping.
///
/// The focused tile reports its visual box with [FocusGlideScope.track]; while anything may be moving (focus
/// change, scrolling, a tile's own scale animation, a relayout) a ticker moves the ring toward that box, on
/// [spring] when there is one and on v4's overshoot-free ease otherwise, then stops so an idle home screen
/// schedules no frames.
class FocusGlide extends StatefulWidget {
  final bool enabled;
  final SpringSpec? spring;
  final Widget child;

  const FocusGlide({super.key, required this.enabled, this.spring, required this.child});

  @override
  State<FocusGlide> createState() => FocusGlideState();
}

class FocusGlideState extends State<FocusGlide> with SingleTickerProviderStateMixin {
  // Time constant of the ease: the ring covers about 99 % of the way in five of these.
  static const double _tau = 0.036;
  static const Duration _settle = Duration(milliseconds: 260);

  final GlobalKey _stackKey = GlobalKey();
  late final Ticker _ticker = createTicker(_tick);
  BuildContext? _tracked;
  Rect? _rect;
  // Left, top, right and bottom of the ring on the spring.
  final List<SpringState> _edges = [for (var i = 0; i < 4; i++) SpringState(0)];
  double _radius = Shapes.tileRadius;
  Duration _lastTick = Duration.zero;
  Duration _quietSince = Duration.zero;
  Duration _elapsed = Duration.zero;

  bool get enabled => widget.enabled;

  /// [tile] gained focus: the ring heads there, or appears there when it was hidden.
  void track(BuildContext tile) {
    final wasHidden = _tracked == null;
    _tracked = tile;
    if (wasHidden) {
      _rect = null;
    }
    kick();
  }

  /// [tile] lost focus; the ring fades out unless another tile takes it in the same focus change (whose
  /// listeners may run in either order, hence the microtask).
  void release(BuildContext tile) => Future.microtask(() {
    if (_tracked == tile) {
      _tracked = null;
      if (mounted) {
        setState(() {});
      }
    }
  });

  /// Something may have moved: follow the tracked tile for a little while.
  void kick() {
    _quietSince = _elapsed;
    if (!_ticker.isActive && mounted) {
      _lastTick = Duration.zero;
      _elapsed = Duration.zero;
      _quietSince = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    // A ticker's first frame reports zero elapsed time; count it as one display frame so the ring moves at once.
    final dt = elapsed == Duration.zero ? 1 / 60 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _elapsed = elapsed;
    final target = _targetRect();
    if (target == null) {
      _ticker.stop();
      return;
    }
    final current = _rect;
    final spring = widget.spring;
    final Rect next;
    if (current == null) {
      next = target;
      _setEdges(target);
    } else if (spring != null) {
      final targets = [target.left, target.top, target.right, target.bottom];
      for (var i = 0; i < 4; i++) {
        _edges[i].target = targets[i];
        _edges[i].step(dt, spring);
      }
      next = Rect.fromLTRB(_edges[0].value, _edges[1].value, _edges[2].value, _edges[3].value);
    } else {
      next = Rect.lerp(current, target, 1 - exp(-dt / _tau))!;
      _setEdges(next);
    }
    final settled = _distance(next, target) < 0.5 && _edges.every((e) => e.velocity.abs() < 5);
    setState(() => _rect = settled ? target : next);
    if (settled && elapsed - _quietSince > _settle) {
      _ticker.stop();
    }
  }

  void _setEdges(Rect rect) {
    final values = [rect.left, rect.top, rect.right, rect.bottom];
    for (var i = 0; i < 4; i++) {
      _edges[i].jumpTo(values[i]);
    }
  }

  Rect? _targetRect() {
    final tile = _tracked;
    if (tile == null || !tile.mounted) {
      return null;
    }
    final box = tile.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.attached || !box.hasSize) {
      return null;
    }
    final rect = MatrixUtils.transformRect(box.getTransformTo(stack), Offset.zero & box.size);
    _radius = Shapes.tileRadius * rect.width / max(1, box.size.width);
    return rect;
  }

  double _distance(Rect a, Rect b) => max(
    max((a.left - b.left).abs(), (a.top - b.top).abs()),
    max((a.right - b.right).abs(), (a.bottom - b.bottom).abs()),
  );

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return FocusGlideScope(
      state: widget.enabled ? this : null,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          if (_tracked != null) {
            kick();
          }
          return false;
        },
        child: Stack(
          key: _stackKey,
          children: [
            widget.child,
            if (widget.enabled && rect != null)
              Positioned.fromRect(
                rect: rect,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _tracked == null ? 0 : 1,
                    duration: Motion.focus,
                    curve: Motion.curve,
                    child: DecoratedBox(
                      key: Key("focus-glide"),
                      decoration: BoxDecoration(
                        border: Border.all(color: Palette.brass, width: Shapes.focusRing),
                        borderRadius: BorderRadius.circular(_radius),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lets tiles find the glide; absent (or disabled) they draw their own ring.
class FocusGlideScope extends InheritedWidget {
  final FocusGlideState? state;

  const FocusGlideScope({super.key, required this.state, required super.child});

  static FocusGlideState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FocusGlideScope>()?.state;

  @override
  bool updateShouldNotify(FocusGlideScope oldWidget) => oldWidget.state != state;
}
