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

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/right_panel_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ApplicationInfoPanel extends StatelessWidget {
  final App application;
  final bool inHero;

  ApplicationInfoPanel({required this.application, required this.inHero});

  @override
  Widget build(BuildContext context) => RightPanelDialog(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            application.icon != null ? Image.memory(application.icon!, width: 50) : Icon(Icons.android, size: 50),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                application.name,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(application.packageName, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        Text("v${application.version}", style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        Divider(),
        if (inHero)
          _entry(context, Icons.star_outline, "Remove from main apps", () async {
            await context.read<AppsService>().removeFromHero(application);
            Navigator.of(context).pop(ApplicationInfoPanelResult.none);
          })
        else
          _entry(context, Icons.star, "Add to main apps", () async {
            await context.read<AppsService>().addToHero(application);
            Navigator.of(context).pop(ApplicationInfoPanelResult.none);
          }),
        if (inHero)
          _entry(
            context,
            Icons.swap_horiz,
            "Move",
            () => Navigator.of(context).pop(ApplicationInfoPanelResult.reorderApp),
          ),
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
            Navigator.of(context).pop(ApplicationInfoPanelResult.none);
          },
        ),
        Divider(),
        _entry(context, Icons.info_outlined, "App info", () => context.read<AppsService>().openAppInfo(application)),
        _entry(context, Icons.delete_outlined, "Uninstall", () async {
          await context.read<AppsService>().uninstallApp(application);
          Navigator.of(context).pop(ApplicationInfoPanelResult.none);
        }),
      ],
    ),
  );

  Widget _entry(BuildContext context, IconData icon, String label, VoidCallback onPressed) => TextButton(
    child: Row(
      children: [
        Icon(icon),
        Container(width: 8),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
    onPressed: onPressed,
  );
}

enum ApplicationInfoPanelResult { none, reorderApp }
