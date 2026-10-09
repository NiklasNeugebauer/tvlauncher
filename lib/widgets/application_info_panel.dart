/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 * Copyright (C) 2026  Niklas Neugebauer
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

import 'package:flauncher/database.dart';
import 'package:flauncher/home_focus.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/panel_row.dart';
import 'package:flauncher/widgets/right_panel_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The panel of an app in the grid: add it to the main apps, hide it, its system info, uninstall. Main apps have no
/// panel; a held select moves them, a longer hold moves them back down to the grid.
class ApplicationInfoPanel extends StatelessWidget {
  final App application;

  ApplicationInfoPanel({required this.application});

  static const double artworkWidth = 96;

  @override
  Widget build(BuildContext context) => RightPanelDialog(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Divider(),
        _entry(context, Icons.star, "Add to main apps", () async {
          // The new hero tile takes focus, ready to be moved into place.
          _homeFocus(context)?.focusWhenBuilt(application.packageName, inHero: true, move: true);
          await context.read<AppsService>().addToHero(application);
          Navigator.of(context).pop();
        }, autofocus: true),
        _entry(
          context,
          application.hidden ? Icons.visibility : Icons.visibility_off_outlined,
          application.hidden ? "Unhide" : "Hide",
          () async {
            if (application.hidden) {
              await context.read<AppsService>().unHideApplication(application);
            } else {
              await context.read<AppsService>().hideApplication(application);
            }
            Navigator.of(context).pop();
          },
        ),
        Divider(),
        _entry(context, Icons.info_outlined, "App info", () => context.read<AppsService>().openAppInfo(application)),
        _entry(context, Icons.delete_outlined, "Uninstall", () async {
          await context.read<AppsService>().uninstallApp(application);
          Navigator.of(context).pop();
        }, destructive: true),
      ],
    ),
  );

  static HomeFocusController? _homeFocus(BuildContext context) {
    try {
      return context.read<HomeFocusController>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Widget _header(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dim = textTheme.bodySmall!.copyWith(color: Palette.creamDim);
    return Padding(
      padding: EdgeInsets.only(left: PanelRow.gap, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _artwork(),
          SizedBox(height: 12),
          Text(application.name, style: textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
          SizedBox(height: 4),
          Text(application.packageName, style: dim, overflow: TextOverflow.ellipsis),
          Text("v${application.version}", style: dim, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _artwork() {
    if (application.banner != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Shapes.rowRadius),
        child: Image.memory(application.banner!, width: artworkWidth, fit: BoxFit.cover),
      );
    }
    if (application.icon != null) {
      return Image.memory(application.icon!, width: artworkWidth / 2);
    }
    return Icon(Icons.android, size: artworkWidth / 2);
  }

  Widget _entry(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool autofocus = false,
    bool destructive = false,
  }) => PanelRow(icon: icon, label: label, onPressed: onPressed, autofocus: autofocus, destructive: destructive);
}
