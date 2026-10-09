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

import 'package:flauncher/background/diamond_background.dart';
import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/band/band_frame.dart';
import 'package:flauncher/band/band_geometry.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/motion/tuning.dart';
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
      expect(BandGeometry(height: 0.6, position: 1, edge: BandEdge.hard).rect(_frame), Rect.fromLTWH(0, 216, 960, 324));
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
      final controller = BandController();
      Size? screen;
      await _pumpFrame(tester, controller, Builder(builder: (context) => _record(context, (s) => screen = s)));

      expect(screen, BandGeometry.release.rect(_frame).size);
      expect(tester.getRect(find.byKey(Key("probe"))), BandGeometry.release.rect(_frame));
      expect(tester.widget(find.byKey(Key("background"))), isA<DiamondBackground>());
    });

    testWidgets("paints v3's glow when the background is set to glow", (tester) async {
      final controller = BandController()..background = BackgroundMode.glow;
      await _pumpFrame(tester, controller, SizedBox());

      expect(tester.widget(find.byKey(Key("background"))), isA<ThemedBackground>());
    });

    testWidgets("paints a custom wallpaper instead of the theme", (tester) async {
      final wallpaper = MockWallpaperService();
      when(wallpaper.wallpaperBytes).thenReturn(kTransparentImage);

      await _pumpFrame(tester, BandController(), SizedBox(), wallpaper: wallpaper);

      expect(tester.widget(find.byKey(Key("background"))), isA<Image>());
    });

    testWidgets("nudge mode moves the band with the arrows, cycles the edge with select and gives focus back", (
      tester,
    ) async {
      final controller = BandController();
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
      expect(controller.geometry, BandGeometry(height: 0.65, position: 0.55, edge: BandEdge.soft));
      expect(tester.getRect(find.byKey(Key("probe"))), controller.geometry.rect(_frame));

      controller.stopNudging();
      await tester.pumpAndSettle();
      expect(find.byKey(Key("nudge-values")), findsNothing);
      expect(button.hasFocus, isTrue);
      button.dispose();
    });
  });

  group("Idle", () {
    testWidgets("after the idle time the band shrinks to a picture frame; the next key only wakes it", (tester) async {
      final controller = BandController(idleAfter: Duration(seconds: 10))..idleMode = IdleMode.frame;
      final button = FocusNode();
      await _pumpFrame(
        tester,
        controller,
        TextButton(focusNode: button, autofocus: true, onPressed: () {}, child: Text("tile")),
      );

      await tester.pump(Duration(seconds: 6));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(Duration(seconds: 6));
      expect(controller.idle, isFalse, reason: "a key press restarts the idle time");

      await tester.pump(Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(controller.idle, isTrue);
      expect(button.hasFocus, isFalse);
      expect(find.byKey(Key("idle-clock")), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.idle, isFalse);
      expect(button.hasFocus, isTrue, reason: "the waking key is consumed");
      expect(find.byKey(Key("idle-clock")), findsNothing);
      controller.dispose();
      button.dispose();
    });

    testWidgets("hiding the launcher while idle wakes the band, so keys reach the tiles again", (tester) async {
      final controller = BandController(idleAfter: Duration(seconds: 10))..idleMode = IdleMode.frame;
      final button = FocusNode();
      await _pumpFrame(
        tester,
        controller,
        TextButton(focusNode: button, autofocus: true, onPressed: () {}, child: Text("tile")),
      );
      await tester.pump(Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(button.hasFocus, isFalse);

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(controller.idle, isFalse);
      expect(button.hasFocus, isTrue);
      expect(find.byKey(Key("idle-clock")), findsNothing);
      controller.dispose();
      button.dispose();
    });

    testWidgets("Back wakes an idle band and ends the nudge mode before reaching the app", (tester) async {
      final controller = BandController(idleAfter: Duration(seconds: 1))..idleMode = IdleMode.dim;
      await tester.pump(Duration(seconds: 2));
      expect(controller.idle, isTrue);
      expect(await controller.didPopRoute(), isTrue);
      expect(controller.idle, isFalse);

      controller.startNudging();
      expect(await controller.didPopRoute(), isTrue);
      expect(controller.nudging, isFalse);

      expect(await controller.didPopRoute(), isFalse);
      controller.dispose();
    });

    testWidgets("with idle off nothing happens", (tester) async {
      final controller = BandController(idleAfter: Duration(seconds: 1));
      await tester.pump(Duration(seconds: 5));
      expect(controller.idle, isFalse);
      controller.dispose();
    });
  });

  group("BandController", () {
    final app = fakeApp(packageName: "app.one");
    final tile = Rect.fromLTWH(100, 300, 200, 112.5);

    Future<LaunchTransition> launchWith(LaunchMode mode, {double pixelRatio = 1}) async {
      final apps = MockAppsService();
      final controller = BandController()
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
      expect(await launchWith(LaunchMode.scaleBand), LaunchTransition.scaleUp(Rect.fromLTWH(0, 216, 960, 324)));
    });

    testWidgets("a grow launch lights the full frame as the app starts", (tester) async {
      final apps = MockAppsService();
      final controller = BandController()..launchMode = LaunchMode.growFade;

      final launching = controller.launch(apps, app, tile);
      expect(controller.expanded, isTrue);
      expect(controller.contentVisible, isFalse);
      expect(controller.animateExpansion, isTrue);
      verifyNever(apps.launchApp(any, any));
      await tester.pump(Motion.launch);
      await launching;
      verify(apps.launchApp(app, LaunchTransition.fade));
    });

    testWidgets("the frame darkens as it grows for an app and brightens as it settles back", (tester) async {
      final apps = MockAppsService();
      final controller = BandController()
        ..launchMode = LaunchMode.growCut
        ..returnMode = ReturnMode.collapse;
      await _pumpFrame(tester, controller, SizedBox());
      double level() => tester
          .widget<Opacity>(find.descendant(of: find.byType(BandFrame), matching: find.byType(Opacity)).first)
          .opacity;
      expect(level(), 1);

      final launching = controller.launch(apps, app, tile);
      await tester.pump();
      await tester.pump(controller.launchDuration);
      await launching;
      expect(level(), closeTo(1 - Tune.launchDim.defaultValue, 0.01));

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(level(), closeTo(1 - Tune.launchDim.defaultValue, 0.01));
      await tester.pumpAndSettle();
      expect(level(), 1);
      controller.dispose();
    });

    test("coming back from an app plays the chosen return", () {
      final apps = MockAppsService();
      final controller = BandController()..returnMode = ReturnMode.collapse;
      controller.launch(apps, app, tile);

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect((controller.expanded, controller.contentVisible, controller.animateExpansion), (true, false, false));

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect((controller.expanded, controller.contentVisible, controller.animateExpansion), (false, true, true));
    });

    test("without a launch, hiding and resuming leave the band alone", () {
      final controller = BandController()..returnMode = ReturnMode.collapse;

      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect((controller.expanded, controller.contentVisible), (false, true));
    });

    testWidgets("a repeating direction key switches to the hold spring until it is released", (tester) async {
      final controller = BandController();
      await tester.pumpWidget(Focus(autofocus: true, child: SizedBox()));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.holding, isFalse);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.holding, isTrue);
      expect(controller.focusSpring, controller.tuning.holdSpring);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(controller.holding, isFalse);
      expect(controller.focusSpring, controller.tuning.focusSpring);
      controller.dispose();
    });

    test("reduced motion, from the switch or from Android, drops the overshoot", () {
      final controller = BandController();
      expect(controller.focusSpring.overshoot, greaterThan(0));

      controller.reducedMotionSetting = true;
      expect(controller.reducedMotion, isTrue);
      expect(controller.focusSpring.overshoot, 0);

      controller.reducedMotionSetting = false;
      controller.systemReducedMotion = true;
      expect(controller.reducedMotion, isTrue);
      controller.dispose();
    });

    test("the config file keeps the choices", () async {
      final dir = await Directory.systemTemp.createTemp("band");
      final file = File("${dir.path}/band_config.json");
      final first = BandController(configFile: () async => file);
      first.geometry = BandGeometry(height: 0.5, position: 0.25, edge: BandEdge.hard);
      first.launchMode = LaunchMode.scaleTile;
      first.returnMode = ReturnMode.collapse;
      first.focusMotion = FocusMotion.ease;
      first.frameTimes = true;
      first.tuning[Tune.focusResponse] = 420;
      first.idleMode = IdleMode.dim;
      first.launchDuration = Duration(milliseconds: 500);
      first.returnDuration = Duration(milliseconds: 777);
      await Future.delayed(Duration(milliseconds: 50));

      final second = BandController(configFile: () async => file);
      await Future.delayed(Duration(milliseconds: 50));

      expect(second.geometry, first.geometry);
      expect(second.launchMode, LaunchMode.scaleTile);
      expect(second.returnMode, ReturnMode.collapse);
      expect(second.focusMotion, FocusMotion.ease);
      expect(second.frameTimes, isTrue);
      expect(second.tuning[Tune.focusResponse], 420);
      expect(second.idleMode, IdleMode.dim);
      expect(second.launchDuration, Duration(milliseconds: 500));
      expect(second.returnDuration, Duration(milliseconds: 780), reason: "lengths snap to 20 ms");
      expect(jsonDecode(await file.readAsString())["_doc"], contains("edge hard|soft|inset"));
      first.dispose();
      second.dispose();
      await dir.delete(recursive: true);
    });

    test("a v4 config without glide means jump", () async {
      final dir = await Directory.systemTemp.createTemp("band");
      final file = File("${dir.path}/band_config.json");
      await file.writeAsString(jsonEncode({"focusGlide": false}));
      final controller = BandController(configFile: () async => file);
      await Future.delayed(Duration(milliseconds: 50));

      expect(controller.focusMotion, FocusMotion.jump);
      controller.dispose();
      await dir.delete(recursive: true);
    });

    test("a pushed config applies without a restart", () async {
      final dir = await Directory.systemTemp.createTemp("band");
      final file = File("${dir.path}/band_config.json");
      final controller = BandController(configFile: () async => file);
      controller.tuning[Tune.focusOvershoot] = 0.1;
      await Future.delayed(Duration(milliseconds: 50));

      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      (json["tuning"] as Map<String, dynamic>)[Tune.focusOvershoot.key] = 0.2;
      await file.writeAsString(jsonEncode(json));
      await file.setLastModified(DateTime.now().add(Duration(seconds: 1)));
      await Future.delayed(Duration(milliseconds: 1300));

      expect(controller.tuning[Tune.focusOvershoot], 0.2);
      controller.dispose();
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
        home: SizedBox.expand(
          key: Key("probe"),
          child: Center(child: home),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
