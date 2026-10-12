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

import 'package:tvlauncher/providers/wallpaper_service.dart';
import 'package:tvlauncher/widgets/settings/wallpaper_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  group("'Custom image'", () {
    testWidgets("opens file explorer if available", (tester) async {
      final wallpaperService = MockWallpaperService();
      when(wallpaperService.wallpaperBytes).thenReturn(null);

      await _pumpWidgetWithProviders(tester, wallpaperService);

      // Custom image is the first entry and autofocused.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      verify(wallpaperService.pickWallpaper());
    });

    testWidgets("shows snack bar if not file explorer available", (tester) async {
      final wallpaperService = MockWallpaperService();
      when(wallpaperService.wallpaperBytes).thenReturn(null);
      when(wallpaperService.pickWallpaper()).thenThrow(NoFileExplorerException());

      await _pumpWidgetWithProviders(tester, wallpaperService);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text("Please install a file explorer in order to pick an image."), findsOneWidget);
    });
  });

  group("'Back to theme'", () {
    testWidgets("is hidden without a custom image", (tester) async {
      final wallpaperService = MockWallpaperService();
      when(wallpaperService.wallpaperBytes).thenReturn(null);

      await _pumpWidgetWithProviders(tester, wallpaperService);

      expect(find.text("Back to theme"), findsNothing);
    });

    testWidgets("clears the custom image", (tester) async {
      final wallpaperService = MockWallpaperService();
      when(wallpaperService.wallpaperBytes).thenReturn(Uint8List.fromList([0x01]));

      await _pumpWidgetWithProviders(tester, wallpaperService);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      verify(wallpaperService.clearWallpaper());
    });
  });
}

Future<void> _pumpWidgetWithProviders(WidgetTester tester, WallpaperService wallpaperService) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<WallpaperService>.value(
      value: wallpaperService,
      builder: (_, _) => MaterialApp(home: Scaffold(body: WallpaperPanelPage())),
    ),
  );
  await tester.pumpAndSettle();
}
