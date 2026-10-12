import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tvlauncher/database.dart';
import 'package:tvlauncher/desktop/desktop_paths.dart';
import 'package:tvlauncher/desktop/fake_launcher_channel.dart';
import 'package:tvlauncher/desktop/fake_remote.dart';

import 'package:tvlauncher/launcher_app.dart';

/// Runs the launcher on a desktop with made-up apps: `flutter run -d linux -t lib/desktop/main_desktop.dart`.
/// Files go to `build/desktop_data` (or `--dart-define=DESKTOP_DATA=<dir>`), including band_config.json.
/// Keys: arrows and Enter as on the remote, Backspace = Back, H = Home, Q = quick settings (long Back).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final channel = startDesktop();
  final database = LauncherDatabase(connect());
  await seedHero(channel, database);
  runApp(LauncherApp(ImagePicker(), channel, database));
}

/// Sets up everything [LauncherApp] needs from the platform and returns the channel to hand it.
FakeLauncherChannel startDesktop({String? dataDir}) {
  const defined = String.fromEnvironment("DESKTOP_DATA");
  final root = dataDir ?? (defined.isNotEmpty ? defined : "${Directory.current.path}/build/desktop_data");
  PathProviderPlatform.instance = DesktopPaths(root);
  final channel = FakeLauncherChannel();
  HardwareKeyboard.instance.addHandler((event) {
    if (event is! KeyDownEvent) return false;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.backspace:
        FakeRemote.back();
      case LogicalKeyboardKey.keyH:
        channel.pressHome();
      case LogicalKeyboardKey.keyQ:
        channel.pressQuickSettings();
      default:
        return false;
    }
    return true;
  });
  return channel;
}

/// A fresh database gets the fake apps and a hero of the first [count], like a TV that has been set up.
Future<void> seedHero(FakeLauncherChannel channel, LauncherDatabase database, {int count = 5}) async {
  if ((await database.listCategoriesWithVisibleApps()).isNotEmpty) return;
  final apps = await channel.getApplications();
  await database.persistApps([
    for (final app in apps)
      AppsCompanion.insert(
        packageName: app["packageName"],
        name: app["name"],
        version: app["version"],
        banner: Value(app["banner"]),
        icon: Value(app["icon"]),
        sideloaded: Value(app["sideloaded"]),
      ),
  ]);
  await database.insertCategory(CategoriesCompanion.insert(name: "Main", order: 0));
  final hero = (await database.listCategoriesWithVisibleApps()).first.category;
  await database.insertAppsCategories([
    for (var i = 0; i < count; i++)
      AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: apps[i]["packageName"], order: i),
  ]);
}
