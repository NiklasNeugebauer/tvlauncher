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

class ApplicationInfoPanel extends StatelessWidget {
  final App application;
  final bool inHero;

  ApplicationInfoPanel({required this.application, required this.inHero});

  static const double artworkWidth = 96;

  @override
  Widget build(BuildContext context) => RightPanelDialog(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Divider(),
        if (inHero)
          _entry(context, Icons.star_outline, "Remove from main apps", () async {
            final apps = context.read<AppsService>();
            _focusAfterRemoval(context, apps);
            await apps.removeFromHero(application);
            Navigator.of(context).pop(ApplicationInfoPanelResult.none);
          }, autofocus: true)
        else
          _entry(context, Icons.star, "Add to main apps", () async {
            // The new hero tile takes focus, ready to be moved into place.
            _homeFocus(context)?.focusWhenBuilt(application.packageName, inHero: true, move: true);
            await context.read<AppsService>().addToHero(application);
            Navigator.of(context).pop(ApplicationInfoPanelResult.none);
          }, autofocus: true),
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
        }, destructive: true),
      ],
    ),
  );

  // Focus stays in the hero, on the tile that takes the removed one's place; with no hero left, it follows the
  // app into the grid.
  void _focusAfterRemoval(BuildContext context, AppsService apps) {
    final homeFocus = _homeFocus(context);
    if (homeFocus == null) {
      return;
    }
    final hero = apps.heroApps;
    final index = hero.indexWhere((app) => app.packageName == application.packageName);
    if (index < 0) {
      return;
    }
    if (hero.length == 1) {
      homeFocus.focusWhenBuilt(application.packageName, inHero: false);
    } else {
      final neighbour = index + 1 < hero.length ? hero[index + 1] : hero[index - 1];
      homeFocus.focusWhenBuilt(neighbour.packageName, inHero: true);
    }
  }

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

enum ApplicationInfoPanelResult { none, reorderApp }
