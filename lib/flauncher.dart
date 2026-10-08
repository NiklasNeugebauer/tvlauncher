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

import 'dart:typed_data';
import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/home_focus.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/hero_row.dart';
import 'package:flauncher/widgets/home_layout.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/time_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FLauncher extends StatefulWidget {
  @override
  State<FLauncher> createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> {
  @override
  void initState() {
    super.initState();
    context.read<AppsService>().setPlatformHandlers(
      onHomePressed: _onHomePressed,
      onQuickSettingsPressed: _onQuickSettingsPressed,
    );
  }

  void _onQuickSettingsPressed() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    showDialog(context: context, builder: (_) => SettingsPanel());
  }

  // Home always lands on the first main app: close whatever panel is open, drop a tile being moved (it ends its
  // move on focus loss), then focus and scroll to the top once that has settled.
  void _onHomePressed() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    FocusManager.instance.primaryFocus?.unfocus();
    final controller = context.read<HomeFocusController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.focusFirstTile());
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: RowByRowTraversalPolicy(),
    child: Stack(
      children: [
        Consumer<WallpaperService>(
          builder: (_, wallpaper, _) => _wallpaper(wallpaper.wallpaperBytes),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _appBar(context),
          body: Consumer<AppsService>(
            builder: (context, appsService, _) =>
                appsService.initialized ? _home(context, appsService) : _emptyState(context),
          ),
        ),
      ],
    ),
  );

  Widget _home(BuildContext context, AppsService appsService) => LayoutBuilder(
    builder: (context, constraints) {
      final headingStyle = _headingStyle(context);
      final layout = HomeLayout(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        headingHeight: _textHeight(context, "Apps", headingStyle),
      );
      final controller = context.read<HomeFocusController>();
      controller.heroZoneHeight = layout.heroZoneHeight;
      final heroApps = appsService.heroApps;
      final gridApps = appsService.gridApps;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostFocus(context, controller));
      return SingleChildScrollView(
        controller: controller.scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: layout.heroZoneHeight,
              child: Focus(
                focusNode: controller.heroNode,
                canRequestFocus: false,
                skipTraversal: true,
                child: Align(
                  alignment: HomeLayout.heroAlignment,
                  child: HeroRow(
                    applications: heroApps,
                    tileWidth: layout.heroTileWidth(heroApps.length),
                    tileHeight: layout.heroTileHeight(heroApps.length),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                HomeLayout.sidePadding,
                HomeLayout.headingTop,
                HomeLayout.sidePadding,
                HomeLayout.headingBottom,
              ),
              child: Text("Apps", style: headingStyle),
            ),
            Focus(
              focusNode: controller.gridNode,
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: controller.handleGridKey,
              child: AppsGrid(
                applications: gridApps,
                tileWidth: layout.gridTileWidth,
                autofocusFirst: heroApps.isEmpty,
              ),
            ),
            SizedBox(height: layout.bottomSpacer(gridApps.length)),
          ],
        ),
      );
    },
  );

  // After a tile disappears (hidden, uninstalled, moved between hero and grid) focus falls back to the scope and
  // the remote stops working. Only the home route itself recovers; an open panel keeps its own focus.
  void _recoverLostFocus(BuildContext context, HomeFocusController controller) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) {
      controller.focusFirstTile();
    }
  }

  // Quieter than the clock so it does not compete with the tiles.
  TextStyle _headingStyle(BuildContext context) => Theme.of(context).textTheme.titleLarge!.copyWith(
    color: Palette.cream.withValues(alpha: 0.7),
    shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
  );

  double _textHeight(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.height;
  }

  AppBar _appBar(BuildContext context) => AppBar(
    titleSpacing: HomeLayout.sidePadding,
    centerTitle: false,
    title: TimeWidget(),
    actions: [
      Padding(
        padding: EdgeInsets.only(right: HomeLayout.sidePadding),
        child: _SettingsButton(onPressed: () => showDialog(context: context, builder: (_) => SettingsPanel())),
      ),
    ],
  );

  Widget _wallpaper(Uint8List? wallpaperImage) => Positioned.fill(
    child: wallpaperImage != null
        ? Image.memory(wallpaperImage, key: Key("background"), fit: BoxFit.cover)
        : ThemedBackground(key: Key("background")),
  );

  Widget _emptyState(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text("Loading...", style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

/// The gear: dim until focused, then brass like every other focus mark.
class _SettingsButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _SettingsButton({required this.onPressed});

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) => setState(() => _focused = focused),
    child: IconButton(
      key: Key("settings"),
      padding: EdgeInsets.all(2),
      constraints: BoxConstraints(),
      splashRadius: 20,
      color: _focused ? Palette.brass : Palette.creamDim,
      icon: Icon(Icons.settings_outlined),
      onPressed: widget.onPressed,
    ),
  );
}
