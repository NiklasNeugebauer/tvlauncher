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
