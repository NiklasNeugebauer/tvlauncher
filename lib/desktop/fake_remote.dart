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

import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Presses the TV remote's keys inside the app, delivered as the Android engine delivers them: a [ui.KeyData] for
/// the [HardwareKeyboard] followed by the raw `flutter/keyevent` message it is paired with. Back is not a key on
/// the TV but a route pop, see [back].
class FakeRemote {
  static const right = RemoteKey(22, 106, LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight);
  static const left = RemoteKey(21, 105, LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft);
  static const down = RemoteKey(20, 108, LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown);
  static const up = RemoteKey(19, 103, LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp);
  static const select = RemoteKey(23, 353, LogicalKeyboardKey.select, PhysicalKeyboardKey.select);

  static ui.KeyDataCallback? _onKeyData;

  /// From now on only these presses reach the app; the desktop keyboard and mouse are ignored. Whatever is typed
  /// into the bench window, or a pointer resting on it (hover focuses a tile), would otherwise land in the
  /// measurement.
  static void exclusive() {
    _onKeyData = ui.PlatformDispatcher.instance.onKeyData;
    ui.PlatformDispatcher.instance.onKeyData = (_) => false;
    SystemChannels.keyEvent.setMessageHandler((_) async => {"handled": false});
    ui.PlatformDispatcher.instance.onPointerDataPacket = (_) {};
  }

  static Future<void> press(RemoteKey key, {Duration hold = const Duration(milliseconds: 60)}) async {
    _send(key, down: true);
    await Future.delayed(hold);
    _send(key, down: false);
  }

  static void back() => ServicesBinding.instance.channelBuffers.push(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(const MethodCall("popRoute")),
    (_) {},
  );

  static void _send(RemoteKey key, {required bool down}) {
    (_onKeyData ?? ui.PlatformDispatcher.instance.onKeyData)!(
      ui.KeyData(
        type: down ? ui.KeyEventType.down : ui.KeyEventType.up,
        physical: key.physical.usbHidUsage,
        logical: key.logical.keyId,
        timeStamp: Duration(microseconds: DateTime.now().microsecondsSinceEpoch),
        character: null,
        synthesized: false,
      ),
    );
    final raw = {
      "type": down ? "keydown" : "keyup",
      "keymap": "android",
      "keyCode": key.keyCode,
      "scanCode": key.scanCode,
      "plainCodePoint": 0,
      "codePoint": 0,
      "metaState": 0,
      "flags": 0,
      "source": 0x201, // SOURCE_DPAD
      "deviceId": 1,
      "repeatCount": 0,
    };
    // ignore: deprecated_member_use
    ServicesBinding.instance.keyEventManager.handleRawKeyMessage(raw);
  }
}

/// An Android key code and scan code with the Flutter keys the engine maps them to.
class RemoteKey {
  final int keyCode;
  final int scanCode;
  final LogicalKeyboardKey logical;
  final PhysicalKeyboardKey physical;

  const RemoteKey(this.keyCode, this.scanCode, this.logical, this.physical);
}
