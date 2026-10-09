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

import 'package:flauncher/background/diamond_background.dart';
import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/band/band_geometry.dart';
import 'package:flauncher/band/nudge_overlay.dart';
import 'package:flauncher/motion/frame_times.dart';
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/time_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The projected frame: black everywhere except the lit band, inside which the whole app lives. Wrapping the
/// navigator puts every route, dialog and scrim into the band, and gives them the band's size as their screen.
///
/// The lit area and the content are separate layers: the lit area can grow to the full frame (launch) and shrink
/// back (return) while the content keeps its layout and only fades. Idle, the lit area dims or shrinks to a small
/// picture frame with the time.
class BandFrame extends StatefulWidget {
  final BandController controller;
  final Widget child;

  const BandFrame({super.key, required this.controller, required this.child});

  @override
  State<BandFrame> createState() => _BandFrameState();
}

class _BandFrameState extends State<BandFrame> with TickerProviderStateMixin {
  /// The idle picture frame: a small 16:9 panel centred in the band.
  static const Size idleFrameSize = Size(240, 135);
  static const double idleDim = 0.25;

  /// Fraction of the growth by which the launch dim is complete.
  static const double launchDimBy = 0.7;

  late final AnimationController _expansion = AnimationController(
    vsync: this,
    duration: Motion.layout,
    value: widget.controller.expanded ? 1 : 0,
  );
  late final AnimationController _idle = AnimationController(vsync: this, duration: Motion.layout * 2);
  // Takes focus from the app while nudging or idle, so keys reach the band and not the tiles.
  final FocusNode _captureFocus = FocusNode(debugLabel: "band", canRequestFocus: false, skipTraversal: true);
  FocusNode? _focusBeforeCapture;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _expansion.dispose();
    _idle.dispose();
    _captureFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    final target = controller.expanded ? 1.0 : 0.0;
    if (_expansion.value != target || _expansion.isAnimating) {
      if (controller.animateExpansion) {
        _expansion.animateTo(
          target,
          duration: target == 1 ? controller.launchDuration : controller.returnDuration,
          curve: Motion.curve,
        );
      } else {
        _expansion.value = target;
      }
    }
    if (controller.idle) {
      _idle.animateTo(1, curve: Motion.curve);
    } else {
      _idle.animateBack(0, duration: Motion.layout, curve: Motion.curve);
    }
    _updateCapture(controller.nudging || controller.idle);
    setState(() {});
  }

  void _updateCapture(bool capture) {
    if (capture == _captureFocus.canRequestFocus) {
      return;
    }
    if (capture) {
      _focusBeforeCapture = FocusManager.instance.primaryFocus;
      _captureFocus.canRequestFocus = true;
      _captureFocus.requestFocus();
    } else {
      _captureFocus.canRequestFocus = false;
      final previous = _focusBeforeCapture;
      if (previous != null && previous.context != null && previous.canRequestFocus) {
        previous.requestFocus();
      } else {
        _captureFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      }
      _focusBeforeCapture = null;
    }
  }

  KeyEventResult _onCapturedKey(FocusNode node, KeyEvent event) {
    final controller = widget.controller;
    if (controller.idle) {
      // The waking press only wakes; its key up lands on the tile, which ignores a release it never saw pressed.
      if (event is KeyDownEvent) {
        controller.wake();
      }
      return KeyEventResult.handled;
    }
    if (!controller.nudging) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      return KeyEventResult.handled;
    }
    final geometry = controller.geometry;
    final step = BandGeometry.step;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      controller.geometry = geometry.copyWith(height: geometry.height + step);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      controller.geometry = geometry.copyWith(height: geometry.height - step);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      controller.geometry = geometry.copyWith(position: geometry.position - step);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      controller.geometry = geometry.copyWith(position: geometry.position + step);
    } else if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.gameButtonA)) {
      controller.geometry = geometry.nextEdge();
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      controller.stopNudging();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final controller = widget.controller;
      final frame = Offset.zero & constraints.biggest;
      final geometry = controller.geometry;
      final rest = geometry.rect(frame.size);
      controller.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      // Android's "Remove animations"; reported after the frame, since it makes the controller notify.
      final disableAnimations = MediaQuery.disableAnimationsOf(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.systemReducedMotion = disableAnimations);
      return Focus(
        focusNode: _captureFocus,
        onKeyEvent: _onCapturedKey,
        child: ColoredBox(
          color: Colors.black,
          child: TweenAnimationBuilder<Rect?>(
            tween: RectTween(end: rest),
            duration: Motion.layout,
            curve: Motion.curve,
            builder: (context, animatedRest, _) {
              final band = animatedRest ?? rest;
              controller.bandRect = band;
              return AnimatedBuilder(
                animation: Listenable.merge([_expansion, _idle]),
                builder: (context, _) => _layers(context, frame, band, geometry),
              );
            },
          ),
        ),
      );
    },
  );

  Widget _layers(BuildContext context, Rect frame, Rect band, BandGeometry geometry) {
    final controller = widget.controller;
    final t = _expansion.value;
    final idle = _idle.value;
    final toFrame = controller.idleMode == IdleMode.frame ? idle : 0.0;
    final idleLevel = controller.idleMode == IdleMode.dim ? 1 - (1 - idleDim) * idle : 1.0;
    // Growing toward an app the lit frame darkens, so the app cuts in from near black instead of from a lit frame;
    // coming back it starts dark and brightens as it settles into the band.
    final launchLevel = 1 - controller.tuning[Tune.launchDim] * Interval(0, launchDimBy).transform(t);
    final dim = idleLevel * launchLevel;
    final idleRect = Rect.fromCenter(center: band.center, width: idleFrameSize.width, height: idleFrameSize.height);
    final lit = Rect.lerp(Rect.lerp(band, frame, t)!, idleRect, toFrame)!;
    final radius = geometry.cornerRadius * (1 - t) * (1 - toFrame) + BandGeometry.insetRadius * toFrame;
    final mediaQuery = MediaQuery.of(context);
    final contentOpacity = (1 - toFrame) * (1 - Interval(0, 0.6).transform(t));
    // With the content faded out only the background is lit, and it dims in its own paint; an Opacity over the
    // whole frame costs the GPU a full-frame offscreen pass, the most expensive part of a launch or return frame.
    final backgroundDim = contentOpacity > 0 ? 1.0 : dim;
    return Opacity(
      opacity: contentOpacity > 0 ? dim : 1,
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: lit,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: _SoftEdges(
                fade: geometry.edge == BandEdge.soft ? BandGeometry.softFade * (1 - t) * (1 - toFrame) : 0,
                fadeTop: lit.top > frame.top,
                fadeBottom: lit.bottom < frame.bottom,
                child: Consumer<WallpaperService>(
                  builder: (_, wallpaper, _) => _background(wallpaper.wallpaperBytes, backgroundDim),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: band,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(geometry.cornerRadius),
              // While the lit area is larger than the band (launching, or settling back after an app), the content
              // stays out and comes in over the last part of the return.
              // One opacity layer for both fades; nested, each would take its own offscreen pass.
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: controller.contentVisible ? 1 : 0),
                duration: controller.contentVisible ? Motion.layout : Motion.focus,
                curve: Motion.curve,
                builder: (context, visible, child) => Opacity(opacity: contentOpacity * visible, child: child),
                child: MediaQuery(
                  data: mediaQuery.copyWith(
                    size: band.size,
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: BandScope(controller: controller, child: widget.child),
                ),
              ),
            ),
          ),
          if (toFrame > 0)
            Positioned.fromRect(
              rect: idleRect,
              child: Opacity(
                opacity: Interval(0.5, 1).transform(toFrame),
                child: Center(child: TimeWidget(key: Key("idle-clock"), large: true)),
              ),
            ),
          if (controller.frameTimes) Positioned(left: frame.left, top: frame.top, child: FrameTimes()),
          if (controller.nudging)
            Positioned.fill(
              child: NudgeOverlay(controller: controller, band: band),
            ),
        ],
      ),
    );
  }

  Widget _background(Uint8List? wallpaperImage, double dim) => wallpaperImage != null
      ? CustomPaint(
          foregroundPainter: _Veil(dim),
          child: Image.memory(wallpaperImage, key: Key("background"), fit: BoxFit.cover),
        )
      : widget.controller.background == BackgroundMode.diamonds
      ? DiamondBackground(key: Key("background"), band: widget.controller, dim: dim)
      : CustomPaint(
          foregroundPainter: _Veil(dim),
          child: ThemedBackground(key: Key("background")),
        );
}

/// Darkens what is below it toward black, to [dim] of its brightness.
class _Veil extends CustomPainter {
  final double dim;

  const _Veil(this.dim);

  @override
  void paint(Canvas canvas, Size size) {
    if (dim < 1) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 1 - dim));
    }
  }

  @override
  bool shouldRepaint(_Veil oldDelegate) => oldDelegate.dim != dim;
}

/// Fades [child] to transparent (so to the black behind it) over [fade] pixels at the chosen edges.
class _SoftEdges extends StatelessWidget {
  final double fade;
  final bool fadeTop;
  final bool fadeBottom;
  final Widget child;

  const _SoftEdges({required this.fade, required this.fadeTop, required this.fadeBottom, required this.child});

  @override
  Widget build(BuildContext context) {
    if (fade <= 0 || (!fadeTop && !fadeBottom)) {
      return child;
    }
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final f = (fade / bounds.height).clamp(0.0, 0.5);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fadeTop ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            fadeBottom ? Colors.transparent : Colors.white,
          ],
          stops: [0, f, 1 - f, 1],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
