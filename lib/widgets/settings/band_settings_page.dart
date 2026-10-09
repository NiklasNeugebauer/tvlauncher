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
import 'package:flauncher/motion/tuning.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flauncher/widgets/panel_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Size and motion of the band: the nudge mode, the launch and return choreography with their lengths, how focus
/// moves and its tuning, idle and the frame-time readout. Everything here is also in the config file (see
/// [BandController]).
class BandSettingsPage extends StatelessWidget {
  static const String routeName = "band_settings";

  @override
  Widget build(BuildContext context) {
    final band = BandScope.maybeOf(context, listen: true);
    if (band == null) {
      return SizedBox();
    }
    T next<T extends Enum>(List<T> values, T current) => values[(current.index + 1) % values.length];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader("Band & motion"),
          Divider(),
          _visible(
            PanelRow(
              icon: Icons.straighten,
              label: "Tune size and position",
              autofocus: true,
              onPressed: () async {
                Navigator.of(context, rootNavigator: true).pop();
                // Once the panel is gone and focus is back on the home screen, so leaving the mode returns it there.
                await Future.delayed(Motion.layout);
                band.startNudging();
              },
            ),
          ),
          Divider(),
          _visible(
            PanelRow(
              icon: Icons.open_in_full,
              label: "Launch: ${band.launchMode.label}",
              onPressed: () => band.launchMode = next(LaunchMode.values, band.launchMode),
            ),
          ),
          _visible(
            StepRow(
              key: Key("launch-duration"),
              label: "Launch length",
              value: "${band.launchDuration.inMilliseconds} ms",
              onStep: (steps) => band.launchDuration += BandController.durationStep * steps,
            ),
          ),
          _visible(
            PanelRow(
              icon: Icons.close_fullscreen,
              label: "Return: ${band.returnMode.label}",
              onPressed: () => band.returnMode = next(ReturnMode.values, band.returnMode),
            ),
          ),
          _visible(
            StepRow(
              key: Key("return-duration"),
              label: "Return length",
              value: "${band.returnDuration.inMilliseconds} ms",
              onStep: (steps) => band.returnDuration += BandController.durationStep * steps,
            ),
          ),
          Divider(),
          _visible(
            PanelRow(
              icon: Icons.center_focus_strong,
              label: "Focus: ${band.focusMotion.label}",
              onPressed: () => band.focusMotion = next(FocusMotion.values, band.focusMotion),
            ),
          ),
          for (final param in Tune.all)
            _visible(
              StepRow(
                key: Key("tune-${param.key}"),
                label: param.label,
                value: param.format(band.tuning[param]),
                onStep: (steps) => band.tuning.stepBy(param, steps),
              ),
            ),
          _visible(
            PanelRow(
              icon: Icons.bedtime_outlined,
              label: "Idle after ${band.idleAfter.inMinutes} min: ${band.idleMode.label}",
              onPressed: () => band.idleMode = next(IdleMode.values, band.idleMode),
            ),
          ),
          _visible(
            PanelRow(
              icon: Icons.speed,
              label: "Frame times: ${band.frameTimes ? "shown" : "hidden"}",
              onPressed: () => band.frameTimes = !band.frameTimes,
            ),
          ),
        ],
      ),
    );
  }

  // The band is short, so the page scrolls; keep the focused row in view.
  Widget _visible(Widget row) => EnsureVisible(alignment: 0.5, child: row);
}

/// A number that left and right step down and up. [onStep] gets the direction, not a new value, so presses faster
/// than a rebuild still add up.
class StepRow extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<int> onStep;

  const StepRow({super.key, required this.label, required this.value, required this.onStep});

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is KeyUpEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        onStep(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        onStep(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: PanelRow(icon: Icons.tune, label: "$label   ‹ $value ›", onPressed: () {}),
  );
}
