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
import 'package:flauncher/home_focus.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The "main apps": one centred row that never scrolls. Tiles share the width given by [HomeLayout].
class HeroRow extends StatelessWidget {
  final List<App> applications;
  final double tileWidth;
  final double tileHeight;

  HeroRow({
    Key? key,
    required this.applications,
    required this.tileWidth,
    required this.tileHeight,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return _emptyHint(context);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int index = 0; index < applications.length; ++index) ...[
          if (index > 0) SizedBox(width: HomeLayout.gap),
          SizedBox(
            width: tileWidth,
            height: tileHeight,
            child: RevealOnFocus(
              inHero: true,
              child: AppCard(
                key: Key("hero-${applications[index].packageName}"),
                application: applications[index],
                inHero: true,
                autofocus: index == 0,
                onMove: (direction) => _onMove(context, direction, index),
                onMoveEnd: () => context.read<AppsService>().saveHeroOrder(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _onMove(BuildContext context, AxisDirection direction, int index) {
    final appsService = context.read<AppsService>();
    if (direction == AxisDirection.left && index > 0) {
      appsService.reorderHero(index, index - 1);
    } else if (direction == AxisDirection.right && index < applications.length - 1) {
      appsService.reorderHero(index, index + 1);
    }
  }

  Widget _emptyHint(BuildContext context) => Text(
        "Long-press an app below and choose “Add to main apps”.",
        key: Key("hero-empty"),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
          color: Colors.white70,
          shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
        ),
      );
}
