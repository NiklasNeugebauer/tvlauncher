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
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Apps hidden from the home screen, each with a button to bring it back.
class HiddenAppsPanelPage extends StatelessWidget {
  static const String routeName = "hidden_apps_panel";

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text("Hidden apps", style: Theme.of(context).textTheme.titleLarge),
          Divider(),
          Expanded(
            child: Selector<AppsService, List<App>>(
              selector: (_, appsService) => appsService.applications.where((app) => app.hidden).toList(),
              builder: (context, applications, _) => applications.isEmpty
                  ? Center(child: Text("No hidden apps.", style: Theme.of(context).textTheme.bodyMedium))
                  : ListView(
                      children: [
                        for (int index = 0; index < applications.length; ++index)
                          EnsureVisible(
                            alignment: 0.5,
                            child: _appCard(context, applications[index], autofocus: index == 0),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      );

  Widget _appCard(BuildContext context, App application, {required bool autofocus}) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            application.name,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          leading: application.icon != null ? Image.memory(application.icon!, height: 48) : Icon(Icons.android),
          trailing: IconButton(
            autofocus: autofocus,
            constraints: BoxConstraints(),
            splashRadius: 20,
            tooltip: "Unhide",
            icon: Icon(Icons.visibility),
            onPressed: () => context.read<AppsService>().unHideApplication(application),
          ),
        ),
      );
}
