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

import 'package:tvlauncher/launcher_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test("getApplications", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "getApplications") {
        return [
          {'packageName': 'dev.neugebauer.tvlauncher'},
        ];
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    final apps = await launcherChannel.getApplications();

    expect(apps, [
      {'packageName': 'dev.neugebauer.tvlauncher'},
    ]);
  });

  test("launchApp", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    Object? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "launchApp") {
        arguments = call.arguments;
        return;
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    await launcherChannel.launchApp("dev.neugebauer.tvlauncher");
    expect(arguments, {"packageName": "dev.neugebauer.tvlauncher", "transition": "system"});

    await launcherChannel.launchApp(
      "dev.neugebauer.tvlauncher",
      LaunchTransition.scaleUp(Rect.fromLTWH(10.4, 20, 300, 169)),
    );
    expect(arguments, {
      "packageName": "dev.neugebauer.tvlauncher",
      "transition": "scaleUp",
      "source": [10, 20, 300, 169],
    });
  });

  test("openSystemSettings passes the screen name", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    String? screen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "openSystemSettings") {
        screen = call.arguments as String;
        return true;
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    final opened = await launcherChannel.openSystemSettings("bluetooth");

    expect(opened, isTrue);
    expect(screen, "bluetooth");
  });

  test("openAppInfo", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    String? packageName;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "openAppInfo") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    await launcherChannel.openAppInfo("dev.neugebauer.tvlauncher");

    expect(packageName, "dev.neugebauer.tvlauncher");
  });

  test("uninstallApp", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    String? packageName;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "uninstallApp") {
        packageName = call.arguments as String;
        return;
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    await launcherChannel.uninstallApp("dev.neugebauer.tvlauncher");

    expect(packageName, "dev.neugebauer.tvlauncher");
  });

  test("isDefaultLauncher", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "isDefaultLauncher") {
        return true;
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    final isDefaultLauncher = await launcherChannel.isDefaultLauncher();

    expect(isDefaultLauncher, isTrue);
  });

  test("checkForGetContentAvailability", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "checkForGetContentAvailability") {
        return true;
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    final getContentAvailable = await launcherChannel.checkForGetContentAvailability();

    expect(getContentAvailable, isTrue);
  });

  test("startAmbientMode", () async {
    final channel = MethodChannel('dev.neugebauer.tvlauncher/method');
    bool called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "startAmbientMode") {
        called = true;
        return;
      }
      fail("Unhandled method name");
    });
    final launcherChannel = LauncherChannel();

    await launcherChannel.startAmbientMode();

    expect(called, isTrue);
  });

  test("setPlatformHandlers routes homePressed and quickSettingsPressed", () async {
    final launcherChannel = LauncherChannel();
    var assist = 0;
    final fromApp = <bool>[];
    launcherChannel.setPlatformHandlers(onHomePressed: fromApp.add, onQuickSettingsPressed: () => assist++);

    final codec = StandardMethodCodec();
    for (final (method, arguments) in [
      ("homePressed", {"fromApp": true}),
      ("homePressed", null),
      ("quickSettingsPressed", null),
      ("quickSettingsPressed", null),
    ]) {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'dev.neugebauer.tvlauncher/method',
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
    }

    expect(fromApp, [true, false]);
    expect(assist, 2);
  });
}
