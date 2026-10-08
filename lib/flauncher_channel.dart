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

class FLauncherChannel {
  static const _methodChannel = MethodChannel('me.efesser.flauncher/method');
  static const _eventChannel = EventChannel('me.efesser.flauncher/event');

  Future<List<dynamic>> getApplications() async => (await _methodChannel.invokeListMethod('getApplications'))!;

  Future<bool> applicationExists(String packageName) async =>
      await _methodChannel.invokeMethod('applicationExists', packageName);

  Future<void> launchApp(String packageName) async => await _methodChannel.invokeMethod('launchApp', packageName);

  /// [screen] is the name of a [SystemSettingsScreen]; the platform side picks the matching intents.
  Future<bool> openSystemSettings(String screen) async => await _methodChannel.invokeMethod('openSystemSettings', screen);

  Future<void> openAppInfo(String packageName) async => await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async => await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async => await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<void> startAmbientMode() async => await _methodChannel.invokeMethod("startAmbientMode");

  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) =>
      _eventChannel.receiveBroadcastStream().listen((event) => listener(event));

  /// Calls from the platform: the remote's Home button while the launcher is already running, and a long press
  /// on the Back button.
  void setPlatformHandlers({required void Function() onHomePressed, required void Function() onQuickSettingsPressed}) =>
      _methodChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case "homePressed":
            onHomePressed();
            break;
          case "quickSettingsPressed":
            onQuickSettingsPressed();
            break;
        }
      });
}
