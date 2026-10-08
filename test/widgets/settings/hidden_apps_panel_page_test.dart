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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/settings/hidden_apps_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:transparent_image/transparent_image.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("lists only hidden apps and unhides on press", (tester) async {
    final appsService = MockAppsService();
    final hidden = fakeApp(packageName: "hidden.app", name: "Hidden app", hidden: true, icon: kTransparentImage);
    when(appsService.applications)
        .thenReturn([fakeApp(packageName: "visible.app", name: "Visible app", icon: kTransparentImage), hidden]);
    await _pump(tester, appsService);

    expect(find.text("Hidden app"), findsOneWidget);
    expect(find.text("Visible app"), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();
    verify(appsService.unHideApplication(hidden));
  });

  testWidgets("shows a hint when nothing is hidden", (tester) async {
    final appsService = MockAppsService();
    when(appsService.applications).thenReturn([fakeApp(packageName: "visible.app", icon: kTransparentImage)]);
    await _pump(tester, appsService);

    expect(find.text("No hidden apps."), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, AppsService appsService) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppsService>.value(
      value: appsService,
      builder: (_, _) => MaterialApp(home: Material(child: HiddenAppsPanelPage())),
    ),
  );
  await tester.pumpAndSettle();
}
