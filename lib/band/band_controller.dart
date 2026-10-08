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

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/band/band_geometry.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Builds made with `--dart-define=TUNING=true` carry the nudge mode and the launch/return switcher, and remember
/// what was picked in a file. Release builds use the constants below and touch no file.
const bool tuningBuild = bool.fromEnvironment("TUNING");

/// How an app comes up when its tile is selected.
enum LaunchMode {
  /// The system's default activity transition.
  system("System default"),

  /// The app's window scales up from the selected tile.
  scaleTile("Scale up from tile"),

  /// The app's window scales up from the whole band, so the band seems to grow into the app.
  scaleBand("Scale up from band"),

  /// The band grows to the full frame, then the app cuts in.
  growCut("Band grows, cut"),

  /// The band grows to the full frame, then the app fades in.
  growFade("Band grows, fade");

  final String label;

  const LaunchMode(this.label);
}

/// What the launcher plays when it comes back from an app.
enum ReturnMode {
  /// Nothing of its own: the system's transition only.
  system("System default"),

  /// The lit area shrinks from the full frame back into the band, then the content fades in.
  collapse("Band collapses"),

  /// The content fades in inside the band.
  fade("Content fades in");

  final String label;

  const ReturnMode(this.label);
}

/// The band's state: its geometry, the launch and return choreography, and the nudge mode of tuning builds.
///
/// [expanded] drives the lit area between the band (false) and the full frame (true); [animateExpansion] says
/// whether the frame should animate there or jump.
class BandController extends ChangeNotifier with WidgetsBindingObserver {
  /// Release choices; tuning builds start from these and then follow the file.
  static const LaunchMode releaseLaunchMode = LaunchMode.system;
  static const ReturnMode releaseReturnMode = ReturnMode.system;
  static const bool releaseFocusGlide = true;

  final bool tuning;
  final Future<File> Function()? _tuningFile;

  BandGeometry _geometry = BandGeometry.release;
  LaunchMode _launchMode = releaseLaunchMode;
  ReturnMode _returnMode = releaseReturnMode;
  bool _focusGlide = releaseFocusGlide;
  bool _nudging = false;
  bool _expanded = false;
  bool _contentVisible = true;
  bool _animateExpansion = false;
  bool _launchedApp = false;

  /// The band's resting rectangle and the screen's pixel ratio, kept current by the frame that draws it.
  Rect bandRect = Rect.zero;
  double devicePixelRatio = 1;

  BandController({this.tuning = tuningBuild, Future<File> Function()? tuningFile})
    : _tuningFile = tuningFile ?? (tuning ? _defaultTuningFile : null) {
    WidgetsBinding.instance.addObserver(this);
    if (tuning) {
      _load();
    }
  }

  BandGeometry get geometry => _geometry;

  LaunchMode get launchMode => _launchMode;

  ReturnMode get returnMode => _returnMode;

  bool get focusGlide => _focusGlide;

  bool get nudging => _nudging;

  bool get expanded => _expanded;

  bool get contentVisible => _contentVisible;

  bool get animateExpansion => _animateExpansion;

  set geometry(BandGeometry value) => _update(() => _geometry = value);

  set launchMode(LaunchMode value) => _update(() => _launchMode = value);

  set returnMode(ReturnMode value) => _update(() => _returnMode = value);

  set focusGlide(bool value) => _update(() => _focusGlide = value);

  void startNudging() {
    _nudging = true;
    notifyListeners();
  }

  void stopNudging() {
    _nudging = false;
    notifyListeners();
  }

  /// Starts [app] with the current [launchMode]. [tileRect] is the tile's rectangle in logical pixels of the
  /// screen, when the launch came from a tile.
  Future<void> launch(AppsService apps, App app, Rect? tileRect) async {
    _launchedApp = true;
    switch (_launchMode) {
      case LaunchMode.system:
        await apps.launchApp(app);
      case LaunchMode.scaleTile:
        await apps.launchApp(
          app,
          tileRect == null ? LaunchTransition.system : LaunchTransition.scaleUp(_physical(tileRect)),
        );
      case LaunchMode.scaleBand:
        await apps.launchApp(app, LaunchTransition.scaleUp(_physical(bandRect)));
      case LaunchMode.growCut:
      case LaunchMode.growFade:
        // Apps take 300-400 ms to show their first frame (measured on the device), about as long as the growth, so
        // both start together; waiting for the growth first leaves the full frame lit and empty for that long.
        _setExpansion(expanded: true, contentVisible: false, animate: true);
        await apps.launchApp(app, _launchMode == LaunchMode.growCut ? LaunchTransition.none : LaunchTransition.fade);
    }
  }

  // Hidden behind an app, the band takes the pose the return animation starts from, so the first frame shown on
  // the way back is already right. Coming back, it plays the return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden && _launchedApp) {
      switch (_returnMode) {
        case ReturnMode.system:
          _setExpansion(expanded: false, contentVisible: true, animate: false);
        case ReturnMode.collapse:
          _setExpansion(expanded: true, contentVisible: false, animate: false);
        case ReturnMode.fade:
          _setExpansion(expanded: false, contentVisible: false, animate: false);
      }
    } else if (state == AppLifecycleState.resumed && _launchedApp) {
      _launchedApp = false;
      _setExpansion(expanded: false, contentVisible: true, animate: _returnMode != ReturnMode.system);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _setExpansion({required bool expanded, required bool contentVisible, required bool animate}) {
    _expanded = expanded;
    _contentVisible = contentVisible;
    _animateExpansion = animate;
    notifyListeners();
  }

  Rect _physical(Rect logical) => Rect.fromLTRB(
    logical.left * devicePixelRatio,
    logical.top * devicePixelRatio,
    logical.right * devicePixelRatio,
    logical.bottom * devicePixelRatio,
  );

  void _update(VoidCallback change) {
    change();
    notifyListeners();
    if (tuning) {
      _save();
    }
  }

  static Future<File> _defaultTuningFile() async =>
      File("${(await getApplicationSupportDirectory()).path}/band_tuning.json");

  Future<void> _load() async {
    try {
      final file = await _tuningFile!();
      if (!await file.exists()) {
        return;
      }
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _geometry = BandGeometry.fromJson(json);
      _launchMode = LaunchMode.values.where((m) => m.name == json["launch"]).firstOrNull ?? _launchMode;
      _returnMode = ReturnMode.values.where((m) => m.name == json["return"]).firstOrNull ?? _returnMode;
      _focusGlide = json["focusGlide"] as bool? ?? _focusGlide;
      notifyListeners();
    } catch (e) {
      debugPrint("band tuning not loaded: $e");
    }
  }

  Future<void> _save() async {
    try {
      final file = await _tuningFile!();
      await file.writeAsString(
        jsonEncode({
          ..._geometry.toJson(),
          "launch": _launchMode.name,
          "return": _returnMode.name,
          "focusGlide": _focusGlide,
        }),
      );
    } catch (e) {
      debugPrint("band tuning not saved: $e");
    }
  }
}

/// Makes the [BandController] reachable from tiles without requiring it: widgets pumped on their own (tests,
/// panels) simply launch with the system transition.
class BandScope extends InheritedNotifier<BandController> {
  const BandScope({super.key, required BandController controller, required super.child}) : super(notifier: controller);

  static BandController? maybeOf(BuildContext context, {bool listen = false}) => listen
      ? context.dependOnInheritedWidgetOfExactType<BandScope>()?.notifier
      : context.getInheritedWidgetOfExactType<BandScope>()?.notifier;
}
