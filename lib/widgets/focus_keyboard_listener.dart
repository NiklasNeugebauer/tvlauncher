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

/// KeyEvent.FLAG_LONG_PRESS: Android marks the first repeat after its own long-press timeout.
const _flagLongPress = 0x80;
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

  FocusKeyboardListener({
    Key? key,
    required this.builder,
    this.onPressed,
    this.onLongPress,
    this.onVeryLongPress,
  }) : super(key: key);

  @override
  _FocusKeyboardListenerState createState() => _FocusKeyboardListenerState();
}

class _FocusKeyboardListenerState extends State<FocusKeyboardListener> {
  DateTime? _keyDownAt;
  bool _longPressFired = false;
  bool _veryLongPressFired = false;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        onKey: (_, rawKeyEvent) => _handleKey(context, rawKeyEvent),
        child: Builder(builder: widget.builder),
      );

  KeyEventResult _handleKey(BuildContext context, RawKeyEvent rawKeyEvent) {
    switch (rawKeyEvent.runtimeType) {
      case RawKeyDownEvent:
        return _keyDownEvent(context, rawKeyEvent.logicalKey, rawKeyEvent.data);
      case RawKeyUpEvent:
        return _keyUpEvent(context, rawKeyEvent.logicalKey);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _keyDownEvent(BuildContext context, LogicalKeyboardKey key, RawKeyEventData data) {
    if (!longPressableKeys.contains(key)) {
      return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
    }
    final downAt = _keyDownAt;
    if (downAt == null) {
      // First down of a hold. Test simulators report every repeat with repeatCount 0, so "still held" is tracked
      // here rather than read from the event.
      _keyDownAt = clock.now();
      _longPressFired = false;
      _veryLongPressFired = false;
      return KeyEventResult.handled;
    }
    final held = clock.now().difference(downAt);
    final flaggedLongPress = data is RawKeyEventDataAndroid && data.flags & _flagLongPress != 0;
    if (!_veryLongPressFired && held >= _veryLongPress) {
      _veryLongPressFired = true;
      _longPressFired = true;
      return widget.onVeryLongPress?.call(key) ?? KeyEventResult.handled;
    }
    if (!_longPressFired && (held >= _longPress || flaggedLongPress)) {
      _longPressFired = true;
      return widget.onLongPress?.call(key) ?? KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _keyUpEvent(BuildContext context, LogicalKeyboardKey key) {
    if (_keyDownAt == null) {
      return KeyEventResult.ignored;
    }
    final fired = _longPressFired;
    _keyDownAt = null;
    _longPressFired = false;
    _veryLongPressFired = false;
    if (fired) {
      return KeyEventResult.handled;
    }
    return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
  }
}
