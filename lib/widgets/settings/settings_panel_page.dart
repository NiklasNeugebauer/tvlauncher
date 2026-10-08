/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flauncher/widgets/panel_row.dart';
import 'package:flauncher/widgets/settings/flauncher_about_dialog.dart';
import 'package:flauncher/widgets/settings/hidden_apps_panel_page.dart';
import 'package:flauncher/widgets/settings/wallpaper_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The launcher's own settings, one level below quick settings.
class SettingsPanelPage extends StatelessWidget {
  static const String routeName = "settings_panel";

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader("Launcher settings"),
        Divider(),
        EnsureVisible(
          alignment: 0.5,
          child: _entry(
            context,
            Icons.wallpaper_outlined,
            "Wallpaper",
            () => Navigator.of(context).pushNamed(WallpaperPanelPage.routeName),
            autofocus: true,
          ),
        ),
        _entry(
          context,
          Icons.visibility_off_outlined,
          "Hidden apps",
          () => Navigator.of(context).pushNamed(HiddenAppsPanelPage.routeName),
        ),
        Divider(),
        _entry(
          context,
          Icons.info_outline,
          "About",
          () => showDialog(
            context: context,
            builder: (_) => FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done
                  ? FLauncherAboutDialog(packageInfo: snapshot.data!)
                  : Container(),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _entry(BuildContext context, IconData icon, String label, VoidCallback onPressed, {bool autofocus = false}) =>
      PanelRow(icon: icon, label: label, onPressed: onPressed, autofocus: autofocus);
}
