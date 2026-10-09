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

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The band's background: a flat ground with a grid of squares that grow into diamonds under a spotlight behind
/// the focused tile (`shaders/diamonds.frag`).
///
/// The spotlight's x springs toward the focused tile, its y and width follow the tile; a pulse on every landing
/// widens and brightens it; the light colour eases between warm and the app's hue. A ticker runs only while any of
/// that moves. The ambient shimmer is redrawn by a timer at [Tune.ambientFps] instead, so a still home screen
/// redraws the background a few dozen times a second and nothing else.
class DiamondBackground extends StatefulWidget {
  final BandController band;

  /// Brightness, 1 for full.
  final double dim;

  const DiamondBackground({super.key, required this.band, this.dim = 1});

  /// The ground and the colour of an unlit diamond, one step lighter.
  static const Color ground = Palette.bgBottom;
  static final Color base = _lighter(ground, 0.18);

  static Color _lighter(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  @override
  State<DiamondBackground> createState() => _DiamondBackgroundState();
}

class _DiamondBackgroundState extends State<DiamondBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static Future<List<ui.FragmentProgram>>? _programs;

  // Plan values: velocity kept at 0.0009^dt, pulse decays as 0.18^dt, warm light steps scaled by 0.82.
  static const double _spotDrag = 0.0009;
  static const double _pulseDecay = 0.18;
  static const double _warmScale = 0.82;
  // Fraction of the way the light colour moves per 60 Hz frame.
  static const double _colourEase = 0.04;

  ui.FragmentShader? _shader;
  ui.FragmentShader? _lightShader;
  // The light of every cell for the current frame, one pixel per cell; the previous frame's is disposed.
  ui.Image? _cells;
  late final Ticker _ticker = createTicker(_tick);
  final _Repaint _repaint = _Repaint();
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _ambient;
  double _ambientFps = -1;
  int _landings = 0;
  Duration _lastTick = Duration.zero;

  // Spotlight in device pixels of this widget.
  double? _x;
  double _vx = 0;
  double _y = 0;
  double _tileW = 0;
  double _pulse = 0;
  Color _light = Palette.brass;
  double _scale = _warmScale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _programs ??= Future.wait([
      ui.FragmentProgram.fromAsset("shaders/diamonds.frag"),
      ui.FragmentProgram.fromAsset("shaders/diamond_light.frag"),
    ]);
    _programs!.then((programs) {
      if (mounted) {
        setState(() {
          _shader = programs[0].fragmentShader();
          _lightShader = programs[1].fragmentShader();
        });
      }
    }, onError: (Object e) => debugPrint("diamonds shader not loaded: $e"));
    widget.band.spotlight.addListener(_onSpotlight);
    widget.band.addListener(_onBand);
    widget.band.panel.addListener(_repaint.ping);
    _onBand();
    _onSpotlight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.band.spotlight.removeListener(_onSpotlight);
    widget.band.removeListener(_onBand);
    widget.band.panel.removeListener(_repaint.ping);
    _ticker.dispose();
    _ambient?.cancel();
    _shader?.dispose();
    _lightShader?.dispose();
    _cells?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // Rebuilt with the band's frame, which moves and resizes this widget under the tile while it grows toward an app
  // or shrinks back into the band, so the light is measured again.
  @override
  void didUpdateWidget(DiamondBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _wake();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartAmbient();
    } else {
      _ambient?.cancel();
      _ambient = null;
    }
  }

  void _onSpotlight() {
    final spotlight = widget.band.spotlight;
    if (spotlight.landings != _landings) {
      _landings = spotlight.landings;
      // Behind a panel the launcher is paused: the light moves but does not pulse; reduced motion never pulses.
      if (!widget.band.panelOpen.value && !widget.band.reducedMotion) {
        _pulse = 1;
      }
    }
    _wake();
  }

  void _onBand() {
    final fps = widget.band.reducedMotion ? 0.0 : widget.band.tuning[Tune.ambientFps];
    if (fps != _ambientFps) {
      _ambientFps = fps;
      _restartAmbient();
    }
    _wake();
  }

  void _restartAmbient() {
    _ambient?.cancel();
    _ambient = null;
    if (_ambientFps > 0) {
      _ambient = Timer.periodic(Duration(microseconds: (1e6 / _ambientFps).round()), (_) {
        if (!_ticker.isActive) {
          _repaint.ping();
        }
      });
    }
  }

  void _wake() {
    if (!_ticker.isActive && mounted) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  Color get _targetLight {
    final hue = widget.band.spotlight.hue;
    if (widget.band.lightMode == LightMode.app && hue != null) {
      return HSLColor.fromAHSL(1, hue, 0.78, 0.68).toColor();
    }
    return Palette.brass;
  }

  double get _targetScale =>
      widget.band.lightMode == LightMode.app && widget.band.spotlight.hue != null ? 1 : _warmScale;

  void _tick(Duration elapsed) {
    final dt = elapsed == Duration.zero ? 1 / 60 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final target = _measureTile();
    var settled = true;
    if (target != null) {
      final tx = target.center.dx;
      settled = (target.center.dy - _y).abs() < 0.5 && (target.width - _tileW).abs() < 0.5;
      _y = target.center.dy;
      _tileW = target.width;
      // Reduced motion: the light jumps to the tile and is drawn once.
      if (_x == null || widget.band.reducedMotion) {
        _x = tx;
        _vx = 0;
      } else {
        _vx += (tx - _x!) * widget.band.tuning[Tune.spotStiffness] * dt;
        _vx *= pow(_spotDrag, dt);
        _x = _x! + _vx * dt;
      }
    }
    _pulse *= pow(_pulseDecay, dt);
    final ease = 1 - pow(1 - _colourEase, dt * 60).toDouble();
    _light = Color.lerp(_light, _targetLight, ease)!;
    _scale += (_targetScale - _scale) * ease;
    _repaint.ping();
    final still =
        (target == null || (settled && (target.center.dx - _x!).abs() < 0.5 && _vx.abs() < 1)) &&
        _pulse < 0.02 &&
        _colourDistance(_light, _targetLight) < 0.004 &&
        (_scale - _targetScale).abs() < 0.002;
    if (still) {
      _pulse = 0;
      _light = _targetLight;
      _scale = _targetScale;
      _ticker.stop();
    }
  }

  static double _colourDistance(Color a, Color b) => max((a.r - b.r).abs(), max((a.g - b.g).abs(), (a.b - b.b).abs()));

  /// The focused tile in device pixels of this widget, as drawn (lift, scale and scroll included).
  Rect? _measureTile() {
    final tile = widget.band.spotlight.tile;
    final own = context.findRenderObject() as RenderBox?;
    final box = tile != null && tile.mounted ? tile.findRenderObject() as RenderBox? : null;
    if (own == null || box == null || !own.attached || !box.attached || !box.hasSize || !own.hasSize) {
      return null;
    }
    final global = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    final local = global.shift(-own.localToGlobal(Offset.zero));
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Rect.fromLTRB(local.left * dpr, local.top * dpr, local.right * dpr, local.bottom * dpr);
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: Key("diamonds"),
      painter: _DiamondPainter(this, _shader, _lightShader, MediaQuery.devicePixelRatioOf(context), widget.dim),
      child: SizedBox.expand(),
    ),
  );
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _DiamondPainter extends CustomPainter {
  final _DiamondBackgroundState state;
  final ui.FragmentShader? shader;
  final ui.FragmentShader? lightShader;
  final double dpr;
  final double dim;

  _DiamondPainter(this.state, this.shader, this.lightShader, this.dpr, this.dim) : super(repaint: state._repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shader = this.shader;
    final lightShader = this.lightShader;
    if (shader == null || lightShader == null || size.isEmpty) {
      canvas.drawRect(rect, Paint()..color = Color.lerp(Colors.black, DiamondBackground.ground, dim)!);
      return;
    }
    final tuning = state.widget.band.tuning;
    // Before the first focus: a quiet light in the middle of the band.
    final x = state._x ?? size.width * dpr / 2;
    final y = state._x == null ? size.height * dpr * 0.6 : state._y;
    final tileW = state._tileW > 0 ? state._tileW : size.width * dpr * 0.17;
    final grid = tuning[Tune.grid];
    final columns = (size.width * dpr / grid).ceil();
    final rows = (size.height * dpr / grid).ceil();

    // The light of each cell, rendered once per cell into a columns × rows image.
    var i = 0;
    void setLight(double value) => lightShader.setFloat(i++, value);
    setLight(x);
    setLight(y);
    setLight(tileW);
    setLight(state._pulse);
    // Behind an open panel the light dims, following the panel's slide.
    final panel = Motion.sheenCurve.transform(state.widget.band.panel.value.clamp(0.0, 1.0));
    setLight(tuning[Tune.lightStrength] * (1 - (1 - tuning[Tune.panelLight]) * panel));
    setLight(state._clock.elapsedMicroseconds / 1e6);
    setLight(grid);
    setLight(state._ambientFps > 0 ? 1 : 0);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, columns.toDouble(), rows.toDouble()), Paint()..shader = lightShader);
    final picture = recorder.endRecording();
    final cells = picture.toImageSync(columns, rows);
    picture.dispose();
    state._cells?.dispose();
    state._cells = cells;

    i = 0;
    void set(double value) => shader.setFloat(i++, value);
    void colour(Color c) {
      set(c.r);
      set(c.g);
      set(c.b);
    }

    set(dpr);
    set(grid);
    set(columns.toDouble());
    set(rows.toDouble());
    set(state._scale);
    colour(DiamondBackground.ground);
    colour(DiamondBackground.base);
    colour(state._light);
    set(dim);
    shader.setImageSampler(0, cells);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_DiamondPainter oldDelegate) =>
      oldDelegate.dpr != dpr || oldDelegate.shader != shader || oldDelegate.dim != dim;
}
