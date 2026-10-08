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
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/home_layout.dart';
import 'package:flutter/material.dart';

/// Every app that is not in the hero row, alphabetical, in fixed-size rows that scroll with the page.
///
/// Plain rows rather than a sliver grid: a sliver only builds the tiles near the viewport, and the row-by-row
/// focus traversal can only move to tiles that exist.
class AppsGrid extends StatelessWidget {
  final List<App> applications;
  final double tileWidth;
  final bool autofocusFirst;

  AppsGrid({
    Key? key,
    required this.applications,
    required this.tileWidth,
    this.autofocusFirst = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int start = 0; start < applications.length; start += HomeLayout.gridColumns) {
      final end = (start + HomeLayout.gridColumns).clamp(0, applications.length);
      rows.add(Padding(
        padding: EdgeInsets.only(top: start == 0 ? 0 : HomeLayout.gap),
        child: Row(
          children: [
            for (int index = start; index < end; ++index) ...[
              if (index > start) SizedBox(width: HomeLayout.gap),
              SizedBox(
                width: tileWidth,
                height: tileWidth / HomeLayout.aspectRatio,
                child: RevealOnFocus(
                  inHero: false,
                  child: AppCard(
                    key: Key("grid-${applications[index].packageName}"),
                    application: applications[index],
                    inHero: false,
                    autofocus: autofocusFirst && index == 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ));
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: HomeLayout.sidePadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}
