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

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/motion/edge_nudge.dart';
import 'package:flauncher/motion/spring.dart';
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/focus_glide.dart';
import 'package:flauncher/widgets/focus_ring.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/right_panel_dialog.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _validationKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

/// One app tile. Hero tiles can be moved left/right; grid tiles are alphabetical and never move.
class AppCard extends StatefulWidget {
  final App application;
  final bool inHero;
  final bool autofocus;
  final void Function(AxisDirection)? onMove;
  final VoidCallback? onMoveEnd;

  AppCard({
    super.key,
    required this.application,
    required this.inHero,
    required this.autofocus,
    this.onMove,
    this.onMoveEnd,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin {
  // Tiles pumped without a band (tests, panels) use the defaults.
  static final Tuning _defaultTuning = Tuning();
  static const Duration _sheenDelay = Duration(milliseconds: 50);

  bool _moving = false;
  bool _pressed = false;
  late final AnimationController _sheen = AnimationController(vsync: this);
  MemoryImage? _imageProvider;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _tileKey = GlobalKey();
  FocusGlideState? _glide;
  BuildContext? _reportedTile;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _glide = FocusGlideScope.maybeOf(context);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    final reported = _reportedTile;
    if (reported != null) {
      _glide?.release(reported);
    }
    _focusNode.dispose();
    _sheen.dispose();
    super.dispose();
  }

  Tuning get _tuning => BandScope.maybeOf(context)?.tuning ?? _defaultTuning;

  // Losing focus while moving (Home, Back, a hovering pointer) drops the tile where it is, so the order in memory
  // never silently diverges from the one persisted.
  void _onFocusChange() {
    if (!_focusNode.hasFocus && _moving) {
      _endMove();
    }
    final tile = _tileKey.currentContext;
    if (_focusNode.hasFocus) {
      _startSheen();
    } else {
      _sheen.value = 0;
      if (_pressed) {
        setState(() => _pressed = false);
      }
    }
    if (tile != null && _focusNode.hasFocus) {
      _reportedTile = tile;
      _glide?.track(tile);
    } else if (_reportedTile != null) {
      _glide?.release(_reportedTile!);
      _reportedTile = null;
    }
  }

  // Once per focus, never while a held key runs along the row.
  void _startSheen() {
    final tuning = _tuning;
    if (tuning[Tune.sheen] <= 0 || (BandScope.maybeOf(context)?.holding ?? false)) {
      return;
    }
    _sheen.duration = tuning.sheenDuration + _sheenDelay;
    _sheen.forward(from: 0);
  }

  // A focused tile that is rebuilt may have moved (reordered, resized with the band): let the ring follow.
  @override
  void didUpdateWidget(AppCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus) {
      _glide?.kick();
    }
  }

  ImageProvider _cachedMemoryImage(Uint8List bytes) {
    if (!listEquals(bytes, _imageProvider?.bytes)) {
      _imageProvider = MemoryImage(bytes);
    }
    return _imageProvider!;
  }

  @override
  Widget build(BuildContext context) => FocusKeyboardListener(
    onPressed: (key) => _onPressed(context, key),
    onLongPress: (key) => _onLongPress(context, key),
    onVeryLongPress: (key) => _onVeryLongPress(context),
    onPressChanged: (pressed) => setState(() => _pressed = pressed),
    builder: (context) {
      final band = BandScope.maybeOf(context, listen: true);
      final tuning = band?.tuning ?? _defaultTuning;
      final focused = Focus.of(context).hasFocus;
      final focusSpring = band?.focusSpring ?? tuning.focusSpring;
      SpringSpec towards(bool on) => on ? focusSpring : tuning.focusOutSpring;
      final raised = focused && !_moving;
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: EdgeNudge(
          distance: tuning[Tune.nudge],
          duration: tuning.nudgeDuration,
          child: SpringBuilder(
            value: raised ? 1 : 0,
            spec: towards(raised),
            builder: (context, raise, _) => SpringBuilder(
              value: _pressed ? tuning[Tune.pressScale] : 1,
              spec: _pressed ? tuning.pressDownSpring : tuning.pressUpSpring,
              builder: (context, press, _) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.translationValues(0, -tuning[Tune.lift] * raise, 0)
                  ..scaleByDouble(
                    (1 + (tuning[Tune.focusScale] - 1) * raise) * press,
                    (1 + (tuning[Tune.focusScale] - 1) * raise) * press,
                    1,
                    1,
                  ),
                child: SpringBuilder(
                  value: focused ? 1 : 0,
                  spec: towards(focused),
                  builder: (context, light, _) => _tile(context, band, tuning, focused, light.clamp(0.0, 1.0)),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  // [light] runs from 0 (unfocused: dimmed and desaturated) to 1 (focused: full colour).
  Widget _tile(BuildContext context, BandController? band, Tuning tuning, bool focused, double light) => CustomPaint(
    // With a glide, the home screen draws one ring that travels between tiles instead.
    foregroundPainter: focused && _glide == null
        ? FocusRingPainter(style: band?.ringStyle ?? RingStyle(), radius: Shapes.tileRadius)
        : null,
    child: Material(
      key: _tileKey,
      color: Palette.surface,
      borderRadius: BorderRadius.circular(Shapes.tileRadius),
      clipBehavior: Clip.antiAlias,
      elevation: focused ? 16 : 0,
      shadowColor: Palette.shadow,
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            autofocus: widget.autofocus,
            focusNode: _focusNode,
            focusColor: Colors.transparent,
            onTap: () => _onTap(context),
            onHover: _onHover,
            onLongPress: () => _onLongPress(context, null),
            child: widget.application.banner != null
                ? Ink.image(
                    image: _cachedMemoryImage(widget.application.banner!),
                    fit: BoxFit.cover,
                    colorFilter: _dimFilter(tuning, light),
                  )
                : _iconWithName(context),
          ),
          if (_moving) ..._arrows(),
          // Icon tiles have no image to filter; they only darken.
          if (widget.application.banner == null && light < 1)
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: (1 - tuning[Tune.dimBrightness]) * (1 - light))),
            ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _sheen,
              builder: (context, _) => _sheen.value == 0 || _sheen.value == 1
                  ? SizedBox()
                  : CustomPaint(
                      key: Key("sheen"),
                      painter: _SheenPainter(
                        progress: Interval(
                          _sheenDelay.inMicroseconds / _sheen.duration!.inMicroseconds,
                          1,
                          curve: Motion.sheenCurve,
                        ).transform(_sheen.value),
                        opacity: tuning[Tune.sheen],
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );

  /// Brightness and saturation lowered by [1 - light]; none at full light, so a focused tile is drawn unfiltered.
  static ColorFilter? _dimFilter(Tuning tuning, double light) {
    if (light >= 0.999) {
      return null;
    }
    final b = 1 - (1 - tuning[Tune.dimBrightness]) * (1 - light);
    final s = 1 - (1 - tuning[Tune.dimSaturation]) * (1 - light);
    // Rec. 709 luma weights.
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    List<double> row(int channel) => [
      b * (lr * (1 - s) + (channel == 0 ? s : 0)),
      b * (lg * (1 - s) + (channel == 1 ? s : 0)),
      b * (lb * (1 - s) + (channel == 2 ? s : 0)),
      0,
      0,
    ];
    return ColorFilter.matrix([...row(0), ...row(1), ...row(2), 0, 0, 0, 1, 0]);
  }

  Widget _iconWithName(BuildContext context) => Padding(
    padding: EdgeInsets.all(8),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: widget.application.icon != null
              ? Ink.image(image: _cachedMemoryImage(widget.application.icon!), height: double.infinity)
              : Icon(Icons.android, size: 32),
        ),
        Flexible(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text(
              widget.application.name,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _arrows() => [
    _arrow(Alignment.centerLeft, Icons.keyboard_arrow_left),
    _arrow(Alignment.centerRight, Icons.keyboard_arrow_right),
  ];

  Widget _arrow(Alignment alignment, IconData icon) => Align(
    alignment: alignment,
    child: Padding(
      padding: EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: Palette.brass),
        child: Icon(icon, size: 16, color: Palette.bgBottom),
      ),
    ),
  );

  KeyEventResult _onPressed(BuildContext context, LogicalKeyboardKey? key) {
    if (_moving) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.onMove?.call(AxisDirection.left);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        widget.onMove?.call(AxisDirection.right);
      } else if (_validationKeys.contains(key)) {
        _endMove();
      }
      return KeyEventResult.handled;
    } else if (_validationKeys.contains(key)) {
      _launch(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Pointer / air-mouse support. Hovering a card selects it, mirroring the D-pad focus model that every visual
  // state in build() reads from Focus.of(context).hasFocus. The !_moving guard keeps a stray hover from stealing
  // focus while a card is being repositioned with the D-pad.
  void _onHover(bool hovering) {
    if (hovering && !_moving && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  // A pointer tap is the equivalent of pressing the D-pad select key: launch the app, or drop it in place when
  // reordering. (The keyboard path passes a LogicalKeyboardKey to _onPressed; a tap has no key.)
  void _onTap(BuildContext context) {
    if (_moving) {
      _endMove();
    } else {
      _launch(context);
    }
  }

  // Through the band when there is one, so the launch can open out of this tile; on its own, a plain launch.
  void _launch(BuildContext context) {
    final apps = context.read<AppsService>();
    final band = BandScope.maybeOf(context);
    if (band == null) {
      apps.launchApp(widget.application);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final tileRect = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
    band.launch(apps, widget.application, tileRect);
  }

  void _endMove() {
    setState(() => _moving = false);
    widget.onMoveEnd?.call();
  }

  // Held select on a hero tile starts moving it right away; the panel comes after a longer hold (or a pointer
  // long press, which has no move mode). Grid tiles cannot move, so the hold opens the panel directly.
  KeyEventResult _onLongPress(BuildContext context, LogicalKeyboardKey? key) {
    if (_moving) {
      return KeyEventResult.ignored;
    }
    if (key != null && widget.inHero && widget.onMove != null) {
      setState(() => _moving = true);
    } else {
      _showPanel(context);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onVeryLongPress(BuildContext context) {
    if (_moving) {
      // Nothing was moved yet, so there is no order to save.
      setState(() => _moving = false);
    }
    _showPanel(context);
    return KeyEventResult.handled;
  }

  Future<void> _showPanel(BuildContext context) async {
    final result = await showPanel<ApplicationInfoPanelResult>(
      context,
      (context) => ApplicationInfoPanel(application: widget.application, inHero: widget.inHero),
    );
    if (result == ApplicationInfoPanelResult.reorderApp && widget.onMove != null && mounted) {
      setState(() => _moving = true);
    }
  }
}

/// One diagonal highlight crossing the tile from top left to bottom right as [progress] runs from 0 to 1.
class _SheenPainter extends CustomPainter {
  static const double _halfWidth = 0.16;

  final double progress;
  final double opacity;

  const _SheenPainter({required this.progress, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = -_halfWidth + progress * (1 + 2 * _halfWidth);
    final white = Colors.white.withValues(alpha: opacity);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [white.withValues(alpha: 0), white, white.withValues(alpha: 0)],
      stops: [(centre - _halfWidth).clamp(0.0, 1.0), centre.clamp(0.0, 1.0), (centre + _halfWidth).clamp(0.0, 1.0)],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_SheenPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.opacity != opacity;
}
