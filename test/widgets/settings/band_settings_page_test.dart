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

import 'package:tvlauncher/band/band_controller.dart';
import 'package:tvlauncher/widgets/settings/band_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("left and right change the lengths in 20 ms steps, select cycles the variants", (tester) async {
    final band = BandController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BandScope(controller: band, child: BandSettingsPage()),
        ),
      ),
    );
    final launchLength = band.launchDuration;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text("Launch length   ‹ ${launchLength.inMilliseconds} ms ›"), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(band.launchDuration, launchLength + Duration(milliseconds: 20));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(band.launchMode, LaunchMode.values[(BandController.releaseLaunchMode.index + 1) % LaunchMode.values.length]);
    band.dispose();
  });

  test("lengths stay between 100 ms and 3 s", () {
    final band = BandController()
      ..launchDuration = Duration.zero
      ..returnDuration = Duration(seconds: 10);
    expect(band.launchDuration, Duration(milliseconds: 100));
    expect(band.returnDuration, Duration(milliseconds: 3000));
    band.dispose();
  });
}
