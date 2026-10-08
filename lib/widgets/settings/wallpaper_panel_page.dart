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

import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/panel_row.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A custom image replaces the themed background; "Back to theme" removes it again.
class WallpaperPanelPage extends StatelessWidget {
  static const String routeName = "wallpaper_panel";

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PanelHeader("Wallpaper"),
      Divider(),
      PanelRow(
        autofocus: true,
        icon: Icons.insert_drive_file_outlined,
        label: "Custom image",
        onPressed: () => _pickWallpaper(context),
      ),
      Selector<WallpaperService, bool>(
        selector: (_, wallpaperService) => wallpaperService.wallpaperBytes != null,
        builder: (context, hasWallpaper, _) => hasWallpaper
            ? PanelRow(
                icon: Icons.palette_outlined,
                label: "Back to theme",
                onPressed: () => context.read<WallpaperService>().clearWallpaper(),
              )
            : SizedBox.shrink(),
      ),
    ],
  );

  Future<void> _pickWallpaper(BuildContext context) async {
    try {
      await context.read<WallpaperService>().pickWallpaper();
    } on NoFileExplorerException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: 8),
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
              SizedBox(width: 8),
              Text("Please install a file explorer in order to pick an image."),
            ],
          ),
        ),
      );
    }
  }
}
