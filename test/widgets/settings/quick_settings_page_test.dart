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
import 'package:flauncher/widgets/settings/quick_settings_page.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  for (final entry in {
    "Bluetooth": SystemSettingsScreen.bluetooth,
    "Wi-Fi": SystemSettingsScreen.wifi,
    "Display & Sound": SystemSettingsScreen.displaySound,
    "All settings": SystemSettingsScreen.all,
  }.entries) {
    testWidgets("'${entry.key}' opens the system screen and closes the panel", (tester) async {
      final appsService = MockAppsService();
      when(appsService.openSystemSettings(any)).thenAnswer((_) => Future.value(true));
      await _pumpPanel(tester, appsService);

      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();

      verify(appsService.openSystemSettings(entry.value));
      expect(find.byType(SettingsPanel), findsNothing);
    });
  }

  testWidgets("'Launcher settings' pushes the launcher settings page", (tester) async {
    final appsService = MockAppsService();
    when(appsService.categoriesWithApps).thenReturn([]);
    when(appsService.applications).thenReturn([]);
    await _pumpPanel(tester, appsService);

    await tester.tap(find.text("Launcher settings"));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPanelPage), findsOneWidget);
    expect(find.byType(SettingsPanel), findsOneWidget);
  });

  testWidgets("Bluetooth is focused when the panel opens", (tester) async {
    final appsService = MockAppsService();
    await _pumpPanel(tester, appsService);

    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text("Bluetooth"), matching: find.byType(TextButton)),
    );
    expect(button.autofocus, isTrue);
  });
}

Future<void> _pumpPanel(WidgetTester tester, AppsService appsService) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppsService>.value(value: appsService),
      ],
      builder: (_, _) => MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            child: Text("open"),
            onPressed: () => showDialog(context: context, builder: (_) => SettingsPanel()),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text("open"));
  await tester.pumpAndSettle();
  expect(find.byType(QuickSettingsPage), findsOneWidget);
}
