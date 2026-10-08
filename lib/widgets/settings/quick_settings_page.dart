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

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/panel_row.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// First page behind the gear: the system screens that get used from the couch, then the launcher's own settings.
class QuickSettingsPage extends StatelessWidget {
  static const String routeName = "quick_settings";

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader("Quick settings"),
        Divider(),
        _systemEntry(context, Icons.bluetooth, "Bluetooth", SystemSettingsScreen.bluetooth, autofocus: true),
        _systemEntry(context, Icons.wifi, "Wi-Fi", SystemSettingsScreen.wifi),
        _systemEntry(context, Icons.tv, "Display & Sound", SystemSettingsScreen.displaySound),
        _systemEntry(context, Icons.settings_outlined, "All settings", SystemSettingsScreen.all),
        Divider(),
        _entry(
          context,
          Icons.tune,
          "Launcher settings",
          () => Navigator.of(context).pushNamed(SettingsPanelPage.routeName),
        ),
        if (tuningBuild) ..._tuningEntries(context),
      ],
    ),
  );

  // Tuning builds only: the nudge mode and the switchers for what is still being picked on the wall.
  List<Widget> _tuningEntries(BuildContext context) {
    final band = BandScope.maybeOf(context, listen: true);
    if (band == null) {
      return [];
    }
    T next<T extends Enum>(List<T> values, T current) => values[(current.index + 1) % values.length];
    return [
      Divider(),
      _entry(context, Icons.straighten, "Tune band", () async {
        Navigator.of(context, rootNavigator: true).pop();
        // Once the panel is gone and focus is back on the home screen, so leaving the mode can return it there.
        await Future.delayed(Motion.layout);
        band.startNudging();
      }),
      _entry(
        context,
        Icons.open_in_full,
        "Launch: ${band.launchMode.label}",
        () => band.launchMode = next(LaunchMode.values, band.launchMode),
      ),
      _entry(
        context,
        Icons.close_fullscreen,
        "Return: ${band.returnMode.label}",
        () => band.returnMode = next(ReturnMode.values, band.returnMode),
      ),
      _entry(
        context,
        Icons.center_focus_strong,
        "Focus: ${band.focusGlide ? "glide" : "jump"}",
        () => band.focusGlide = !band.focusGlide,
      ),
    ];
  }

  // The panel closes itself: Back from the system screen should land on the home screen, not on a stale menu.
  Widget _systemEntry(
    BuildContext context,
    IconData icon,
    String label,
    SystemSettingsScreen screen, {
    bool autofocus = false,
  }) => _entry(context, icon, label, () async {
    await context.read<AppsService>().openSystemSettings(screen);
    Navigator.of(context, rootNavigator: true).pop();
  }, autofocus: autofocus);

  Widget _entry(BuildContext context, IconData icon, String label, VoidCallback onPressed, {bool autofocus = false}) =>
      PanelRow(icon: icon, label: label, onPressed: onPressed, autofocus: autofocus);
}
