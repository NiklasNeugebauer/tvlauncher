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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Owns the home screen's scroll position and the two focus regions (hero row, apps grid).
///
/// Focus drives scrolling: a focused hero tile keeps the page at the top, a focused grid tile keeps the hero fully
/// scrolled out of view. The region nodes never take focus themselves and are skipped by traversal, so the
/// row-by-row policy sees only the tiles.
class HomeFocusController {
  static const _scrollDuration = Duration(milliseconds: 150);

  final ScrollController scroll = ScrollController();
  final FocusNode heroNode = FocusNode(debugLabel: "hero", canRequestFocus: false, skipTraversal: true);
  final FocusNode gridNode = FocusNode(debugLabel: "grid", canRequestFocus: false, skipTraversal: true);

  /// Height of the hero zone, set by the home screen's layout on every build.
  double heroZoneHeight = 0;

  bool get gridHasFocus => gridNode.hasFocus;

  bool get hasFocusedTile => heroNode.hasFocus || gridNode.hasFocus;

  /// Scrolls to the top and focuses the first hero tile, or the first grid tile when the hero is empty.
  void focusFirstTile({bool animate = false}) {
    if (scroll.hasClients) {
      animate ? scroll.animateTo(0, duration: _scrollDuration, curve: Curves.easeInOut) : scroll.jumpTo(0);
    }
    (_firstTraversable(heroNode) ?? _firstTraversable(gridNode))?.requestFocus();
  }

  /// Up from the grid's first row goes to the hero, not to whatever happens to be above it on screen (the
  /// hero is scrolled out of view then, so plain geometry would pick the gear).
  KeyEventResult handleGridKey(FocusNode node, RawKeyEvent event) {
    if (event is! RawKeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    final current = FocusManager.instance.primaryFocus;
    if (current == null || !gridNode.traversalDescendants.contains(current)) {
      return KeyEventResult.ignored;
    }
    final currentY = current.rect.center.dy.round();
    final hasRowAbove = gridNode.traversalDescendants.any((tile) => tile.rect.center.dy.round() < currentY);
    if (hasRowAbove) {
      return KeyEventResult.ignored;
    }
    final heroTiles = heroNode.traversalDescendants.toList();
    if (heroTiles.isEmpty) {
      return KeyEventResult.ignored;
    }
    final currentX = current.rect.center.dx;
    heroTiles.sort((a, b) => (a.rect.center.dx - currentX).abs().compareTo((b.rect.center.dx - currentX).abs()));
    heroTiles.first.requestFocus();
    return KeyEventResult.handled;
  }

  void revealTile(BuildContext tileContext, {required bool inHero}) {
    if (!scroll.hasClients) {
      return;
    }
    if (inHero) {
      _animateTo(0);
      return;
    }
    final renderObject = tileContext.findRenderObject();
    final viewport = renderObject == null ? null : RenderAbstractViewport.of(renderObject);
    if (renderObject == null || viewport == null) {
      return;
    }
    final maxExtent = scroll.position.maxScrollExtent;
    final target = viewport.getOffsetToReveal(renderObject, 0.5).offset;
    _animateTo(target.clamp(min(heroZoneHeight, maxExtent), maxExtent));
  }

  void dispose() {
    scroll.dispose();
    heroNode.dispose();
    gridNode.dispose();
  }

  void _animateTo(double offset) {
    if ((scroll.offset - offset).abs() < 0.5) {
      return;
    }
    scroll.animateTo(offset, duration: _scrollDuration, curve: Curves.easeInOut);
  }

  FocusNode? _firstTraversable(FocusNode region) {
    final descendants = region.traversalDescendants;
    return descendants.isEmpty ? null : descendants.first;
  }
}

/// Reports focus gained by the wrapped tile to the [HomeFocusController] so the page scrolls to it.
class RevealOnFocus extends StatefulWidget {
  final bool inHero;
  final Widget child;

  RevealOnFocus({Key? key, required this.inHero, required this.child}) : super(key: key);

  @override
  _RevealOnFocusState createState() => _RevealOnFocusState();
}

class _RevealOnFocusState extends State<RevealOnFocus> {
  HomeFocusController? _controller;
  // Focus can bounce back to a tile while its subtree is being torn down; a deactivated element has no usable
  // render object, so track activity explicitly instead of relying on `mounted`.
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _active = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = context.read<HomeFocusController>();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (focused && _active) {
            _controller?.revealTile(context, inHero: widget.inHero);
          }
        },
        child: widget.child,
      );
}
