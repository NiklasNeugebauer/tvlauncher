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

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/theme.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const _validationKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

/// One app tile. Hero tiles can be moved left/right; grid tiles are alphabetical and never move.
class AppCard extends StatefulWidget {
  final App application;
  final bool inHero;
  final bool autofocus;
  final void Function(AxisDirection)? onMove;
  final VoidCallback? onMoveEnd;

  AppCard({
    super.key,
    required this.application,
    required this.inHero,
    required this.autofocus,
    this.onMove,
    this.onMoveEnd,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _moving = false;
  MemoryImage? _imageProvider;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  // Losing focus while moving (Home, Back, a hovering pointer) drops the tile where it is, so the order in memory
  // never silently diverges from the one persisted.
  void _onFocusChange() {
    if (!_focusNode.hasFocus && _moving) {
      _endMove();
    }
  }

  ImageProvider _cachedMemoryImage(Uint8List bytes) {
    if (!listEquals(bytes, _imageProvider?.bytes)) {
      _imageProvider = MemoryImage(bytes);
    }
    return _imageProvider!;
  }

  @override
  Widget build(BuildContext context) => FocusKeyboardListener(
    onPressed: (key) => _onPressed(context, key),
    onLongPress: (key) => _onLongPress(context, key),
    onVeryLongPress: (key) => _onVeryLongPress(context),
    builder: (context) => AspectRatio(
      aspectRatio: 16 / 9,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        transformAlignment: Alignment.center,
        transform: _scaleTransform(context),
        child: Material(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Shapes.tileRadius),
          clipBehavior: Clip.antiAlias,
          elevation: Focus.of(context).hasFocus ? 16 : 0,
          shadowColor: Palette.shadow,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InkWell(
                autofocus: widget.autofocus,
                focusNode: _focusNode,
                focusColor: Colors.transparent,
                onTap: () => _onTap(context),
                onHover: _onHover,
                onLongPress: () => _onLongPress(context, null),
                child: widget.application.banner != null
                    ? Ink.image(image: _cachedMemoryImage(widget.application.banner!), fit: BoxFit.cover)
                    : _iconWithName(context),
              ),
              if (_moving) ..._arrows(),
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  opacity: Focus.of(context).hasFocus ? 0 : 0.10,
                  child: Container(color: Colors.black),
                ),
              ),
              IgnorePointer(
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    border: Focus.of(context).hasFocus
                        ? Border.all(color: Palette.brass, width: Shapes.focusRing)
                        : null,
                    borderRadius: BorderRadius.circular(Shapes.tileRadius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _iconWithName(BuildContext context) => Padding(
    padding: EdgeInsets.all(8),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: widget.application.icon != null
              ? Ink.image(image: _cachedMemoryImage(widget.application.icon!), height: double.infinity)
              : Icon(Icons.android, size: 32),
        ),
        Flexible(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text(
              widget.application.name,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ),
      ],
    ),
  );

  Matrix4 _scaleTransform(BuildContext context) {
    final scale = !_moving && Focus.of(context).hasFocus ? 1.1 : 1.0;
    return Matrix4.diagonal3Values(scale, scale, 1.0);
  }

  List<Widget> _arrows() => [
    _arrow(Alignment.centerLeft, Icons.keyboard_arrow_left),
    _arrow(Alignment.centerRight, Icons.keyboard_arrow_right),
  ];

  Widget _arrow(Alignment alignment, IconData icon) => Align(
    alignment: alignment,
    child: Padding(
      padding: EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: Palette.brass),
        child: Icon(icon, size: 16, color: Palette.bgBottom),
      ),
    ),
  );

  KeyEventResult _onPressed(BuildContext context, LogicalKeyboardKey? key) {
    if (_moving) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.onMove?.call(AxisDirection.left);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        widget.onMove?.call(AxisDirection.right);
      } else if (_validationKeys.contains(key)) {
        _endMove();
      }
      return KeyEventResult.handled;
    } else if (_validationKeys.contains(key)) {
      context.read<AppsService>().launchApp(widget.application);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Pointer / air-mouse support. Hovering a card selects it, mirroring the D-pad focus model that every visual
  // state in build() reads from Focus.of(context).hasFocus. The !_moving guard keeps a stray hover from stealing
  // focus while a card is being repositioned with the D-pad.
  void _onHover(bool hovering) {
    if (hovering && !_moving && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  // A pointer tap is the equivalent of pressing the D-pad select key: launch the app, or drop it in place when
  // reordering. (The keyboard path passes a LogicalKeyboardKey to _onPressed; a tap has no key.)
  void _onTap(BuildContext context) {
    if (_moving) {
      _endMove();
    } else {
      context.read<AppsService>().launchApp(widget.application);
    }
  }

  void _endMove() {
    setState(() => _moving = false);
    widget.onMoveEnd?.call();
  }

  // Held select on a hero tile starts moving it right away; the panel comes after a longer hold (or a pointer
  // long press, which has no move mode). Grid tiles cannot move, so the hold opens the panel directly.
  KeyEventResult _onLongPress(BuildContext context, LogicalKeyboardKey? key) {
    if (_moving) {
      return KeyEventResult.ignored;
    }
    if (key != null && widget.inHero && widget.onMove != null) {
      setState(() => _moving = true);
    } else {
      _showPanel(context);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onVeryLongPress(BuildContext context) {
    if (_moving) {
      // Nothing was moved yet, so there is no order to save.
      setState(() => _moving = false);
    }
    _showPanel(context);
    return KeyEventResult.handled;
  }

  Future<void> _showPanel(BuildContext context) async {
    final result = await showDialog<ApplicationInfoPanelResult>(
      context: context,
      builder: (context) => ApplicationInfoPanel(application: widget.application, inHero: widget.inHero),
    );
    if (result == ApplicationInfoPanelResult.reorderApp && widget.onMove != null && mounted) {
      setState(() => _moving = true);
    }
  }
}
