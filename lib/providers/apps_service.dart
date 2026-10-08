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

import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';

/// System settings screens the launcher deep-links to. Names are the strings the platform side switches on.
enum SystemSettingsScreen { bluetooth, wifi, displaySound, all }

class AppsService extends ChangeNotifier {
  final FLauncherChannel _fLauncherChannel;
  final FLauncherDatabase _database;
  bool _initialized = false;

  List<App> _applications = [];
  List<CategoryWithApps> _categoriesWithApps = [];
  List<App> _gridApps = [];

  bool get initialized => _initialized;

  List<App> get applications => UnmodifiableListView(_applications);

  List<CategoryWithApps> get categoriesWithApps => _categoriesWithApps
      .map((item) => CategoryWithApps(item.category, UnmodifiableListView(item.applications)))
      .toList(growable: false);

  /// The "main apps" row: the category with the lowest order. Null only before [_ensureHeroCategory] has run.
  Category? get heroCategory => _categoriesWithApps.isEmpty ? null : _categoriesWithApps.first.category;

  List<App> get heroApps =>
      _categoriesWithApps.isEmpty ? const [] : UnmodifiableListView(_categoriesWithApps.first.applications);

  /// Every visible app that is not in the hero, alphabetically. Derived, never stored.
  List<App> get gridApps => UnmodifiableListView(_gridApps);

  AppsService(this._fLauncherChannel, this._database) {
    _init();
  }

  Future<void> _init() async {
    await _refreshState(shouldNotifyListeners: false);
    await _ensureHeroCategory();
    _fLauncherChannel.addAppsChangedListener((event) async {
      switch (event["action"]) {
        case "PACKAGE_ADDED":
        case "PACKAGE_CHANGED":
          await _database.persistApps([_buildAppCompanion(event["activitiyInfo"])]);
          break;
        case "PACKAGES_AVAILABLE":
          await _database.persistApps((event["activitiesInfo"] as List<dynamic>).map(_buildAppCompanion).toList());
          break;
        case "PACKAGE_REMOVED":
          await _database.deleteApps([event["packageName"]]);
          break;
      }
      _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
      _applications = await _database.listApplications();
      _recomputeGridApps();
      notifyListeners();
    });
    _initialized = true;
    notifyListeners();
  }

  AppsCompanion _buildAppCompanion(dynamic data) => AppsCompanion(
    packageName: Value(data["packageName"]),
    name: Value(data["name"]),
    version: Value(data["version"] ?? "(unknown)"),
    banner: Value(data["banner"]),
    icon: Value(data["icon"]),
    hidden: Value.absent(),
    sideloaded: Value(data["sideloaded"]),
  );

  /// Runs on every start so a database without categories (fresh install, or all deleted) always ends up with a
  /// hero category, and a hero created by older code is ordered manually.
  Future<void> _ensureHeroCategory() async {
    if (_categoriesWithApps.isEmpty) {
      await _database.insertCategory(CategoriesCompanion.insert(name: "Main", order: 0));
      _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    } else if (_categoriesWithApps.first.category.sort != CategorySort.manual) {
      await _database.updateCategory(
        _categoriesWithApps.first.category.id,
        CategoriesCompanion(sort: Value(CategorySort.manual)),
      );
      _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    }
    _recomputeGridApps();
  }

  void _recomputeGridApps() {
    final heroPackages = heroApps.map((app) => app.packageName).toSet();
    _gridApps = _applications.where((app) => !app.hidden && !heroPackages.contains(app.packageName)).toList();
  }

  Future<void> _refreshState({bool shouldNotifyListeners = true}) async {
    await _database.transaction(() async {
      final appsFromSystem = (await _fLauncherChannel.getApplications()).map(_buildAppCompanion).toList();

      final appsRemovedFromSystem = (await _database.listApplications())
          .where((app) => !appsFromSystem.any((systemApp) => systemApp.packageName.value == app.packageName))
          .map((app) => app.packageName)
          .toList();

      final List<String> uninstalledApplications = [];
      await Future.forEach(appsRemovedFromSystem, (String packageName) async {
        if (!(await _fLauncherChannel.applicationExists(packageName))) {
          uninstalledApplications.add(packageName);
        }
      });

      await _database.persistApps(appsFromSystem);
      await _database.deleteApps(uninstalledApplications);

      _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
      _applications = await _database.listApplications();
    });
    _recomputeGridApps();
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> launchApp(App app) => _fLauncherChannel.launchApp(app.packageName);

  Future<void> openAppInfo(App app) => _fLauncherChannel.openAppInfo(app.packageName);

  Future<void> uninstallApp(App app) => _fLauncherChannel.uninstallApp(app.packageName);

  Future<bool> openSystemSettings(SystemSettingsScreen screen) => _fLauncherChannel.openSystemSettings(screen.name);

  Future<bool> isDefaultLauncher() => _fLauncherChannel.isDefaultLauncher();

  Future<void> startAmbientMode() => _fLauncherChannel.startAmbientMode();

  void setPlatformHandlers({required void Function() onHomePressed, required void Function() onQuickSettingsPressed}) =>
      _fLauncherChannel.setPlatformHandlers(
        onHomePressed: onHomePressed,
        onQuickSettingsPressed: onQuickSettingsPressed,
      );

  Future<void> addToHero(App app) => addToCategory(app, heroCategory!);

  Future<void> removeFromHero(App app) => removeFromCategory(app, heroCategory!);

  void reorderHero(int oldIndex, int newIndex) => reorderApplication(heroCategory!, oldIndex, newIndex);

  Future<void> saveHeroOrder() => saveOrderInCategory(heroCategory!);

  Future<void> addToCategory(App app, Category category, {bool shouldNotifyListeners = true}) async {
    int index = await _database.nextAppCategoryOrder(category.id) ?? 0;
    await _database.insertAppsCategories([
      AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: app.packageName, order: index),
    ]);
    _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    _recomputeGridApps();
    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> removeFromCategory(App app, Category category) async {
    await _database.deleteAppCategory(category.id, app.packageName);
    _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    _recomputeGridApps();
    notifyListeners();
  }

  Future<void> saveOrderInCategory(Category category) async {
    final applications = _categoriesWithApps.firstWhere((element) => element.category.id == category.id).applications;
    final orderedAppCategories = <AppsCategoriesCompanion>[];
    for (int i = 0; i < applications.length; ++i) {
      orderedAppCategories.add(
        AppsCategoriesCompanion(
          categoryId: Value(category.id),
          appPackageName: Value(applications[i].packageName),
          order: Value(i),
        ),
      );
    }
    await _database.replaceAppsCategories(orderedAppCategories);
    _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    notifyListeners();
  }

  void reorderApplication(Category category, int oldIndex, int newIndex) {
    final applications = _categoriesWithApps.firstWhere((element) => element.category.id == category.id).applications;
    final application = applications.removeAt(oldIndex);
    applications.insert(newIndex, application);
    notifyListeners();
  }

  Future<void> hideApplication(App application) async {
    await _database.updateApp(application.packageName, AppsCompanion(hidden: Value(true)));
    _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    _applications = await _database.listApplications();
    _recomputeGridApps();
    notifyListeners();
  }

  Future<void> unHideApplication(App application) async {
    await _database.updateApp(application.packageName, AppsCompanion(hidden: Value(false)));
    _categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    _applications = await _database.listApplications();
    _recomputeGridApps();
    notifyListeners();
  }
}
