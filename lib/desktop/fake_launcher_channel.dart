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
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:tvlauncher/launcher_channel.dart';

/// Stands in for the Android side when the launcher runs on a desktop: a fixed set of made-up apps with generated
/// banners and icons, the sizes `drawableToByteArray` gives at density 320. Launching an app hides the launcher and
/// "returns" to it after [returnAfter], so the launch and return animations both play.
///
/// It also owns the app lifecycle: a desktop window goes inactive whenever it loses focus, which a TV launcher in
/// front never does, so the embedder's lifecycle messages are dropped and the launcher stays resumed.
class FakeLauncherChannel extends LauncherChannel {
  final Duration returnAfter;
  Future<List<Map<String, Object?>>>? _apps;
  bool _launched = false;
  void Function(bool fromApp)? _onHomePressed;
  void Function()? _onQuickSettingsPressed;

  FakeLauncherChannel({this.returnAfter = const Duration(milliseconds: 1500)}) {
    SystemChannels.lifecycle.setMessageHandler((_) async => null);
    _lifecycle(const [AppLifecycleState.resumed]);
  }

  /// What the remote's Home and long Back would send.
  void pressHome() => _onHomePressed?.call(false);

  void pressQuickSettings() => _onQuickSettingsPressed?.call();

  @override
  Future<List<dynamic>> getApplications() => _apps ??= _buildApps();

  @override
  Future<bool> applicationExists(String packageName) async => true;

  @override
  Future<void> launchApp(String packageName, [LaunchTransition transition = LaunchTransition.system]) async {
    debugPrint("fake channel: launch $packageName with $transition");
    // One fake app at a time; a second launch before the return would stack another Home press and lifecycle.
    if (_launched) return;
    _launched = true;
    // The app's first frame covers the launcher about 350 ms after the start (measured on the device).
    Timer(
      const Duration(milliseconds: 350),
      () => _lifecycle(const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]),
    );
    // As on Android: the Home press reaches the launcher (onNewIntent) before it resumes.
    Timer(returnAfter, () {
      _launched = false;
      _onHomePressed?.call(true);
      _lifecycle(const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
    });
  }

  // ignore: invalid_use_of_protected_member
  void _lifecycle(List<AppLifecycleState> states) =>
      states.forEach(WidgetsBinding.instance.handleAppLifecycleStateChanged);

  @override
  Future<bool> openSystemSettings(String screen) async {
    debugPrint("fake channel: system settings $screen");
    return true;
  }

  @override
  Future<void> openAppInfo(String packageName) async => debugPrint("fake channel: app info $packageName");

  @override
  Future<void> uninstallApp(String packageName) async => debugPrint("fake channel: uninstall $packageName");

  @override
  Future<bool> isDefaultLauncher() async => true;

  @override
  Future<bool> checkForGetContentAvailability() async => false;

  @override
  Future<void> startAmbientMode() async => debugPrint("fake channel: ambient mode");

  @override
  Future<void> playSound(String name, {double rate = 1, double volume = 1}) async {}

  @override
  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) {}

  @override
  void setPlatformHandlers({
    required void Function(bool fromApp) onHomePressed,
    required void Function() onQuickSettingsPressed,
  }) {
    _onHomePressed = onHomePressed;
    _onQuickSettingsPressed = onQuickSettingsPressed;
  }
}

/// Banner styles found on a real TV: full-bleed artwork, a small logo on a plain colour, and no banner at all (a
/// sideloaded phone app with only an icon).
enum _Style { artwork, plainLogo, iconOnly }

const _names = [
  "Streamflix",
  "Tubeview",
  "Prime Cinema",
  "Arte Mediathek",
  "Musicbox",
  "Podcasts",
  "Kodi",
  "Plex",
  "Jellyfin",
  "Weather",
  "News 24",
  "Sport Live",
  "Kids TV",
  "Photos",
  "Browser",
  "Files",
  "Settings Plus",
  "VLC",
  "Spotlight",
  "Radio",
  "Fitness",
  "Recipes",
  "Game Hub",
  "Remote Desktop",
];

Future<List<Map<String, Object?>>> _buildApps() async {
  final apps = <Map<String, Object?>>[];
  for (var i = 0; i < _names.length; i++) {
    final style = switch (i % 4) {
      3 => _Style.iconOnly,
      2 => _Style.plainLogo,
      _ => _Style.artwork,
    };
    final hue = (i * 47) % 360.0;
    apps.add({
      "name": _names[i],
      "packageName": "com.example.${_names[i].toLowerCase().replaceAll(" ", "")}",
      "banner": style == _Style.iconOnly ? null : await _banner(_names[i], hue, style),
      "icon": await _icon(_names[i], hue),
      "version": "1.$i.0",
      "sideloaded": style == _Style.iconOnly,
    });
  }
  return apps;
}

Future<Uint8List> _banner(String name, double hue, _Style style) => _png(320, 180, (canvas, size) {
  final base = HSVColor.fromAHSV(1, hue, 0.7, 0.8).toColor();
  if (style == _Style.artwork) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          base,
          HSVColor.fromAHSV(1, (hue + 60) % 360, 0.9, 0.3).toColor(),
        ]),
    );
    for (var k = 0; k < 6; k++) {
      canvas.drawCircle(
        Offset(40.0 + k * 50, 40.0 + (k * 37) % 100),
        18.0 + k * 4,
        Paint()..color = const Color(0x33FFFFFF),
      );
    }
    _text(canvas, size, name, 30, const Color(0xFFFFFFFF));
  } else {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101418));
    canvas.drawCircle(size.center(const Offset(0, -12)), 26, Paint()..color = base);
    _text(canvas, Size(size.width, size.height + 90), name, 18, base);
  }
});

Future<Uint8List> _icon(String name, double hue) => _png(192, 192, (canvas, size) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(40)),
    Paint()..color = HSVColor.fromAHSV(1, hue, 0.6, 0.9).toColor(),
  );
  _text(canvas, size, name.substring(0, 1), 110, const Color(0xFFFFFFFF));
});

void _text(Canvas canvas, Size size, String text, double fontSize, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, color: color, fontWeight: FontWeight.bold),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: size.width);
  painter.paint(canvas, Offset((size.width - painter.width) / 2, (size.height - painter.height) / 2));
  painter.dispose();
}

Future<Uint8List> _png(int width, int height, void Function(Canvas, Size) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return bytes!.buffer.asUint8List();
}
