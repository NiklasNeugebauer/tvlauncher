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
import 'package:flauncher/widgets/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// One focus ring for the whole home screen that travels from tile to tile instead of jumping.
///
/// The focused tile reports its visual box with [FocusGlideScope.track]. The ring is glued to that box, so it
/// follows scrolling, the tile's own lift and scale and an edge nudge exactly; only the jump between two tiles is
/// animated, as an offset that decays to zero: on [spring] when there is one, on v4's overshoot-free ease
/// otherwise. While anything may be moving a ticker runs, then it stops so an idle home screen schedules no frames.
class FocusGlide extends StatefulWidget {
  final bool enabled;

  /// Read at every focus change, so a move that starts while a key is held can use a different spring.
  final ValueGetter<SpringSpec>? spring;
  final RingStyle style;
  final Widget child;

  const FocusGlide({
    super.key,
    required this.enabled,
    this.spring,
    this.style = const RingStyle(),
    required this.child,
  });

  @override
  State<FocusGlide> createState() => FocusGlideState();
}

class FocusGlideState extends State<FocusGlide> with SingleTickerProviderStateMixin {
  // Time constant of the ease: the offset shrinks to about 1 % in five of these.
  static const double _tau = 0.036;
  static const Duration _settle = Duration(milliseconds: 260);

  final GlobalKey _stackKey = GlobalKey();
  late final Ticker _ticker = createTicker(_tick);
  final _Repaint _repaint = _Repaint();
  BuildContext? _tracked;
  Rect? _painted;
  Rect? _lastTarget;
  SpringSpec? _spring;
  double _radius = Shapes.tileRadius;
  // Left, top, right and bottom of the ring relative to the tracked tile, decaying to zero.
  final List<SpringState> _offsets = [for (var i = 0; i < 4; i++) SpringState(0)];
  Duration _lastTick = Duration.zero;
  Duration _quietSince = Duration.zero;
  Duration _elapsed = Duration.zero;

  bool get enabled => widget.enabled;

  /// Where the ring was last drawn, in the glide's coordinates.
  @visibleForTesting
  Rect? get ringRect => _painted;

  /// [tile] gained focus: the ring heads there from where it is, or appears there when it was hidden.
  void track(BuildContext tile) {
    final from = _tracked == null ? null : _painted;
    _tracked = tile;
    _spring = widget.spring?.call();
    final to = _targetRect();
    if (from == null || to == null) {
      for (final offset in _offsets) {
        offset.jumpTo(0);
      }
    } else {
      final deltas = [from.left - to.left, from.top - to.top, from.right - to.right, from.bottom - to.bottom];
      for (var i = 0; i < 4; i++) {
        // The velocity stays: a press mid-move redirects the ring instead of restarting it.
        _offsets[i]
          ..value = deltas[i]
          ..target = 0;
      }
    }
    setState(() {});
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
    _repaint.dispose();
    super.dispose();
  }

  // Steps the offsets and asks for a repaint; where the tile is, is measured when the ring is painted, after this
  // frame's layout, so the ring never trails the tile by a frame.
  void _tick(Duration elapsed) {
    // A ticker's first frame reports zero elapsed time; count it as one display frame so the ring moves at once.
    final dt = elapsed == Duration.zero ? 1 / 60 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _elapsed = elapsed;
    if (_tracked == null) {
      _ticker.stop();
      return;
    }
    // The tile itself is still moving (scroll, lift, nudge): keep following.
    final target = _painted == null ? null : _targetRect();
    if (target != _lastTarget) {
      _quietSince = elapsed;
      _lastTarget = target;
    }
    final spring = _spring;
    var settled = true;
    for (final offset in _offsets) {
      if (spring != null) {
        settled &= offset.step(dt, spring);
      } else if (offset.value != 0) {
        offset.value *= exp(-dt / _tau);
        if (offset.value.abs() < 0.5) {
          offset.jumpTo(0);
        } else {
          settled = false;
        }
      }
    }
    _repaint.ping();
    if (settled && elapsed - _quietSince > _settle) {
      _ticker.stop();
    }
  }

  /// The ring for this paint: the tracked tile plus the offsets, or where it was while it fades out.
  Rect? _ringForPaint() {
    final target = _tracked == null ? null : _targetRect();
    if (target != null) {
      _painted = Rect.fromLTRB(
        target.left + _offsets[0].value,
        target.top + _offsets[1].value,
        target.right + _offsets[2].value,
        target.bottom + _offsets[3].value,
      );
    }
    return _painted;
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

  @override
  Widget build(BuildContext context) => FocusGlideScope(
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
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (widget.enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  key: Key("focus-glide"),
                  opacity: _tracked == null ? 0 : 1,
                  duration: Motion.focus,
                  curve: Motion.curve,
                  child: CustomPaint(painter: _GlidePainter(this)),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _GlidePainter extends CustomPainter {
  final FocusGlideState glide;

  _GlidePainter(this.glide) : super(repaint: glide._repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final ring = glide._ringForPaint();
    if (ring == null) {
      return;
    }
    canvas.save();
    canvas.translate(ring.left, ring.top);
    FocusRingPainter(style: glide.widget.style, radius: glide._radius).paint(canvas, ring.size);
    canvas.restore();
  }

  // Repaints come from the ticker; a rebuild (style change, focus change) makes a new painter.
  @override
  bool shouldRepaint(_GlidePainter oldDelegate) => true;
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
