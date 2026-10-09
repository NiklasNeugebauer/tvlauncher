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
import 'dart:convert';
import 'dart:io';

import 'package:flauncher/background/spotlight.dart';
import 'package:flauncher/band/band_geometry.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/motion/spring.dart';
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/focus_ring.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

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

/// What the band does after [BandController.idleAfter] without a key press, well before the system screensaver.
enum IdleMode {
  off("Off"),

  /// The band and its content dim.
  dim("Dim"),

  /// The band shrinks to a small picture frame that shows only the time.
  frame("Picture frame");

  final String label;

  const IdleMode(this.label);
}

/// How focus travels between tiles.
enum FocusMotion {
  /// One ring springs from tile to tile and overshoots a little; tiles lift on the same spring.
  spring("spring"),

  /// One ring eases toward the tile without overshoot (v4).
  ease("ease"),

  /// Each tile draws its own ring.
  jump("jump");

  final String label;

  const FocusMotion(this.label);
}

/// What lights the band's background.
enum BackgroundMode {
  /// A grid of squares that grow into diamonds under a spotlight following focus.
  diamonds("Diamonds"),

  /// v3's gradient with a warm glow from below.
  glow("Glow");

  final String label;

  const BackgroundMode(this.label);
}

/// The colour of the diamonds' light.
enum LightMode {
  warm("Warm"),

  /// The focused app's hue; grey banners stay warm.
  app("App colour");

  final String label;

  const LightMode(this.label);
}

/// The focus ring's colour: brass is the state accent; cream is the primary text colour, brighter on the wall.
enum RingColor {
  brass(Palette.brass),
  cream(Palette.cream);

  final Color color;

  const RingColor(this.color);
}

/// The band's state: its geometry, the launch and return choreography, the nudge mode and idle.
///
/// The config lives in a JSON file on the app's external storage, where `adb` can read and replace it without root
/// or a debuggable build. It is read at start and whenever the launcher comes back to the front, and every load and
/// save is logged with the tag `flutter` as `band config ...`. While the launcher is in front the file is checked
/// once a second, so a pushed config applies without a restart.
///
/// [expanded] drives the lit area between the band (false) and the full frame (true); [animateExpansion] says
/// whether the frame should animate there or jump.
class BandController extends ChangeNotifier with WidgetsBindingObserver {
  /// Defaults when the config file has no value.
  static const LaunchMode releaseLaunchMode = LaunchMode.growCut;
  static const ReturnMode releaseReturnMode = ReturnMode.collapse;
  static const FocusMotion releaseFocusMotion = FocusMotion.spring;
  static const IdleMode releaseIdleMode = IdleMode.off;

  /// Where the config is, for logs and docs; the external files directory of the app.
  static const String configPath = "/sdcard/Android/data/dev.neugebauer.tvlauncher/files/band_config.json";

  static const Duration _pollInterval = Duration(seconds: 1);

  final Future<File> Function()? configFile;
  DateTime? _configModified;
  Timer? _pollTimer;
  File? _file;
  bool _missingLogged = false;
  bool _loading = false;

  /// The tunable motion numbers, kept in the config under `tuning`.
  final Tuning tuning = Tuning();

  /// Where the background's light is.
  final Spotlight spotlight = Spotlight();

  /// How far a side panel is open, 0 to 1, following its slide; what is behind it scales and dims with it.
  final ValueNotifier<double> panel = ValueNotifier(0);

  /// A side panel is open (set before its first frame, cleared when it is popped), so a tile that loses focus to
  /// it keeps looking focused.
  final ValueNotifier<bool> panelOpen = ValueNotifier(false);
  final Duration idleAfter;

  BandGeometry _geometry = BandGeometry.release;
  LaunchMode _launchMode = releaseLaunchMode;
  ReturnMode _returnMode = releaseReturnMode;
  FocusMotion _focusMotion = releaseFocusMotion;
  bool _frameTimes = false;
  RingColor _ringColor = RingColor.brass;
  BackgroundMode _background = BackgroundMode.diamonds;
  LightMode _lightMode = LightMode.warm;
  bool _holding = false;
  Duration _launchDuration = Motion.launch;
  Duration _returnDuration = Motion.returnHome;
  bool _nudging = false;
  bool _expanded = false;
  bool _contentVisible = true;
  bool _animateExpansion = false;
  bool _launchedApp = false;
  IdleMode _idleMode = releaseIdleMode;
  bool _idle = false;
  Timer? _idleTimer;

  /// The band's resting rectangle and the screen's pixel ratio, kept current by the frame that draws it.
  Rect bandRect = Rect.zero;
  double devicePixelRatio = 1;

  /// [configFile] locates the config; without one (tests) nothing is read or written.
  BandController({this.configFile, this.idleAfter = const Duration(minutes: 2)}) {
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    tuning.addListener(_onTuningChanged);
    _restartIdleTimer();
    _startPolling();
    _load();
  }

  BandGeometry get geometry => _geometry;

  LaunchMode get launchMode => _launchMode;

  ReturnMode get returnMode => _returnMode;

  FocusMotion get focusMotion => _focusMotion;

  BackgroundMode get background => _background;

  set background(BackgroundMode value) => _update(() => _background = value);

  LightMode get lightMode => _lightMode;

  set lightMode(LightMode value) => _update(() => _lightMode = value);

  RingColor get ringColor => _ringColor;

  set ringColor(RingColor value) => _update(() => _ringColor = value);

  RingStyle get ringStyle => RingStyle(
    color: _ringColor.color,
    gap: tuning[Tune.ringGap],
    halo: tuning[Tune.ringHalo],
    haloWidth: tuning[Tune.ringHaloWidth],
  );

  /// A direction key is held and repeating: focus runs along the row rather than stepping.
  bool get holding => _holding;

  /// The spring for a focus move starting now.
  SpringSpec get focusSpring => _holding ? tuning.holdSpring : tuning.focusSpring;

  /// Whether the frame shows build and raster times.
  bool get frameTimes => _frameTimes;

  /// How long the band takes to grow before an app, and to settle back after one.
  Duration get launchDuration => _launchDuration;

  Duration get returnDuration => _returnDuration;

  set launchDuration(Duration value) => _update(() => _launchDuration = _durationStep(value));

  set returnDuration(Duration value) => _update(() => _returnDuration = _durationStep(value));

  static const Duration durationStep = Duration(milliseconds: 20);

  static Duration _durationStep(Duration value) {
    final steps = (value.inMilliseconds / durationStep.inMilliseconds).round().clamp(5, 150);
    return durationStep * steps;
  }

  bool get nudging => _nudging;

  bool get expanded => _expanded;

  bool get contentVisible => _contentVisible;

  bool get animateExpansion => _animateExpansion;

  IdleMode get idleMode => _idleMode;

  /// Idle and showing it; the next key press only wakes the band.
  bool get idle => _idle;

  set geometry(BandGeometry value) => _update(() => _geometry = value);

  set launchMode(LaunchMode value) => _update(() => _launchMode = value);

  set returnMode(ReturnMode value) => _update(() => _returnMode = value);

  set focusMotion(FocusMotion value) => _update(() => _focusMotion = value);

  set frameTimes(bool value) => _update(() => _frameTimes = value);

  set idleMode(IdleMode value) => _update(() {
    _idleMode = value;
    _restartIdleTimer();
  });

  void wake() {
    if (_idle) {
      _idle = false;
      notifyListeners();
    }
    _restartIdleTimer();
  }

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
        // Apps take 300-400 ms to show their first frame (measured on the device), so the start overlaps the
        // growth and the app lands as it finishes; starting after it leaves the full frame lit and empty.
        _setExpansion(expanded: true, contentVisible: false, animate: true);
        final head = _launchDuration - const Duration(milliseconds: 350);
        await Future.delayed(head.isNegative ? Duration.zero : head);
        await apps.launchApp(app, _launchMode == LaunchMode.growCut ? LaunchTransition.none : LaunchTransition.fade);
    }
  }

  // Hidden behind an app, the band takes the pose the return animation starts from, so the first frame shown on
  // the way back is already right. Coming back, it plays the return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden) {
      // Behind an app, the screensaver or a sleeping display there is nothing to idle; come back awake. The frame
      // must hear about it, or it keeps showing the picture frame and holding focus with nothing left to wake.
      _idleTimer?.cancel();
      _pollTimer?.cancel();
      if (_idle) {
        _idle = false;
        notifyListeners();
      }
    } else if (state == AppLifecycleState.resumed) {
      _restartIdleTimer();
      _startPolling();
      _load();
    }
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

  // Back arrives as a route pop, not a key. While idle it only wakes the band; while nudging it ends the mode.
  // The controller is created before the app's navigator registers, so it is asked first.
  @override
  Future<bool> didPopRoute() async {
    if (_idle) {
      wake();
      return true;
    }
    if (_nudging) {
      stopNudging();
      return true;
    }
    _restartIdleTimer();
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    tuning.removeListener(_onTuningChanged);
    tuning.dispose();
    spotlight.dispose();
    panel.dispose();
    panelOpen.dispose();
    _idleTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  // Watches every key without handling it. While idle the frame takes focus and consumes the waking press itself.
  bool _onKey(KeyEvent event) {
    if (!_idle) {
      _restartIdleTimer();
    }
    if (_directionKeys.contains(event.logicalKey)) {
      if (event is KeyRepeatEvent) {
        _holding = true;
      } else if (event is KeyUpEvent) {
        _holding = false;
      }
    }
    return false;
  }

  static final Set<LogicalKeyboardKey> _directionKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  };

  void _onTuningChanged() {
    notifyListeners();
    if (!_loading) {
      _save();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (configFile != null) {
      _pollTimer = Timer.periodic(_pollInterval, (_) => _load());
    }
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (_idleMode == IdleMode.off) {
      return;
    }
    _idleTimer = Timer(idleAfter, () {
      if (_nudging) {
        _restartIdleTimer();
        return;
      }
      _idle = true;
      notifyListeners();
    });
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
    _save();
  }

  /// The config file in the app's external files directory, moved there from the tuning builds' private file.
  static Future<File> defaultConfigFile() async {
    final support = await getApplicationSupportDirectory();
    final dir = await getExternalStorageDirectory() ?? support;
    final file = File("${dir.path}/band_config.json");
    final old = File("${support.path}/band_tuning.json");
    if (!await file.exists() && await old.exists()) {
      await old.copy(file.path);
      await old.delete();
    }
    return file;
  }

  Map<String, Object> _toJson() => {
    "_doc":
        "height 0.3-1 and position 0 (top) to 1 (bottom) in steps of 0.05; edge ${_names(BandEdge.values)}; "
        "launch ${_names(LaunchMode.values)}; launchMs and returnMs in steps of 20; return ${_names(ReturnMode.values)}; "
        "focus ${_names(FocusMotion.values)}; ring ${_names(RingColor.values)}; background ${_names(BackgroundMode.values)}; light ${_names(LightMode.values)}; idle ${_names(IdleMode.values)}; frameTimes true|false; "
        "tuning: ${Tune.all.map((p) => "${p.key} ${p.min}-${p.max} step ${p.step}").join(", ")}. "
        "Checked once a second while the launcher is in front.",
    ..._geometry.toJson(),
    "launch": _launchMode.name,
    "return": _returnMode.name,
    "focus": _focusMotion.name,
    "frameTimes": _frameTimes,
    "ring": _ringColor.name,
    "background": _background.name,
    "light": _lightMode.name,
    "launchMs": _launchDuration.inMilliseconds,
    "returnMs": _returnDuration.inMilliseconds,
    "idle": _idleMode.name,
    "tuning": tuning.toJson(),
  };

  static String _names(List<Enum> values) => values.map((v) => v.name).join("|");

  Future<void> _load() async {
    final locate = configFile;
    if (locate == null) {
      return;
    }
    try {
      final file = _file ??= await locate();
      if (!await file.exists()) {
        if (!_missingLogged) {
          debugPrint("band config: none at ${file.path}, using defaults");
          _missingLogged = true;
        }
        return;
      }
      final modified = await file.lastModified();
      if (modified == _configModified) {
        return;
      }
      _configModified = modified;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _geometry = BandGeometry.fromJson(json);
      _launchMode = LaunchMode.values.where((m) => m.name == json["launch"]).firstOrNull ?? _launchMode;
      _returnMode = ReturnMode.values.where((m) => m.name == json["return"]).firstOrNull ?? _returnMode;
      // v4 kept only glide on or off.
      final legacyGlide = json["focusGlide"] as bool?;
      _focusMotion =
          FocusMotion.values.where((m) => m.name == json["focus"]).firstOrNull ??
          (legacyGlide == false ? FocusMotion.jump : _focusMotion);
      _frameTimes = json["frameTimes"] as bool? ?? _frameTimes;
      _ringColor = RingColor.values.where((c) => c.name == json["ring"]).firstOrNull ?? _ringColor;
      _background = BackgroundMode.values.where((m) => m.name == json["background"]).firstOrNull ?? _background;
      _lightMode = LightMode.values.where((m) => m.name == json["light"]).firstOrNull ?? _lightMode;
      _loading = true;
      try {
        tuning.load(json["tuning"] as Map<String, dynamic>?);
      } finally {
        _loading = false;
      }
      final launchMs = json["launchMs"] as num?;
      final returnMs = json["returnMs"] as num?;
      _launchDuration = launchMs == null ? _launchDuration : _durationStep(Duration(milliseconds: launchMs.round()));
      _returnDuration = returnMs == null ? _returnDuration : _durationStep(Duration(milliseconds: returnMs.round()));
      _idleMode = IdleMode.values.where((m) => m.name == json["idle"]).firstOrNull ?? _idleMode;
      _restartIdleTimer();
      notifyListeners();
      debugPrint("band config loaded from ${file.path}: ${jsonEncode(_toJson()..remove("_doc"))}");
    } catch (e) {
      debugPrint("band config not loaded: $e");
    }
  }

  Future<void> _save() async {
    final locate = configFile;
    if (locate == null) {
      return;
    }
    try {
      final file = _file ??= await locate();
      await file.writeAsString(JsonEncoder.withIndent("  ").convert(_toJson()));
      _configModified = await file.lastModified();
      debugPrint("band config saved to ${file.path}: ${jsonEncode(_toJson()..remove("_doc"))}");
    } catch (e) {
      debugPrint("band config not saved: $e");
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
