/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flutter/services.dart';

/// How Android animates an app's window in when the launcher starts it. [source] is in physical pixels of the
/// launcher's window.
class LaunchTransition {
  final String kind;
  final Rect? source;

  const LaunchTransition._(this.kind, [this.source]);

  /// Whatever the system does for a plain startActivity.
  static const LaunchTransition system = LaunchTransition._("system");

  /// No window animation at all: the launcher has already played its own.
  static const LaunchTransition none = LaunchTransition._("none");

  /// A short cross-fade, to soften the cut after the launcher's own animation.
  static const LaunchTransition fade = LaunchTransition._("fade");

  /// The app's window scales up from [source].
  const LaunchTransition.scaleUp(Rect source) : this._("scaleUp", source);

  Map<String, Object?> toArguments(String packageName) => {
    "packageName": packageName,
    "transition": kind,
    if (source != null)
      "source": [source!.left, source!.top, source!.width, source!.height].map((v) => v.round()).toList(),
  };

  @override
  bool operator ==(Object other) => other is LaunchTransition && other.kind == kind && other.source == source;

  @override
  int get hashCode => Object.hash(kind, source);

  @override
  String toString() => "LaunchTransition($kind, $source)";
}

class LauncherChannel {
  static const _methodChannel = MethodChannel('dev.neugebauer.tvlauncher/method');
  static const _eventChannel = EventChannel('dev.neugebauer.tvlauncher/event');

  Future<List<dynamic>> getApplications() async => (await _methodChannel.invokeListMethod('getApplications'))!;

  Future<bool> applicationExists(String packageName) async =>
      await _methodChannel.invokeMethod('applicationExists', packageName);

  Future<void> launchApp(String packageName, [LaunchTransition transition = LaunchTransition.system]) async =>
      await _methodChannel.invokeMethod('launchApp', transition.toArguments(packageName));

  /// [screen] is the name of a [SystemSettingsScreen]; the platform side picks the matching intents.
  Future<bool> openSystemSettings(String screen) async =>
      await _methodChannel.invokeMethod('openSystemSettings', screen);

  Future<void> openAppInfo(String packageName) async => await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async => await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async => await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<void> startAmbientMode() async => await _methodChannel.invokeMethod("startAmbientMode");

  /// Plays one of the UI sounds rendered by tool/sounds.py; [rate] 0.5 to 2 shifts its pitch, [volume] is 0 to 1.
  Future<void> playSound(String name, {double rate = 1, double volume = 1}) async =>
      await _methodChannel.invokeMethod("playSound", {"name": name, "rate": rate, "volume": volume});

  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) =>
      _eventChannel.receiveBroadcastStream().listen((event) => listener(event));

  /// Calls from the platform: the remote's Home button while the launcher is already running ([onHomePressed] gets
  /// whether an app was in front), and a long press on the Back button.
  void setPlatformHandlers({
    required void Function(bool fromApp) onHomePressed,
    required void Function() onQuickSettingsPressed,
  }) => _methodChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case "homePressed":
        onHomePressed((call.arguments as Map?)?["fromApp"] == true);
        break;
      case "quickSettingsPressed":
        onQuickSettingsPressed();
        break;
    }
  });
}
