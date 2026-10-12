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

import 'package:drift/drift.dart';
import 'package:tvlauncher/database.dart';
import 'package:tvlauncher/providers/apps_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

void main() {
  group("AppsService initialised correctly", () {
    test("with empty database creates the hero category", () async {
      final channel = MockLauncherChannel();
      final database = MockLauncherDatabase();
      when(channel.getApplications()).thenAnswer(
        (_) => Future.value([
          {
            'packageName': 'dev.neugebauer.tvlauncher',
            'name': 'Launcher',
            'version': null,
            'banner': null,
            'icon': null,
            'sideloaded': false,
          },
        ]),
      );
      when(database.listApplications()).thenAnswer(
        (_) => Future.value([fakeApp(packageName: "dev.neugebauer.tvlauncher", name: "Launcher", version: "1.0.0")]),
      );
      final hero = fakeCategory(name: "Main");
      var categoriesCreated = false;
      when(database.listCategoriesWithVisibleApps())
          .thenAnswer((_) => Future.value(categoriesCreated ? [CategoryWithApps(hero, [])] : []));
      when(database.insertCategory(any)).thenAnswer((_) async {
        categoriesCreated = true;
      });
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      final appsService = AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyInOrder([
        database.listApplications(),
        database.persistApps([
          AppsCompanion.insert(
            packageName: "dev.neugebauer.tvlauncher",
            name: "Launcher",
            version: "(unknown)",
            banner: Value(null),
            icon: Value(null),
            sideloaded: Value(false),
          ),
        ]),
        database.deleteApps([]),
        database.listCategoriesWithVisibleApps(),
        database.listApplications(),
        database.insertCategory(CategoriesCompanion.insert(name: "Main", order: 0)),
        database.listCategoriesWithVisibleApps(),
      ]);
      verifyNever(database.updateCategory(any, any));
      expect(appsService.heroCategory, hero);
      expect(appsService.heroApps, isEmpty);
      expect(appsService.gridApps.map((app) => app.packageName), ["dev.neugebauer.tvlauncher"]);
    });

    test("with an alphabetical first category switches it to manual", () async {
      final channel = MockLauncherChannel();
      final database = MockLauncherDatabase();
      final hero = fakeCategory(name: "Favorites", sort: CategorySort.alphabetical);
      when(channel.getApplications()).thenAnswer((_) => Future.value([]));
      when(database.listApplications()).thenAnswer((_) => Future.value([]));
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([CategoryWithApps(hero, [])]));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verify(database.updateCategory(hero.id, CategoriesCompanion(sort: Value(CategorySort.manual))));
      verifyNever(database.insertCategory(any));
    });

    test("with a manual first category writes nothing", () async {
      final channel = MockLauncherChannel();
      final database = MockLauncherDatabase();
      final hero = fakeCategory(name: "Main", sort: CategorySort.manual);
      when(channel.getApplications()).thenAnswer((_) => Future.value([]));
      when(database.listApplications()).thenAnswer((_) => Future.value([]));
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([CategoryWithApps(hero, [])]));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyNever(database.updateCategory(any, any));
      verifyNever(database.insertCategory(any));
    });

    test("with newly installed, uninstalled and existing apps", () async {
      final channel = MockLauncherChannel();
      final database = MockLauncherDatabase();
      when(channel.getApplications()).thenAnswer(
        (_) => Future.value([
          {
            'packageName': 'dev.neugebauer.tvlauncher',
            'name': 'Launcher',
            'version': '2.0.0',
            'banner': null,
            'icon': null,
            'sideloaded': false,
          },
          {
            'packageName': 'dev.neugebauer.tvlauncher.2',
            'name': 'Launcher 2',
            'version': '1.0.0',
            'banner': null,
            'icon': null,
            'sideloaded': false,
          },
        ]),
      );
      when(channel.applicationExists("uninstalled.app")).thenAnswer((_) => Future.value(false));
      when(channel.applicationExists("not.uninstalled.app")).thenAnswer((_) => Future.value(true));
      when(database.listApplications()).thenAnswer(
        (_) => Future.value([
          fakeApp(packageName: "dev.neugebauer.tvlauncher", name: "Launcher", version: "1.0.0"),
          fakeApp(packageName: "uninstalled.app", name: "Uninstalled Application", version: "1.0.0"),
          fakeApp(packageName: "not.uninstalled.app", name: "Not Uninstalled Application", version: "1.0.0"),
        ]),
      );
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyInOrder([
        database.listApplications(),
        database.persistApps([
          AppsCompanion.insert(
            packageName: "dev.neugebauer.tvlauncher",
            name: "Launcher",
            version: "2.0.0",
            banner: Value(null),
            icon: Value(null),
            sideloaded: Value(false),
          ),
          AppsCompanion.insert(
            packageName: "dev.neugebauer.tvlauncher.2",
            name: "Launcher 2",
            version: "1.0.0",
            banner: Value(null),
            icon: Value(null),
            sideloaded: Value(false),
          ),
        ]),
        database.deleteApps(["uninstalled.app"]),
        database.listCategoriesWithVisibleApps(),
        database.listApplications(),
      ]);
    });
  });

  test("launchApp calls channel", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.launchApp(app);
  });

  test("openAppInfo calls channel", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.openAppInfo(app);

    verify(channel.openAppInfo(app.packageName));
  });

  test("uninstallApp calls channel", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.uninstallApp(app);

    verify(channel.uninstallApp(app.packageName));
  });

  test("openSystemSettings calls channel with the screen name", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    when(channel.openSystemSettings("displaySound")).thenAnswer((_) => Future.value(true));

    expect(await appsService.openSystemSettings(SystemSettingsScreen.displaySound), isTrue);

    verify(channel.openSystemSettings("displaySound"));
  });

  test("isDefaultLauncher calls channel", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    when(channel.isDefaultLauncher()).thenAnswer((_) => Future.value(true));
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    final isDefaultLauncher = await appsService.isDefaultLauncher();

    verify(channel.isDefaultLauncher());
    expect(isDefaultLauncher, isTrue);
  });

  test("startAmbientMode calls channel", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    await appsService.startAmbientMode();

    verify(channel.startAmbientMode());
  });

  test("gridApps lists visible apps outside the hero, keeping alphabetical order", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final hero = fakeCategory(name: "Main");
    final inHero = fakeApp(packageName: "in.hero", name: "Netflix");
    when(channel.getApplications()).thenAnswer((_) => Future.value([]));
    when(channel.applicationExists(any)).thenAnswer((_) => Future.value(true));
    when(database.listApplications()).thenAnswer(
      (_) => Future.value([
        fakeApp(packageName: "a.app", name: "Arte"),
        fakeApp(packageName: "hidden.app", name: "Hidden", hidden: true),
        inHero,
        fakeApp(packageName: "z.app", name: "Zattoo"),
      ]),
    );
    when(database.listCategoriesWithVisibleApps()).thenAnswer(
      (_) => Future.value([
        CategoryWithApps(hero, [inHero]),
      ]),
    );
    when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
    final appsService = AppsService(channel, database);
    await untilCalled(channel.addAppsChangedListener(any));

    expect(appsService.heroApps.map((app) => app.packageName), ["in.hero"]);
    expect(appsService.gridApps.map((app) => app.packageName), ["a.app", "z.app"]);
  });

  test("addToHero appends to the hero category and removes the app from the grid", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final hero = fakeCategory(name: "Main");
    final app = fakeApp(packageName: "app.to.be.added");
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [CategoryWithApps(hero, [])],
      applications: [app],
    );
    when(database.nextAppCategoryOrder(hero.id)).thenAnswer((_) => Future.value(0));
    when(database.listCategoriesWithVisibleApps()).thenAnswer(
      (_) => Future.value([
        CategoryWithApps(hero, [app]),
      ]),
    );
    expect(appsService.gridApps, [app]);

    await appsService.addToHero(app);

    verify(
      database.insertAppsCategories([
        AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: app.packageName, order: 0),
      ]),
    );
    expect(appsService.heroApps, [app]);
    expect(appsService.gridApps, isEmpty);
  });

  test("removeFromHero deletes the membership and the app reappears in the grid", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final hero = fakeCategory(name: "Main");
    final app = fakeApp(packageName: "app.in.hero");
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [
        CategoryWithApps(hero, [app]),
      ],
      applications: [app],
    );
    when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([CategoryWithApps(hero, [])]));
    expect(appsService.gridApps, isEmpty);

    await appsService.removeFromHero(app);

    verify(database.deleteAppCategory(hero.id, app.packageName));
    expect(appsService.heroApps, isEmpty);
    expect(appsService.gridApps, [app]);
  });

  test("reorderHero and saveHeroOrder persist the in-memory hero order", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final hero = fakeCategory(name: "Main");
    final appsService = await _buildInitialisedAppsService(channel, database, [
      CategoryWithApps(hero, [fakeApp(packageName: "app.1"), fakeApp(packageName: "app.2")]),
    ]);

    appsService.reorderHero(0, 1);
    expect(appsService.heroApps.map((app) => app.packageName), ["app.2", "app.1"]);
    await appsService.saveHeroOrder();

    verify(
      database.replaceAppsCategories([
        AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: "app.2", order: 0),
        AppsCategoriesCompanion.insert(categoryId: hero.id, appPackageName: "app.1", order: 1),
      ]),
    );
  });

  test("addToCategory adds app to category", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final category = fakeCategory(name: "Category");
    when(database.nextAppCategoryOrder(category.id)).thenAnswer((_) => Future.value(1));

    await appsService.addToCategory(fakeApp(packageName: "app.to.be.added"), category);

    verify(
      database.insertAppsCategories([
        AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.to.be.added", order: 1),
      ]),
    );
    verify(database.listCategoriesWithVisibleApps());
  });

  test("removeFromCategory removes app from category", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp(packageName: "app.to.be.added");
    final category = fakeCategory(name: "Category");

    await appsService.removeFromCategory(app, category);

    verify(database.deleteAppCategory(category.id, app.packageName));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("saveOrderInCategory persists apps order from memory to database", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final category = fakeCategory(name: "Category");
    final appsService = await _buildInitialisedAppsService(channel, database, [
      CategoryWithApps(category, [fakeApp(packageName: "app.1"), fakeApp(packageName: "app.2")]),
    ]);

    await appsService.saveOrderInCategory(category);

    verify(
      database.replaceAppsCategories([
        AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.1", order: 0),
        AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.2", order: 1),
      ]),
    );
    verify(database.listCategoriesWithVisibleApps());
  });

  test("reorderApplication changes application order in-memory", () async {
    final channel = MockLauncherChannel();
    final database = MockLauncherDatabase();
    final category = fakeCategory(name: "Category");
    final appsService = await _buildInitialisedAppsService(channel, database, [
      CategoryWithApps(category, [fakeApp(packageName: "app.1"), fakeApp(packageName: "app.2")]),
    ]);

    appsService.reorderApplication(category, 1, 0);

    expect(appsService.categoriesWithApps[0].applications[0].packageName, "app.2");
    expect(appsService.categoriesWithApps[0].applications[1].packageName, "app.1");
  });

  test("hideApplication hides application", () async {
    final database = MockLauncherDatabase();
    final application = fakeApp();
    final appsService = await _buildInitialisedAppsService(MockLauncherChannel(), database, []);
    when(database.listApplications()).thenAnswer((_) => Future.value([application]));

    await appsService.hideApplication(application);

    verify(database.updateApp(application.packageName, AppsCompanion(hidden: Value(true))));
    verify(database.listCategoriesWithVisibleApps());
    verify(database.listApplications());
    expect(appsService.applications, [application]);
  });

  test("unHideApplication hides application", () async {
    final database = MockLauncherDatabase();
    final application = fakeApp();
    final appsService = await _buildInitialisedAppsService(MockLauncherChannel(), database, []);

    await appsService.unHideApplication(application);

    verify(database.updateApp(application.packageName, AppsCompanion(hidden: Value(false))));
    verify(database.listCategoriesWithVisibleApps());
    verify(database.listApplications());
  });
}

Future<AppsService> _buildInitialisedAppsService(
  MockLauncherChannel channel,
  MockLauncherDatabase database,
  List<CategoryWithApps> categoriesWithApps, {
  List<App> applications = const [],
}) async {
  when(channel.getApplications()).thenAnswer((_) => Future.value([]));
  when(channel.applicationExists(any)).thenAnswer((_) => Future.value(true));
  when(database.listApplications()).thenAnswer((_) => Future.value(applications));
  when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value(categoriesWithApps));
  when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
  final appsService = AppsService(channel, database);
  await untilCalled(channel.addAppsChangedListener(any));
  clearInteractions(channel);
  clearInteractions(database);
  return appsService;
}
