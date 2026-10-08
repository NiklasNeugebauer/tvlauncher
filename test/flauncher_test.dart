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
import 'package:flauncher/flauncher.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/home_focus.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
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
    binding.window.physicalSizeTestValue = Size(960, 540);
    binding.window.devicePixelRatioTestValue = 1.0;
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
    expect(tester.widget(find.byKey(Key("background"))), isA<Container>());
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

  testWidgets("Down from the hero focuses the nearest tile of the first grid row and scrolls the hero out of view",
      (tester) async {
    // Two hero tiles: the left one sits above the second and third grid columns.
    final appsService =
        _appsService(hero: [_app("hero.1"), _app("hero.2")], grid: List.generate(12, (i) => _app("grid.$i")));
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

  testWidgets("Up from the hero reaches the settings icon", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: []);
    await _pumpHome(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(Focus.of(findSettingsIcon(tester)!).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(QuickSettingsPage), findsOneWidget);
  });

  testWidgets("focusFirstTile returns from deep in the grid to the first hero tile at the top", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: List.generate(30, (i) => _app("grid.$i")));
    final controller = await _pumpHome(tester, appsService);

    for (int i = 0; i < 4; ++i) {
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
    when(database.listCategoriesWithVisibleApps())
        .thenAnswer((_) => Future.value([CategoryWithApps(hero, [first, second])]));
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
    expect(tester.getRect(find.byKey(Key("hero-hero.1"))).left,
        greaterThan(tester.getRect(find.byKey(Key("hero-hero.2"))).left));
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);
    verify(database.replaceAppsCategories([
      AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: "hero.2", order: 0),
      AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: "hero.1", order: 1),
    ]));
    verifyNever(channel.launchApp(any));
  });

  testWidgets("Home closes an open panel, ends move mode and focuses the first hero tile", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1"), _app("hero.2")], grid: []);
    final controller = await _pumpHome(tester, appsService);
    final homePressed = verify(appsService.setPlatformHandlers(
            onHomePressed: captureAnyNamed("onHomePressed"), onQuickSettingsPressed: anyNamed("onQuickSettingsPressed")))
        .captured
        .single as void Function();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.longPress(find.byKey(Key("hero-hero.2")));
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationInfoPanel), findsOneWidget);

    homePressed();
    await tester.pumpAndSettle();
    expect(find.byType(ApplicationInfoPanel), findsNothing);
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.longPress(find.byKey(Key("hero-hero.2")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Move"));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsOneWidget);

    homePressed();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNothing);
    verify(appsService.saveHeroOrder());
    expect(_hasFocus(tester, "hero-hero.1"), isTrue);
    expect(controller.scroll.offset, 0);
  });

  testWidgets("Long-pressed mute opens the quick settings panel once", (tester) async {
    final appsService = _appsService(hero: [_app("hero.1")], grid: []);
    await _pumpHome(tester, appsService);
    final quickSettingsPressed = verify(appsService.setPlatformHandlers(
            onHomePressed: anyNamed("onHomePressed"), onQuickSettingsPressed: captureAnyNamed("onQuickSettingsPressed")))
        .captured
        .single as void Function();

    quickSettingsPressed();
    await tester.pumpAndSettle();
    quickSettingsPressed();
    await tester.pumpAndSettle();

    expect(find.byType(QuickSettingsPage), findsOneWidget);
  });

  testWidgets("Select launches on release; a hold moves a hero tile, a longer hold opens its panel", (tester) async {
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
    expect(find.byType(ApplicationInfoPanel), findsOneWidget);
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

  testWidgets("Home page displays background image", (tester) async {
    final appsService = _appsService(hero: [], grid: []);
    final wallpaperService = MockWallpaperService();
    when(wallpaperService.wallpaperBytes).thenReturn(kTransparentImage);
    when(wallpaperService.gradient).thenReturn(FLauncherGradients.greatWhale);

    await _pumpHome(tester, appsService, wallpaperService: wallpaperService);

    expect(tester.widget(find.byKey(Key("background"))), isA<Image>());
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

bool _hasFocus(WidgetTester tester, String key) => tester
    .widget<InkWell>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkWell)))
    .focusNode!
    .hasFocus;

Future<HomeFocusController> _pumpHome(
  WidgetTester tester,
  AppsService appsService, {
  WallpaperService? wallpaperService,
}) async {
  if (wallpaperService == null) {
    wallpaperService = MockWallpaperService();
    when(wallpaperService.wallpaperBytes).thenReturn(null);
    when(wallpaperService.gradient).thenReturn(FLauncherGradients.greatWhale);
  }
  // Not disposed: the controller's focus nodes live in the tree until the next pumpWidget replaces it.
  final controller = HomeFocusController();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaperService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        ChangeNotifierProvider<SettingsService>.value(value: MockSettingsService()),
        Provider<HomeFocusController>.value(value: controller),
      ],
      builder: (_, __) => MaterialApp(home: FLauncher()),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}
