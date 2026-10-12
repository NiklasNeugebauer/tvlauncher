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

import 'package:tvlauncher/motion/spring.dart';
import 'package:tvlauncher/motion/tuning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("SpringState", () {
    // Steps a spring from 0 to 100 at 60 fps; returns the peak and the time it took to settle.
    (double, double) run(SpringSpec spec) {
      final state = SpringState(0)..target = 100;
      var peak = 0.0;
      var t = 0.0;
      while (!state.step(1 / 60, spec)) {
        peak = state.value > peak ? state.value : peak;
        t += 1 / 60;
      }
      return (peak, t);
    }

    test("overshoots by about the requested fraction and settles in about one response", () {
      final (peak, settle) = run(SpringSpec(response: Duration(milliseconds: 300), overshoot: 0.06));

      expect(peak, closeTo(106, 1));
      expect(settle, inInclusiveRange(0.25, 0.45));
    });

    test("does not overshoot without overshoot", () {
      final (peak, _) = run(SpringSpec(response: Duration(milliseconds: 300)));

      expect(peak, lessThanOrEqualTo(100));
    });

    test("a new target keeps the velocity", () {
      final spec = SpringSpec(response: Duration(milliseconds: 300), overshoot: 0.06);
      final state = SpringState(0)..target = 100;
      state.step(0.1, spec);
      final velocity = state.velocity;

      state.target = 200;
      state.step(1 / 60, spec);

      expect(velocity, greaterThan(0));
      expect(state.velocity, greaterThan(velocity * 0.8));
    });
  });

  testWidgets("SpringBuilder animates to a new value and jumps without a spec", (tester) async {
    double? shown;
    Widget build(double value, SpringSpec? spec) => SpringBuilder(
      value: value,
      spec: spec,
      builder: (_, v, _) {
        shown = v;
        return SizedBox();
      },
    );
    final spec = SpringSpec(response: Duration(milliseconds: 300), overshoot: 0.06);
    await tester.pumpWidget(build(0, spec));

    await tester.pumpWidget(build(1, spec));
    await tester.pump(Duration(milliseconds: 100));
    expect(shown, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(shown, closeTo(1, 1e-3));

    await tester.pumpWidget(build(0, null));
    expect(shown, 0);
  });

  test("tuning values snap to their step and range", () {
    final tuning = Tuning();

    tuning[Tune.focusResponse] = 333;
    expect(tuning[Tune.focusResponse], 330);
    tuning[Tune.focusResponse] = 5000;
    expect(tuning[Tune.focusResponse], Tune.focusResponse.max);
    tuning.stepBy(Tune.focusOvershoot, -100);
    expect(tuning[Tune.focusOvershoot], 0);
  });
}
