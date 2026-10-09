/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const longPressableKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

const _longPress = Duration(milliseconds: 500);
const _veryLongPress = Duration(milliseconds: 1500);

/// Turns a held select key into three tiers: a press fires on release, a long press after half a second,
/// a very long press after one and a half seconds. The key down is consumed so Flutter's shortcut layer does
/// not activate the focused widget before the hold can be measured.
class FocusKeyboardListener extends StatefulWidget {
  final WidgetBuilder builder;
  final KeyEventResult Function(LogicalKeyboardKey)? onPressed;
  final KeyEventResult Function(LogicalKeyboardKey)? onLongPress;
  final KeyEventResult Function(LogicalKeyboardKey)? onVeryLongPress;

  /// True when a select key goes down, false when it comes up: the moment to show the press, before the
  /// listener knows whether it becomes a press or a hold.
  final ValueChanged<bool>? onPressChanged;

  const FocusKeyboardListener({
    super.key,
    required this.builder,
    this.onPressed,
    this.onLongPress,
    this.onVeryLongPress,
    this.onPressChanged,
  });

  @override
  State<FocusKeyboardListener> createState() => _FocusKeyboardListenerState();
}

class _FocusKeyboardListenerState extends State<FocusKeyboardListener> {
  DateTime? _keyDownAt;
  bool _repeated = false;
  bool _longPressFired = false;
  bool _veryLongPressFired = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) => _handleKey(event),
    child: Builder(builder: widget.builder),
  );

  KeyEventResult _handleKey(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      return _keyUpEvent(key);
    }
    if (!longPressableKeys.contains(key)) {
      return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
    }
    final downAt = _keyDownAt;
    // The repeats of a key pressed before this widget had focus (the select that confirmed a panel entry): not a
    // hold that started here.
    if (downAt == null && event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (downAt == null) {
      _keyDownAt = clock.now();
      _repeated = false;
      _longPressFired = false;
      _veryLongPressFired = false;
      widget.onPressChanged?.call(true);
      return KeyEventResult.handled;
    }
    final held = clock.now().difference(downAt);
    // Android synthesizes the first repeat only after its own long-press timeout, so it counts as a long press
    // even when the clock has not reached ours yet (this is what `input keyevent --longpress` sends).
    final firstRepeat = event is KeyRepeatEvent && !_repeated;
    _repeated = _repeated || event is KeyRepeatEvent;
    if (!_veryLongPressFired && held >= _veryLongPress) {
      _veryLongPressFired = true;
      _longPressFired = true;
      return widget.onVeryLongPress?.call(key) ?? KeyEventResult.handled;
    }
    if (!_longPressFired && (held >= _longPress || firstRepeat)) {
      _longPressFired = true;
      return widget.onLongPress?.call(key) ?? KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _keyUpEvent(LogicalKeyboardKey key) {
    if (_keyDownAt == null) {
      return KeyEventResult.ignored;
    }
    final fired = _longPressFired;
    _keyDownAt = null;
    widget.onPressChanged?.call(false);
    _longPressFired = false;
    _veryLongPressFired = false;
    if (fired) {
      return KeyEventResult.handled;
    }
    return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
  }
}
