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

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/band/band_geometry.dart';
import 'package:flauncher/band/nudge_overlay.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The projected frame: black everywhere except the lit band, inside which the whole app lives. Wrapping the
/// navigator puts every route, dialog and scrim into the band, and gives them the band's size as their screen.
///
/// The lit area and the content are separate layers: the lit area can grow to the full frame (launch) and shrink
/// back (return) while the content keeps its layout and only fades.
class BandFrame extends StatefulWidget {
  final BandController controller;
  final Widget child;

  const BandFrame({super.key, required this.controller, required this.child});

  @override
  State<BandFrame> createState() => _BandFrameState();
}

class _BandFrameState extends State<BandFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _expansion = AnimationController(
    vsync: this,
    duration: Motion.layout,
    value: widget.controller.expanded ? 1 : 0,
  );
  final FocusNode _nudgeFocus = FocusNode(debugLabel: "nudge", canRequestFocus: false, skipTraversal: true);
  FocusNode? _focusBeforeNudge;
  bool _wasNudging = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _expansion.dispose();
    _nudgeFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    final target = controller.expanded ? 1.0 : 0.0;
    if (_expansion.value != target || _expansion.isAnimating) {
      if (controller.animateExpansion) {
        _expansion.animateTo(target, curve: Motion.curve);
      } else {
        _expansion.value = target;
      }
    }
    if (controller.nudging != _wasNudging) {
      _wasNudging = controller.nudging;
      if (controller.nudging) {
        // Taking focus away from the tiles pauses their navigation; the arrows go to the nudge mode instead.
        _focusBeforeNudge = FocusManager.instance.primaryFocus;
        _nudgeFocus.canRequestFocus = true;
        _nudgeFocus.requestFocus();
      } else {
        _nudgeFocus.canRequestFocus = false;
        final previous = _focusBeforeNudge;
        if (previous != null && previous.context != null && previous.canRequestFocus) {
          previous.requestFocus();
        } else {
          _nudgeFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
        }
        _focusBeforeNudge = null;
      }
    }
    setState(() {});
  }

  KeyEventResult _onNudgeKey(FocusNode node, KeyEvent event) {
    final controller = widget.controller;
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
      return Focus(
        focusNode: _nudgeFocus,
        onKeyEvent: _onNudgeKey,
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
                animation: _expansion,
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
    final lit = Rect.lerp(band, frame, t)!;
    final radius = geometry.cornerRadius * (1 - t);
    final mediaQuery = MediaQuery.of(context);
    return Stack(
      children: [
        Positioned.fromRect(
          rect: lit,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: _SoftEdges(
              fade: geometry.edge == BandEdge.soft ? BandGeometry.softFade * (1 - t) : 0,
              fadeTop: lit.top > frame.top,
              fadeBottom: lit.bottom < frame.bottom,
              child: Consumer<WallpaperService>(builder: (_, wallpaper, _) => _background(wallpaper.wallpaperBytes)),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: band,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(geometry.cornerRadius),
            child: AnimatedOpacity(
              opacity: controller.contentVisible ? 1 : 0,
              duration: controller.contentVisible ? Motion.layout : Motion.focus,
              curve: Motion.curve,
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
        if (controller.nudging)
          Positioned.fill(
            child: NudgeOverlay(controller: controller, band: band),
          ),
      ],
    );
  }

  Widget _background(Uint8List? wallpaperImage) => wallpaperImage != null
      ? Image.memory(wallpaperImage, key: Key("background"), fit: BoxFit.cover)
      : ThemedBackground(key: Key("background"));
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
