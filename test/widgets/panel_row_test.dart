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

import 'package:tvlauncher/theme.dart';
import 'package:tvlauncher/widgets/panel_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("Focus raises the row and turns its icon brass", (tester) async {
    await _pump(tester);

    expect(_rowColor(tester, "first"), Palette.surfaceRaised);
    expect(_iconColor(tester, Icons.wifi), Palette.brass);
    expect(_rowColor(tester, "second"), Colors.transparent);
    expect(_iconColor(tester, Icons.tv), Palette.cream);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_rowColor(tester, "first"), Colors.transparent);
    expect(_rowColor(tester, "second"), Palette.surfaceRaised);
    expect(_iconColor(tester, Icons.tv), Palette.brass);
  });

  testWidgets("A destructive row keeps its colour when focused and select presses it", (tester) async {
    var pressed = 0;
    await _pump(tester, onDanger: () => pressed++);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(_rowColor(tester, "danger"), Palette.surfaceRaised);
    expect(_iconColor(tester, Icons.delete_outlined), Palette.danger);
    expect(tester.widget<Text>(find.text("Uninstall")).style!.color, Palette.danger);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(pressed, 1);
  });

  testWidgets("Hovering a row focuses it", (tester) async {
    await _pump(tester);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byKey(Key("second"))));
    await tester.pumpAndSettle();

    expect(_rowColor(tester, "second"), Palette.surfaceRaised);
    expect(Focus.of(tester.element(find.text("Display"))).hasFocus, isTrue);
  });
}

Future<void> _pump(WidgetTester tester, {VoidCallback? onDanger}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Column(
          children: [
            PanelRow(key: Key("first"), icon: Icons.wifi, label: "Wi-Fi", onPressed: () {}, autofocus: true),
            PanelRow(key: Key("second"), icon: Icons.tv, label: "Display", onPressed: () {}),
            PanelRow(
              key: Key("danger"),
              icon: Icons.delete_outlined,
              label: "Uninstall",
              onPressed: onDanger ?? () {},
              destructive: true,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _rowColor(WidgetTester tester, String key) =>
    tester.widget<Material>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Material))).color;

Color? _iconColor(WidgetTester tester, IconData icon) => tester.widget<Icon>(find.byIcon(icon)).color;
