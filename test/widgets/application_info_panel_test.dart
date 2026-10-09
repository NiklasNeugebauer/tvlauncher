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
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:transparent_image/transparent_image.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("The panel offers 'Add to main apps' and nothing for main apps", (tester) async {
    final appsService = MockAppsService();
    final app = _app();
    await _pump(tester, appsService, app);

    expect(find.text("Add to main apps"), findsOneWidget);
    expect(find.text("Remove from main apps"), findsNothing);
    expect(find.text("Move"), findsNothing);
    expect(find.text("Hide"), findsOneWidget);
    expect(find.text("App info"), findsOneWidget);
    expect(find.text("Uninstall"), findsOneWidget);

    await tester.tap(find.text("Add to main apps"));
    await tester.pumpAndSettle();
    verify(appsService.addToHero(app));
    expect(find.byType(ApplicationInfoPanel), findsNothing);
  });

  testWidgets("'Hide' and 'Unhide' call AppsService", (tester) async {
    final appsService = MockAppsService();
    final visible = _app();
    await _pump(tester, appsService, visible);
    await tester.tap(find.text("Hide"));
    await tester.pumpAndSettle();
    verify(appsService.hideApplication(visible));

    final hidden = _app(hidden: true);
    await _pump(tester, appsService, hidden);
    await tester.tap(find.text("Unhide"));
    await tester.pumpAndSettle();
    verify(appsService.unHideApplication(hidden));
  });

  testWidgets("'App info' and 'Uninstall' call AppsService", (tester) async {
    final appsService = MockAppsService();
    final app = _app();
    await _pump(tester, appsService, app);

    await tester.tap(find.text("App info"));
    await tester.pumpAndSettle();
    verify(appsService.openAppInfo(app));

    await tester.tap(find.text("Uninstall"));
    await tester.pumpAndSettle();
    verify(appsService.uninstallApp(app));
  });

  testWidgets("An app without icon renders a placeholder", (tester) async {
    final appsService = MockAppsService();
    await _pump(tester, appsService, fakeApp(packageName: "no.icon", name: "No icon", icon: null));

    expect(find.byIcon(Icons.android), findsOneWidget);
  });
}

App _app({bool hidden = false}) => fakeApp(
  packageName: "me.efesser.flauncher",
  name: "FLauncher",
  version: "1.0.0",
  banner: kTransparentImage,
  icon: kTransparentImage,
  hidden: hidden,
);

Future<void> _pump(WidgetTester tester, AppsService appsService, App application) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppsService>.value(
      value: appsService,
      builder: (_, _) => MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            child: Text("open"),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ApplicationInfoPanel(application: application),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
}
