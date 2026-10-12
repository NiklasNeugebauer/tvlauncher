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

import 'package:tvlauncher/actions.dart';
import 'package:tvlauncher/band/band_controller.dart';
import 'package:tvlauncher/band/band_frame.dart';
import 'package:tvlauncher/providers/apps_service.dart';
import 'package:tvlauncher/home_focus.dart';
import 'package:tvlauncher/providers/wallpaper_service.dart';
import 'package:tvlauncher/sound/ui_sounds.dart';
import 'package:flutter/material.dart';
import 'package:tvlauncher/theme.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'database.dart';
import 'launcher.dart';
import 'launcher_channel.dart';

class LauncherApp extends StatelessWidget {
  final ImagePicker _imagePicker;
  final LauncherChannel _launcherChannel;
  final LauncherDatabase _launcherDatabase;

  LauncherApp(this._imagePicker, this._launcherChannel, this._launcherDatabase);

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AppsService(_launcherChannel, _launcherDatabase)),
      ChangeNotifierProvider(create: (_) => WallpaperService(_imagePicker, _launcherChannel)),
      Provider<HomeFocusController>(
        create: (_) => HomeFocusController(),
        dispose: (_, controller) => controller.dispose(),
      ),
      // Not lazy: created before the navigator, so Back reaches it first (see BandController.didPopRoute).
      ChangeNotifierProvider(create: (_) => BandController(configFile: BandController.defaultConfigFile), lazy: false),
      Provider<UiSounds>(create: (context) => UiSounds(_launcherChannel, context.read<BandController>())),
    ],
    // A builder, so the actions below get a context that sees the providers.
    builder: (context, _) => MaterialApp(
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonB): PrioritizedIntents(
          orderedIntents: [DismissIntent(), BackIntent()],
        ),
      },
      actions: {...WidgetsApp.defaultActions, DirectionalFocusIntent: SoundFeedbackDirectionalFocusAction(context)},
      title: 'Launcher',
      theme: buildTheme(),
      builder: (context, child) => BandFrame(controller: context.read<BandController>(), child: child!),
      home: Builder(
        builder: (context) => PopScope(
          canPop: false,
          // Back: inside the grid it returns to the first main app; on the hero it starts the screensaver. As a
          // non-default launcher the app exits like any other. Idle and nudge mode take Back before this.
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) {
              return;
            }
            if (await shouldPopScope(context)) {
              SystemNavigator.pop();
              return;
            }
            if (!context.mounted) {
              return;
            }
            final homeFocus = context.read<HomeFocusController>();
            if (homeFocus.gridHasFocus) {
              homeFocus.focusFirstTile(animate: true);
            } else {
              context.read<AppsService>().startAmbientMode();
            }
          },
          child: Actions(actions: {BackIntent: BackAction(context, systemNavigator: true)}, child: Launcher()),
        ),
      ),
    ),
  );
}
