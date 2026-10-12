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

import 'package:tvlauncher/motion/edge_nudge.dart';
import 'package:tvlauncher/providers/apps_service.dart';
import 'package:tvlauncher/sound/ui_sounds.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Moves focus with the D-pad, with a blip; when there is nowhere to go, the focused widget's [EdgeNudge] bumps
/// instead, with a thud.
class SoundFeedbackDirectionalFocusAction extends DirectionalFocusAction {
  final BuildContext context;

  SoundFeedbackDirectionalFocusAction(this.context);

  @override
  void invoke(DirectionalFocusIntent intent) {
    final focused = primaryFocus;
    if (focused == null) {
      return;
    }
    final sounds = UiSounds.maybeOf(context);
    if (focused.focusInDirection(intent.direction)) {
      sounds?.focusMoved();
      return;
    }
    sounds?.edge();
    final nudge = focused.context == null ? null : EdgeNudge.of(focused.context!);
    nudge?.nudge(switch (intent.direction) {
      TraversalDirection.left => AxisDirection.left,
      TraversalDirection.right => AxisDirection.right,
      TraversalDirection.up => AxisDirection.up,
      TraversalDirection.down => AxisDirection.down,
    });
  }
}

class BackAction extends Action<BackIntent> {
  final BuildContext context;
  final bool systemNavigator;

  BackAction(this.context, {this.systemNavigator = false});

  @override
  Future<void> invoke(BackIntent intent) async {
    if (systemNavigator && await shouldPopScope(context)) {
      SystemNavigator.pop();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}

class BackIntent extends Intent {
  const BackIntent();
}

Future<bool> shouldPopScope(BuildContext context) async => !await context.read<AppsService>().isDefaultLauncher();
