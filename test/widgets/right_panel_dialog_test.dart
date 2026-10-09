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

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/widgets/focus_glide.dart';
import 'package:flauncher/widgets/panel_row.dart';
import 'package:flauncher/widgets/right_panel_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(PanelStaggerState.forgetFocus);

  testWidgets("the band follows the panel open and closed", (tester) async {
    final band = BandController();
    await _pumpOpener(tester, band);

    await tester.tap(find.text("open"));
    await tester.pump();
    expect(band.panelOpen.value, isTrue);
    await tester.pumpAndSettle();
    expect(band.panel.value, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(band.panelOpen.value, isFalse);
    expect(band.panel.value, 0);
    band.dispose();
  });

  testWidgets("left, toward the launcher, closes the panel", (tester) async {
    final band = BandController();
    await _pumpOpener(tester, band);
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.byType(RightPanelDialog), findsNothing);
    band.dispose();
  });

  testWidgets("a remembering panel reopens on the row used last", (tester) async {
    final band = BandController();
    await _pumpOpener(tester, band);
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_rowHasFocus(tester, "Row 2"), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();

    expect(_rowHasFocus(tester, "Row 2"), isTrue);
    await _close(tester);
    band.dispose();
  });

  testWidgets("one highlight slides behind the focused row", (tester) async {
    final band = BandController();
    await _pumpOpener(tester, band);
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    final glide = tester.state<FocusGlideState>(find.byType(FocusGlide));
    Rect highlight() => glide.ringRect!.shift(tester.getTopLeft(find.byType(FocusGlide)));
    Rect row(String label) =>
        tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(SizedBox)).first);

    expect(highlight(), row("Row 0"));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(Duration(milliseconds: 50));
    expect(highlight().top, inExclusiveRange(row("Row 0").top, row("Row 1").top));
    await tester.pumpAndSettle();
    expect(highlight(), row("Row 1"));
    await _close(tester);
    band.dispose();
  });

  testWidgets("rows rise in one after another", (tester) async {
    final band = BandController();
    await _pumpOpener(tester, band);
    await tester.tap(find.text("open"));
    await tester.pump();
    await tester.pump(Duration(milliseconds: 60));

    double opacityOf(String label) =>
        tester.widget<Opacity>(find.ancestor(of: find.text(label), matching: find.byType(Opacity)).first).opacity;
    expect(opacityOf("Row 0"), greaterThan(opacityOf("Row 2")));
    await tester.pumpAndSettle();
    expect(opacityOf("Row 2"), 1);
    await _close(tester);
    band.dispose();
  });
}

Future<void> _close(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

bool _rowHasFocus(WidgetTester tester, String label) => Focus.of(tester.element(find.text(label))).hasFocus;

Future<void> _pumpOpener(WidgetTester tester, BandController band) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BandScope(
        controller: band,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPanel(
              context,
              (_) => RightPanelDialog(
                rememberFocus: true,
                child: Column(
                  children: [
                    for (var i = 0; i < 4; i++)
                      PanelRow(icon: Icons.circle, label: "Row $i", autofocus: i == 0, onPressed: () {}),
                  ],
                ),
              ),
            ),
            child: Text("open"),
          ),
        ),
      ),
    ),
  );
}
