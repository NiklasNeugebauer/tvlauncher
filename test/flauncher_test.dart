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

import 'package:flauncher/actions.dart';
import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher.dart';
import 'package:flauncher/home_focus.dart';
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/sound/ui_sounds.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/focus_glide.dart';
import 'package:flauncher/widgets/home_layout.dart';
import 'package:flauncher/widgets/settings/quick_settings_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:transparent_image/transparent_image.dart';

import 'helpers.dart';
import 'mocks.dart';
import 'mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(960, 540);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("Home page shows the hero row, the Apps heading and the grid", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: [_app("grid.1"), _app("grid.2")]);

    await _pumpHome(tester, appsService);

    expect(find.byKey(Key("hero-hero.1")), findsOneWidget);
    expect(find.text("Apps"), findsOneWidget);
    expect(find.byKey(Key("grid-grid.1")), findsOneWidget);
    expect(find.byKey(Key("grid-grid.2")), findsOneWidget);
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    expect(_hasFocus(tester, "grid-grid.1"), isFalse);
  });

  testWidgets("Empty hero shows a hint and focuses the first grid tile", (tester) async {
    final appsService = _appsService(hero: [], grid: [_app("grid.1"), _app("grid.2")]);

    await _pumpHome(tester, appsService);

    expect(find.byKey(Key("hero-empty")), findsOneWidget);
    expect(_hasFocus(tester, "grid-grid.1"), isTrue);
  });

  testWidgets("Hero tiles fill the width with four apps and shrink to fit with more", (tester) async {
    final four = _appsService(hero: List.generate(4, (i) => _app("hero.$i")), grid: []);
    await _pumpHome(tester, four);
    final width = 960 - 2 * HomeLayout.sidePadding;
    expect(tester.getSize(find.byKey(Key("hero-hero.0"))).width, closeTo((width - 3 * HomeLayout.gap) / 4, 0.01));

    final eight = _appsService(hero: List.generate(8, (i) => _app("hero.$i")), grid: []);
    await _pumpHome(tester, eight);
    final tileWidth = tester.getSize(find.byKey(Key("hero-hero.0"))).width;
    expect(tileWidth, closeTo((width - 7 * HomeLayout.gap) / 8, 0.01));
    expect(tester.getRect(find.byKey(Key("hero-hero.7"))).right, lessThanOrEqualTo(960 - HomeLayout.sidePadding));
    expect(tester.getRect(find.byKey(Key("hero-hero.7"))).top, tester.getRect(find.byKey(Key("hero-hero.0"))).top);
  });

  testWidgets("The first grid row peeks in below the hero on the initial view", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: List.generate(12, (i) => _app("grid.$i")));

    await _pumpHome(tester, appsService);

    final firstRow = tester.getRect(find.byKey(Key("grid-grid.0")));
    expect(firstRow.top, lessThan(540));
    expect(firstRow.bottom, greaterThan(540));
    expect(tester.getRect(find.byKey(Key("grid-grid.6"))).top, greaterThan(540));
  });

  testWidgets("Down from the hero focuses the nearest tile of the first grid row and scrolls the hero out of view", (
    tester,
  ) async {
    // Two hero tiles: the left one sits above the second and third grid columns.
    final appsService = _appsService(
      hero: [_app("hero.1"), _app("hero.2")],
      grid: List.generate(12, (i) => _app("grid.$i")),
    );
    final controller = await _pumpHome(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(controller.gridHasFocus, isTrue);
    expect(_hasFocus(tester, "grid-grid.1") || _hasFocus(tester, "grid-grid.2"), isTrue);
    expect(controller.scroll.offset, closeTo(controller.heroZoneHeight, 0.5));
    expect(tester.getRect(find.byKey(Key("hero-hero.1"))).bottom, lessThanOrEqualTo(56));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    expect(controller.scroll.offset, 0);
  });

  testWidgets("Up and down inside the grid move one row at a time, left and right stay on the row", (tester) async {
    final appsService = _appsService(hero: [], grid: List.generate(14, (i) => _app("grid.$i")));
    await _pumpHome(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, "grid-grid.7"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, "grid-grid.13"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, "grid-grid.13"), isTrue);
  });

  testWidgets("Right at the end of the hero nudges the tile and springs it back", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: []);
    await _pumpHome(tester, appsService);
    final rest = _tileRect(tester, "hero-hero.1");

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(Duration(milliseconds: 60));
    expect(_tileRect(tester, "hero-hero.1").left, greaterThan(rest.left + 4));

    await tester.pumpAndSettle();
    expect(_tileRect(tester, "hero-hero.1"), rest);
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
  });

  testWidgets("Up from the grid goes to the hero tile above the focused column", (tester) async {
    final appsService = _appsService(
      hero: [_app("hero.1"), _app("hero.2"), _app("hero.3")],
      grid: List.generate(12, (i) => _app("grid.$i")),
    );
    await _pumpHome(tester, appsService);

    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowUp,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
  });

  testWidgets("Down into the grid and straight back up returns to the same hero tile", (tester) async {
    final appsService = _appsService(
      hero: [_app("hero.1"), _app("hero.2"), _app("hero.3"), _app("hero.4"), _app("hero.5")],
      grid: List.generate(12, (i) => _app("grid.$i")),
    );
    await _pumpHome(tester, appsService);

    for (var index = 1; index <= 5; ++index) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_hasFocus(tester, "hero-hero.$index"), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
  });

  testWidgets("A held select shrinks the focused tile until it is released", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: []);
    await _pumpHome(tester, appsService);
    final focused = _tileRect(tester, "hero-hero.1");

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_tileRect(tester, "hero-hero.1").width, closeTo(focused.width * Tune.pressScale.defaultValue, 0.5));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(_tileRect(tester, "hero-hero.1").width, closeTo(focused.width, 0.01));
  });

  testWidgets("Left from the settings icon returns to the hero tile focused last", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1"), _app("hero.2"), _app("hero.3")], grid: []);
    await _pumpHome(tester, appsService);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(Focus.of(findSettingsIcon(tester)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-hero.2"), isTrue);
  });

  testWidgets("Down from the settings icon returns to the hero tile focused last", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1"), _app("hero.2"), _app("hero.3")], grid: []);
    await _pumpHome(tester, appsService);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-hero.2"), isTrue);
  });

  testWidgets("Up from the grid into the hero blips", (tester) async {
    final channel = MockFLauncherChannel();
    when(channel.playSound(any, rate: anyNamed("rate"), volume: anyNamed("volume"))).thenAnswer((_) async {});
    final band = BandController();
    final appsService = _appsService(hero: [_app("hero.1")], grid: [_app("grid.1"), _app("grid.2")]);
    await _pumpHome(tester, appsService, band: band, sounds: UiSounds(channel, band));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    clearInteractions(channel);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    verify(channel.playSound("focus", rate: anyNamed("rate"), volume: anyNamed("volume"))).called(1);
    await tester.pumpWidget(SizedBox());
    band.dispose();
  });

  testWidgets("Up from the hero reaches the settings icon", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: []);
    await _pumpHome(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(Focus.of(findSettingsIcon(tester)).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(QuickSettingsPage), findsOneWidget);
  });

  testWidgets("focusFirstTile returns from deep in the grid to the first hero tile at the top", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: List.generate(30, (i) => _app("grid.$i")));
    final controller = await _pumpHome(tester, appsService);

    for (int i = 0; i < 6; ++i) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(controller.gridHasFocus, isTrue);
    expect(controller.scroll.offset, greaterThan(controller.heroZoneHeight));

    controller.focusFirstTile();
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    expect(controller.scroll.offset, 0);
  });

  testWidgets("Long pressing a grid tile opens the panel and 'Add to main apps' calls AppsService", (tester) async {
    final app = _app("grid.1");
    final appsService = _appsService(hero: [_app("hero.1")], grid: [app]);
    await _pumpHome(tester, appsService);
    // Scroll the grid into view first; the peeking row is only partly inside the viewport.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(Key("grid-grid.1")));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationInfoPanel), findsOneWidget);
    expect(find.text("Add to main apps"), findsOneWidget);
    expect(find.text("Move"), findsNothing);

    await tester.tap(find.text("Add to main apps"));
    await tester.pumpAndSettle();
    verify(appsService.addToHero(app));
    expect(find.byType(ApplicationInfoPanel), findsNothing);
  });

  testWidgets("A held select moves a hero tile with left/right and saves on select", (tester) async {
    // A real AppsService over mocked channel and database, so the reorder rebuilds the row like on the device.
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final hero = fakeCategory(name: "Main");
    final first = _app("hero.1");
    final second = _app("hero.2");
    when(channel.getApplications()).thenAnswer((_) => Future.value([]));
    when(channel.applicationExists(any)).thenAnswer((_) => Future.value(true));
    when(database.listApplications()).thenAnswer((_) => Future.value([first, second]));
    when(database.listCategoriesWithVisibleApps()).thenAnswer(
      (_) => Future.value([
        CategoryWithApps(hero, [first, second]),
      ]),
    );
    when(database.transaction(any)).thenAnswer((invocation) => invocation.positionalArguments[0]());
    final appsService = AppsService(channel, database);
    await untilCalled(channel.addAppsChangedListener(any));
    await _pumpHome(tester, appsService);
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(Key("hero-hero.1"))).left,
      greaterThan(tester.getRect(find.byKey(Key("hero-hero.2"))).left),
    );
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);
    verify(
      database.replaceAppsCategories([
        AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: "hero.2", order: 0),
        AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: "hero.1", order: 1),
      ]),
    );
    verifyNever(channel.launchApp(any));
  });

  testWidgets("Adding a grid app to the main apps focuses its new hero tile in move mode", (tester) async {
    final appsService = await _realAppsService(hero: ["hero.1"], grid: ["grid.1"]);
    await _pumpHome(tester, appsService);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(Key("grid-grid.1")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Add to main apps"));
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-grid.1"), isTrue);
    expect(
      find.descendant(of: find.byKey(Key("hero-grid.1")), matching: find.byIcon(Icons.keyboard_arrow_left)),
      findsOneWidget,
    );
  });

  testWidgets("A very long select on a main app moves it down and focuses its hero neighbour", (tester) async {
    final appsService = await _realAppsService(hero: ["hero.1", "hero.2", "hero.3"], grid: []);
    await _pumpHome(tester, appsService);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 1000));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byKey(Key("grid-hero.2")), findsOneWidget);
    expect(find.byType(ApplicationInfoPanel), findsNothing);
    expect(_hasFocus(tester, "hero-hero.3"), isTrue);
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);
  });

  testWidgets("With a band, focus stays in a panel opened from a grid tile", (tester) async {
    final band = BandController();
    final appsService = _appsService(hero: [_app("hero.1")], grid: [_app("grid.1"), _app("grid.2")]);
    when(appsService.isDefaultLauncher()).thenAnswer((_) async => true);
    await _pumpHome(tester, appsService, band: band);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final tile = FocusManager.instance.primaryFocus;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(focused.findAncestorWidgetOfExactType<ApplicationInfoPanel>(), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, tile);
    await tester.pumpWidget(SizedBox());
    band.dispose();
  });

  testWidgets("Starting move mode shrinks the ring with the tile, and a moved tile takes the light along", (
    tester,
  ) async {
    final band = BandController();
    final appsService = await _realAppsService(hero: ["hero.1", "hero.2"], grid: []);
    await _pumpHome(tester, appsService, band: band);
    await tester.pumpAndSettle();
    final glide = tester.state<FocusGlideState>(find.byType(FocusGlide));
    Rect ring() => glide.ringRect!.shift(tester.getTopLeft(find.byType(FocusGlide)));
    expect(ring(), _tileRect(tester, "hero-hero.1"));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final moving = _tileRect(tester, "hero-hero.1");
    expect(moving.width, lessThan(tester.getSize(find.byKey(Key("hero-hero.1"))).width + 0.5));
    expect(ring(), moving);

    var lightMoves = 0;
    band.spotlight.addListener(() => lightMoves++);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(lightMoves, greaterThan(0));
    expect(band.spotlight.tile, isNotNull);
    expect(ring(), _tileRect(tester, "hero-hero.1"));
    await tester.pumpWidget(SizedBox());
    band.dispose();
  });

  testWidgets("Repeats of a select pressed elsewhere do not start move mode", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1"), _app("hero.2")], grid: []);
    await _pumpHome(tester, appsService);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    tester
        .widget<InkWell>(find.descendant(of: find.byKey(Key("hero-hero.2")), matching: find.byType(InkWell)))
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-hero.2"), isTrue);
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);
    expect(find.byType(ApplicationInfoPanel), findsNothing);
  });

  testWidgets("Home closes an open panel, ends move mode and focuses the first hero tile", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1"), _app("hero.2")], grid: [_app("grid.1")]);
    final controller = await _pumpHome(tester, appsService);
    final homePressed =
        verify(
              appsService.setPlatformHandlers(
                onHomePressed: captureAnyNamed("onHomePressed"),
                onQuickSettingsPressed: anyNamed("onQuickSettingsPressed"),
              ),
            ).captured.single
            as void Function(bool);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(Key("grid-grid.1")));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationInfoPanel), findsOneWidget);

    homePressed(false);
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationInfoPanel), findsNothing);
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);

    homePressed(false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);
    verify(appsService.saveHeroOrder());
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    expect(controller.scroll.offset, 0);
  });

  testWidgets("Home from inside an app keeps focus on the tile that launched it", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1"), _app("hero.2")], grid: [_app("grid.1"), _app("grid.2")]);
    final controller = await _pumpHome(tester, appsService);
    final homePressed =
        verify(
              appsService.setPlatformHandlers(
                onHomePressed: captureAnyNamed("onHomePressed"),
                onQuickSettingsPressed: anyNamed("onQuickSettingsPressed"),
              ),
            ).captured.single
            as void Function(bool);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final offset = controller.scroll.offset;

    homePressed(true);
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "grid-grid.2"), isTrue);
    expect(controller.scroll.offset, offset);
  });

  testWidgets("Long-pressed mute opens the quick settings panel once", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: []);
    await _pumpHome(tester, appsService);
    final quickSettingsPressed =
        verify(
              appsService.setPlatformHandlers(
                onHomePressed: anyNamed("onHomePressed"),
                onQuickSettingsPressed: captureAnyNamed("onQuickSettingsPressed"),
              ),
            ).captured.single
            as void Function();

    quickSettingsPressed();
    await tester.pumpAndSettle();
    quickSettingsPressed();
    await tester.pumpAndSettle();

    expect(find.byType(QuickSettingsPage), findsOneWidget);
  });

  testWidgets("Select launches on release; a hold moves a hero tile, a longer hold moves it down", (tester) async {
    final hero1 = _app("hero.1");
    final appsService = _appsService(hero: [hero1, _app("hero.2")], grid: []);
    await _pumpHome(tester, appsService);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verify(appsService.launchApp(hero1));
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);
    expect(find.byType(ApplicationInfoPanel), findsNothing);
    verifyNever(appsService.launchApp(any));

    await tester.pump(Duration(milliseconds: 1000));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verify(appsService.removeFromHero(hero1));
    expect(find.byType(ApplicationInfoPanel), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verifyNever(appsService.launchApp(any));
    verifyNever(appsService.saveHeroOrder());
  });

  testWidgets("A held select on a grid tile opens its panel without launching", (tester) async {
    final appsService = _appsService(hero: [], grid: [_app("grid.1"), _app("grid.2")]);
    await _pumpHome(tester, appsService);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(Duration(milliseconds: 600));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byType(ApplicationInfoPanel), findsOneWidget);
    expect(find.text("Add to main apps"), findsOneWidget);
    verifyNever(appsService.launchApp(any));
  });

  testWidgets("Tapping on app launches it", (tester) async {
    final app = _app("hero.1");
    final appsService = _appsService(hero: [app], grid: []);
    await _pumpHome(tester, appsService);

    await tester.tap(find.byKey(Key("hero-hero.1")));
    await tester.pumpAndSettle();

    verify(appsService.launchApp(app));
  });

  testWidgets("Hovering over app focuses it", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1"), _app("hero.2")], grid: []);
    await _pumpHome(tester, appsService);
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(() => gesture.removePointer());
    await gesture.moveTo(tester.getCenter(find.byKey(Key("hero-hero.2"))));
    await tester.pumpAndSettle();

    expect(_hasFocus(tester, "hero-hero.1"), isFalse);
    expect(_hasFocus(tester, "hero-hero.2"), isTrue);
  });
}

App _app(String packageName) => fakeApp(
  packageName: packageName,
  name: packageName,
  version: "1.0.0",
  banner: kTransparentImage,
  icon: kTransparentImage,
);

MockAppsService _appsService({required List<App> hero, required List<App> grid}) {
  final appsService = MockAppsService();
  when(appsService.initialized).thenReturn(true);
  when(appsService.heroApps).thenReturn(hero);
  when(appsService.gridApps).thenReturn(grid);
  when(appsService.applications).thenReturn([...hero, ...grid]);
  return appsService;
}

// A real AppsService over a mocked channel and an in-memory hero, so adding and removing rebuild the home screen.
Future<AppsService> _realAppsService({required List<String> hero, required List<String> grid}) async {
  final channel = MockFLauncherChannel();
  final database = MockFLauncherDatabase();
  final category = fakeCategory(name: "Main");
  final apps = {
    for (final name in [...hero, ...grid]) name: _app(name),
  };
  final heroApps = [for (final name in hero) apps[name]!];
  when(channel.getApplications()).thenAnswer((_) => Future.value([]));
  when(channel.applicationExists(any)).thenAnswer((_) => Future.value(true));
  when(database.listApplications()).thenAnswer((_) => Future.value(apps.values.toList()));
  when(database.listCategoriesWithVisibleApps())
      .thenAnswer((_) => Future.value([CategoryWithApps(category, List.of(heroApps))]));
  when(database.transaction(any)).thenAnswer((invocation) => invocation.positionalArguments[0]());
  when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(heroApps.length));
  when(database.insertAppsCategories(any)).thenAnswer((invocation) async {
    for (final row in invocation.positionalArguments[0] as List<AppsCategoriesCompanion>) {
      heroApps.add(apps[row.appPackageName.value]!);
    }
  });
  when(database.deleteAppCategory(any, any)).thenAnswer((invocation) async {
    heroApps.removeWhere((app) => app.packageName == invocation.positionalArguments[1]);
  });
  final appsService = AppsService(channel, database);
  await untilCalled(channel.addAppsChangedListener(any));
  return appsService;
}

// The tile as drawn, with its lift, scale and nudge.
Rect _tileRect(WidgetTester tester, String key) =>
    tester.getRect(find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)));

bool _hasFocus(WidgetTester tester, String key) => tester
    .widget<InkWell>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)))
    .focusNode!
    .hasFocus;

Future<HomeFocusController> _pumpHome(
  WidgetTester tester,
  AppsService appsService, {
  WallpaperService? wallpaperService,
  BandController? band,
  UiSounds? sounds,
}) async {
  if (wallpaperService == null) {
    wallpaperService = MockWallpaperService();
    when(wallpaperService.wallpaperBytes).thenReturn(null);
  }
  // Not disposed: the controller's focus nodes live in the tree until the next pumpWidget replaces it.
  final controller = HomeFocusController();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaperService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        Provider<HomeFocusController>.value(value: controller),
        if (sounds != null) Provider<UiSounds>.value(value: sounds),
      ],
      builder: (context, _) => MaterialApp(
        actions: {...WidgetsApp.defaultActions, DirectionalFocusIntent: SoundFeedbackDirectionalFocusAction(context)},
        builder: (context, child) => band == null ? child! : BandScope(controller: band, child: child!),
        home: FLauncher(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}
