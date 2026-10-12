/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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
import 'dart:ui';

import 'package:tvlauncher/actions.dart';
import 'package:tvlauncher/band/band_controller.dart';
import 'package:tvlauncher/motion/tuning.dart';
import 'package:tvlauncher/sound/ui_sounds.dart';
import 'package:tvlauncher/theme.dart';
import 'package:tvlauncher/widgets/focus_glide.dart';
import 'package:tvlauncher/widgets/panel_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens [builder]'s panel over the home screen behind the panel scrim. The panel slides in from the right edge
/// while the band (when there is one) learns how far it is open, so the launcher behind can scale and dim with it.
Future<T?> showPanel<T>(BuildContext context, WidgetBuilder builder) async {
  final band = BandScope.maybeOf(context);
  final tuning = band?.tuning ?? Tuning.defaults;
  band?.panelOpen.value = true;
  final sounds = UiSounds.maybeOf(context)?..panel(open: true);
  try {
    return await Navigator.of(context).push(
      _PanelRoute<T>(
        builder: builder,
        band: band,
        enter: Duration(milliseconds: tuning[Tune.panelIn].round()),
        exit: Duration(milliseconds: tuning[Tune.panelOut].round()),
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ),
    );
  } finally {
    band?.panelOpen.value = false;
    sounds?.panel(open: false);
  }
}

class _PanelRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final BandController? band;
  final Duration enter;
  final Duration exit;

  _PanelRoute({required this.builder, required this.band, required this.enter, required this.exit, this.barrierLabel});

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => Palette.scrim;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => enter;

  @override
  Duration get reverseTransitionDuration => exit;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  TickerFuture didPush() {
    animation!.addListener(_report);
    return super.didPush();
  }

  void _report() => band?.panel.value = animation!.value;

  @override
  void dispose() {
    animation?.removeListener(_report);
    band?.panel.value = 0;
    super.dispose();
  }
}

/// A panel docked to the right edge: 38 % of the screen wide, on the surface colour with a hairline toward the
/// home screen. It slides in by more than its own width on the polish plan's curve and out faster on the same
/// curve; its rows and header rise in one after another ([PanelStagger]). Left, toward the launcher, acts as Back.
class RightPanelDialog extends StatelessWidget {
  static const double widthFraction = 0.38;
  static const double minWidth = 210;
  static const double padding = 24;
  static const double surfaceOpacity = 0.92;

  final Widget child;

  const RightPanelDialog({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final band = BandScope.maybeOf(context);
    final tuning = band?.tuning ?? Tuning.defaults;
    final reduced = band?.reducedMotion ?? false;
    final animation = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    final blur = tuning[Tune.panelBlur];
    final width = max(minWidth, MediaQuery.sizeOf(context).width * widthFraction);
    Widget panel = Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Palette.surface.withValues(alpha: surfaceOpacity),
        border: Border(left: BorderSide(color: Palette.line)),
      ),
      width: width,
      child: Actions(
        actions: {BackIntent: BackAction(context)},
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: PanelStagger(
            stagger: Duration(milliseconds: tuning[Tune.rowStagger].round()),
            rise: reduced ? Duration.zero : Duration(milliseconds: tuning[Tune.panelIn].round()),
            // One highlight slides between the rows on the focus spring.
            child: FocusGlide(
              enabled: true,
              highlight: true,
              radius: Shapes.rowRadius,
              spring: () => band?.focusSpring ?? tuning.focusSpring,
              child: child,
            ),
          ),
        ),
      ),
    );
    if (blur > 0) {
      panel = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: panel,
        ),
      );
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.centerRight,
        // Reduced motion: the panel fades in place instead of sliding.
        child: reduced
            ? FadeTransition(opacity: animation, child: panel)
            : SlideTransition(
                position: Tween(begin: Offset(1.05, 0), end: Offset.zero).animate(
                  CurvedAnimation(parent: animation, curve: Motion.sheenCurve, reverseCurve: Motion.sheenCurve.flipped),
                ),
                child: panel,
              ),
      ),
    );
  }
}
