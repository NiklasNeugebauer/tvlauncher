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

import 'dart:math';

import 'package:flauncher/band/band_controller.dart';
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/sound/ui_sounds.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockFLauncherChannel channel;
  late BandController band;
  late UiSounds sounds;

  setUp(() {
    channel = MockFLauncherChannel();
    when(channel.playSound(any, rate: anyNamed("rate"), volume: anyNamed("volume"))).thenAnswer((_) async {});
    band = BandController();
    sounds = UiSounds(channel, band, random: Random(1));
  });

  tearDown(() => band.dispose());

  List<(String, double)> played() {
    final captured = verify(channel.playSound(captureAny, rate: captureAnyNamed("rate"), volume: anyNamed("volume")))
        .captured;
    return [for (var k = 0; k < captured.length; k += 2) (captured[k] as String, captured[k + 1] as double)];
  }

  testWidgets("focus blips vary around one pitch by the spread only", (tester) async {
    for (var i = 0; i < 20; i++) {
      sounds.focusMoved();
    }

    final rates = played().map((p) => p.$2 * UiSounds.focusHz).toList();
    expect(rates, everyElement(closeTo(Tune.focusSoundPitch.defaultValue, UiSounds.spreadHz)));
    expect(rates.toSet().length, greaterThan(1));
  });

  test("focus blips follow the tuned pitch and level", () {
    band.tuning[Tune.focusSoundPitch] = 800;
    band.tuning[Tune.focusSoundLevel] = 0.5;
    sounds.focusMoved();

    final captured = verify(
      channel.playSound("focus", rate: captureAnyNamed("rate"), volume: captureAnyNamed("volume")),
    ).captured;
    expect((captured[0] as double) * UiSounds.focusHz, closeTo(800, UiSounds.spreadHz));
    expect(captured[1], closeTo(0.5 * Tune.soundVolume.defaultValue, 1e-9));
  });

  testWidgets("while a key is held, every fourth move ticks and edges stay quiet", (tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 8; i++) {
      sounds.focusMoved();
    }
    sounds.edge();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

    expect(played().map((p) => p.$1), ["tick", "tick"]);
  });

  test("nothing plays with sounds off or at zero volume", () {
    band.sound = false;
    sounds.select();
    band.sound = true;
    band.tuning[Tune.soundVolume] = 0;
    sounds.select();

    verifyNever(channel.playSound(any, rate: anyNamed("rate"), volume: anyNamed("volume")));
  });

  test("panels play quieter than focus", () {
    sounds.panel(open: true);
    sounds.select();

    final volumes = verify(channel.playSound(any, rate: anyNamed("rate"), volume: captureAnyNamed("volume"))).captured
        .cast<double>();
    expect(volumes.first, lessThan(volumes.last));
  });
}
