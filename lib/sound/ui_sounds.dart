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

import 'package:tvlauncher/band/band_controller.dart';
import 'package:tvlauncher/launcher_channel.dart';
import 'package:tvlauncher/motion/tuning.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// The UI sounds and their rules, from the polish plan: a sine blip on every focus move at the base pitch with a
/// little random spread (the plan's pitch rising per tile was dropped), a low thud at an edge (once per press), a
/// click on select (on key down), a quieter two-note blip for panels, and while a direction key is held one soft
/// tick per four moves instead of a blip per move.
class UiSounds {
  /// Pitch the focus blip is rendered at (tool/sounds.py); playing it faster or slower moves it to the tuned
  /// [Tune.focusSoundPitch], and the spread varies that a little.
  static const double focusHz = 560;
  static const double spreadHz = 12;
  static const int ticksEvery = 4;
  static const double panelLevel = 0.6;

  final LauncherChannel _channel;
  final BandController _band;
  final Random _random;
  int _heldMoves = 0;

  UiSounds(this._channel, this._band, {Random? random}) : _random = random ?? Random();

  /// The sounds, when the app provides them (widgets pumped on their own play nothing).
  static UiSounds? maybeOf(BuildContext context) {
    try {
      return context.read<UiSounds>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  void focusMoved() {
    if (_band.holding) {
      if (++_heldMoves % ticksEvery == 0) {
        _play("tick");
      }
      return;
    }
    _heldMoves = 0;
    final hz = _band.tuning[Tune.focusSoundPitch] + (_random.nextDouble() * 2 - 1) * spreadHz;
    _play("focus", rate: hz / focusHz, level: _band.tuning[Tune.focusSoundLevel]);
  }

  /// A press found nothing to focus.
  void edge() {
    if (!_band.holding) {
      _play("thud");
    }
  }

  void select() => _play("select");

  /// The remote's Home button, subtle.
  void home() => _play("home");

  void panel({required bool open}) => _play(open ? "panelOpen" : "panelClose", level: panelLevel);

  void _play(String name, {double rate = 1, double level = 1}) {
    if (!_band.sound) {
      return;
    }
    final volume = _band.tuning[Tune.soundVolume] * level;
    if (volume > 0) {
      _channel.playSound(name, rate: rate, volume: volume);
    }
  }
}
