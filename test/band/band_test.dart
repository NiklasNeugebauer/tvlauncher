/*
 * FLauncher
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


import 'dart:convert';
import 'dart:io';

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/band/band_frame.dart';
import 'package:flauncher/band/band_geometry.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:transparent_image/transparent_image.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

const _frame = Size(960, 540);

void main() {
  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = _frame;
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
  });

  group("BandGeometry", () {
    test("places the band by height and position", () {
      expect(
        BandGeometry(height: 0.6, position: 1, edge: BandEdge.hard).rect(_frame),
        Rect.fromLTWH(0, 216, 960, 324),
      );
      expect(
        BandGeometry(height: 0.6, position: 0.5, edge: BandEdge.soft).rect(_frame),
        Rect.fromLTWH(0, 108, 960, 324),
      );
      expect(
        BandGeometry(height: 0.6, position: 1, edge: BandEdge.inset).rect(_frame),
        Rect.fromLTWH(0, 216, 960, 324).deflate(BandGeometry.insetMargin),
      );
    });

    test("steps stay on the 5 % grid and inside their limits", () {
      var geometry = BandGeometry(height: 0.6, position: 1, edge: BandEdge.soft);
      for (int i = 0; i < 3; ++i) {
        geometry = geometry.copyWith(height: geometry.height + BandGeometry.step);
      }
      expect(geometry.height, 0.75);
      expect(geometry.copyWith(height: 2).height, 1.0);
      expect(geometry.copyWith(height: 0).height, BandGeometry.minHeight);
      expect(geometry.copyWith(position: 1.05).position, 1.0);
      expect(geometry.copyWith(position: -0.05).position, 0.0);
    });

    test("edges cycle and survive a JSON round trip", () {
      final geometry = BandGeometry(height: 0.55, position: 0.35, edge: BandEdge.hard);
      expect(geometry.nextEdge().edge, BandEdge.soft);
      expect(geometry.nextEdge().nextEdge().nextEdge().edge, BandEdge.hard);
      expect(BandGeometry.fromJson(jsonDecode(jsonEncode(geometry.toJson()))), geometry);
      expect(BandGeometry.fromJson({}), BandGeometry.release);
    });
  });

  group("HomeLayout grid windows", () {
    // 6 columns over 896 px: tiles 136 x 76.5, rows every 92.5 px.
    final layout = HomeLayout(width: 960, height: 400, headingHeight: 30);

    test("windows hold whole rows", () {
      expect(layout.rowsUnderHeading, 3);
      expect(layout.rowsPerWindow, 4);
      expect(layout.windowOffset(0), layout.heroZoneHeight);
      expect(layout.windowOffset(2), layout.gridTop + 2 * layout.rowPitch - HomeLayout.gap);
    });

    test("moving down keeps the heading as long as the row fits under it, then pages row by row", () {
      expect(layout.windowFor(0, -1), 0);
      expect(layout.windowFor(2, 0), 0);
      expect(layout.windowFor(3, 0), 1);
      expect(layout.windowFor(4, 1), 1);
      expect(layout.windowFor(5, 1), 2);
    });

    test("moving up puts the row at the top, and back to the heading near the start", () {
      expect(layout.windowFor(4, 5), 4);
      expect(layout.windowFor(2, 3), 0);
      expect(layout.windowFor(0, 1), 0);
    });

    test("the bottom spacer lets the last window scroll fully into view", () {
      const apps = 6 * 9;
      final contentHeight = layout.gridTop + layout.gridContentHeight(apps) + layout.bottomSpacer(apps);
      final lastWindow = layout.windowFor(8, -1);
      expect(layout.windowOffset(lastWindow) + layout.height, lessThanOrEqualTo(contentHeight + 0.01));
    });
  });

  group("BandFrame", () {
    testWidgets("gives the app the band as its screen and paints the theme behind it", (tester) async {
      final controller = BandController(tuning: false);
      Size? screen;
      await _pumpFrame(tester, controller, Builder(builder: (context) => _record(context, (s) => screen = s)));

      expect(screen, BandGeometry.release.rect(_frame).size);
      expect(tester.getRect(find.byKey(Key("probe"))), BandGeometry.release.rect(_frame));
      expect(tester.widget(find.byKey(Key("background"))), isA<ThemedBackground>());
    });

    testWidgets("paints a custom wallpaper instead of the theme", (tester) async {
      final wallpaper = MockWallpaperService();
      when(wallpaper.wallpaperBytes).thenReturn(kTransparentImage);

      await _pumpFrame(tester, BandController(tuning: false), SizedBox(), wallpaper: wallpaper);

      expect(tester.widget(find.byKey(Key("background"))), isA<Image>());
    });

    testWidgets("nudge mode moves the band with the arrows, cycles the edge with select and gives focus back", (
      tester,
    ) async {
      final controller = BandController(tuning: false);
      final button = FocusNode();
      await _pumpFrame(
        tester,
        controller,
        TextButton(focusNode: button, autofocus: true, onPressed: () {}, child: Text("tile")),
      );
      expect(button.hasFocus, isTrue);

      controller.startNudging();
      await tester.pumpAndSettle();
      expect(button.hasFocus, isFalse);
      expect(find.byKey(Key("nudge-values")), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(controller.geometry, BandGeometry(height: 0.65, position: 0.95, edge: BandEdge.inset));
      expect(tester.getRect(find.byKey(Key("probe"))), controller.geometry.rect(_frame));

      controller.stopNudging();
      await tester.pumpAndSettle();
      expect(find.byKey(Key("nudge-values")), findsNothing);
      expect(button.hasFocus, isTrue);
      button.dispose();
    });
  });

  group("BandController", () {
    final app = fakeApp(packageName: "app.one");
    final tile = Rect.fromLTWH(100, 300, 200, 112.5);

    Future<LaunchTransition> launchWith(LaunchMode mode, {double pixelRatio = 1}) async {
      final apps = MockAppsService();
      final controller = BandController(tuning: false)
        ..launchMode = mode
        ..devicePixelRatio = pixelRatio
        ..bandRect = Rect.fromLTWH(0, 216, 960, 324);
      await controller.launch(apps, app, tile);
      return verify(apps.launchApp(app, captureAny)).captured.single as LaunchTransition;
    }

    testWidgets("launches with the transition of the chosen mode, in physical pixels", (tester) async {
      expect(await launchWith(LaunchMode.system), LaunchTransition.system);
      expect(
        await launchWith(LaunchMode.scaleTile, pixelRatio: 2),
        LaunchTransition.scaleUp(Rect.fromLTWH(200, 600, 400, 225)),
      );
      expect(await launchWith(LaunchMode.revealTile), LaunchTransition.reveal(tile));
      expect(await launchWith(LaunchMode.revealBand), LaunchTransition.reveal(Rect.fromLTWH(0, 216, 960, 324)));
    });

    testWidgets("a grow launch lights the full frame before the app starts", (tester) async {
      final apps = MockAppsService();
      final controller = BandController(tuning: false)..launchMode = LaunchMode.growFade;

      final launching = controller.launch(apps, app, tile);
      expect(controller.expanded, isTrue);
      expect(controller.contentVisible, isFalse);
      verifyNever(apps.launchApp(any, any));
      await tester.pump(Motion.layout);
      await launching;
      verify(apps.launchApp(app, LaunchTransition.fade));
    });

    test("coming back from an app plays the chosen return", () {
      final apps = MockAppsService();
      final controller = BandController(tuning: false)..returnMode = ReturnMode.collapse;
      controller.launch(apps, app, tile);

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect((controller.expanded, controller.contentVisible, controller.animateExpansion), (true, false, false));

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect((controller.expanded, controller.contentVisible, controller.animateExpansion), (false, true, true));
    });

    test("without a launch, hiding and resuming leave the band alone", () {
      final controller = BandController(tuning: false)..returnMode = ReturnMode.collapse;

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect((controller.expanded, controller.contentVisible), (false, true));
    });

    test("a tuning build remembers its choices in a file", () async {
      final dir = await Directory.systemTemp.createTemp("band");
      final file = File("${dir.path}/band_tuning.json");
      final first = BandController(tuning: true, tuningFile: () async => file);
      first.geometry = BandGeometry(height: 0.5, position: 0.25, edge: BandEdge.hard);
      first.launchMode = LaunchMode.scaleTile;
      first.returnMode = ReturnMode.collapse;
      first.focusGlide = false;
      await Future.delayed(Duration(milliseconds: 50));

      final second = BandController(tuning: true, tuningFile: () async => file);
      await Future.delayed(Duration(milliseconds: 50));

      expect(second.geometry, first.geometry);
      expect(second.launchMode, LaunchMode.scaleTile);
      expect(second.returnMode, ReturnMode.collapse);
      expect(second.focusGlide, isFalse);
      await dir.delete(recursive: true);
    });
  });
}

Widget _record(BuildContext context, void Function(Size) onSize) {
  onSize(MediaQuery.sizeOf(context));
  return SizedBox();
}

Future<void> _pumpFrame(
  WidgetTester tester,
  BandController controller,
  Widget home, {
  WallpaperService? wallpaper,
}) async {
  if (wallpaper == null) {
    wallpaper = MockWallpaperService();
    when(wallpaper.wallpaperBytes).thenReturn(null);
  }
  await tester.pumpWidget(
    ChangeNotifierProvider<WallpaperService>.value(
      value: wallpaper,
      child: MaterialApp(
        builder: (context, child) => BandFrame(controller: controller, child: child!),
        home: SizedBox.expand(key: Key("probe"), child: Center(child: home)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
