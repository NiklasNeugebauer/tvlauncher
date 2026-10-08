import 'package:flauncher/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Element? findAppCardByPackageName(WidgetTester tester, String packageName) {
  for (var val in tester.elementList(find.byType(AppCard))) {
    if ((val.widget as AppCard).application.packageName == packageName) {
      return val;
    }
  }
  return null;
}

Element findSettingsIcon(WidgetTester tester) => tester.element(find.byKey(Key("settings")));
