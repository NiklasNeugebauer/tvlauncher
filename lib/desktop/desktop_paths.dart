import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Keeps every file the launcher writes (database, wallpaper, band_config.json) in one directory, so a desktop run
/// neither touches ~/Documents nor needs Android's external storage, which path_provider has no Linux answer for.
class DesktopPaths extends PathProviderPlatform {
  final String root;

  DesktopPaths(this.root) {
    Directory(root).createSync(recursive: true);
  }

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getExternalStoragePath() async => root;

  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;

  @override
  Future<String?> getApplicationCachePath() async => Directory.systemTemp.path;
}
