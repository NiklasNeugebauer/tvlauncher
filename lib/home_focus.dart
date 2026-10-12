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

import 'package:tvlauncher/custom_traversal_policy.dart';
import 'package:tvlauncher/database.dart';
import 'package:tvlauncher/theme.dart';
import 'package:tvlauncher/widgets/home_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Owns the home screen's scroll position and the two focus regions (hero row, apps grid).
///
/// Focus drives scrolling: a focused hero tile keeps the page at the top, a focused grid tile keeps the hero fully
/// scrolled out of view and shows whole rows only (see [HomeLayout.windowFor]). The region nodes never take focus
/// themselves and are skipped by traversal, so the row-by-row policy sees only the tiles.
class HomeFocusController {
  static const _scrollDuration = Motion.focus;

  final ScrollController scroll = ScrollController();
  final FocusNode heroNode = FocusNode(debugLabel: "hero", canRequestFocus: false, skipTraversal: true);
  final FocusNode gridNode = FocusNode(debugLabel: "grid", canRequestFocus: false, skipTraversal: true);

  /// The home screen's geometry, set by its layout on every build.
  HomeLayout? layout;

  // The grid window on screen, -1 while the hero is.
  int _gridWindow = -1;

  // The hero tile focused last, which up from the grid returns to.
  FocusNode? _lastHeroTile;

  // A tile that should take focus once it is built, after the hero changed under the focused tile.
  ({String packageName, bool inHero, bool move})? _pending;

  /// The tile of [packageName] in the hero or the grid takes focus once it is built, and starts moving if [move].
  void focusWhenBuilt(String packageName, {required bool inHero, bool move = false}) =>
      _pending = (packageName: packageName, inHero: inHero, move: move);

  /// [app] is leaving the hero: focus stays in the hero on the tile that takes its place, or follows the app into
  /// the grid when it was the last one.
  void focusAfterLeavingHero(App app, List<App> hero) {
    final index = hero.indexWhere((other) => other.packageName == app.packageName);
    if (index < 0) {
      return;
    }
    if (hero.length == 1) {
      focusWhenBuilt(app.packageName, inHero: false);
    } else {
      final neighbour = index + 1 < hero.length ? hero[index + 1] : hero[index - 1];
      focusWhenBuilt(neighbour.packageName, inHero: true);
    }
  }

  /// Whether a tile is waiting to take focus for [packageName] in that region.
  bool isPending(String packageName, bool inHero) => _pending?.packageName == packageName && _pending?.inHero == inHero;

  /// Takes the pending focus for [packageName]; null if there is none for it, else whether to start moving.
  bool? claimFocus(String packageName, bool inHero) {
    final pending = _pending;
    if (pending == null || !isPending(packageName, inHero)) {
      return null;
    }
    _pending = null;
    return pending.move;
  }

  double get heroZoneHeight => layout?.heroZoneHeight ?? 0;

  bool get gridHasFocus => gridNode.hasFocus;

  bool get hasFocusedTile => heroNode.hasFocus || gridNode.hasFocus;

  /// Scrolls to the top and focuses the first hero tile, or the first grid tile when the hero is empty.
  void focusFirstTile({bool animate = false}) {
    _gridWindow = -1;
    if (scroll.hasClients) {
      animate ? scroll.animateTo(0, duration: _scrollDuration, curve: Motion.curve) : scroll.jumpTo(0);
    }
    (_firstTraversable(heroNode) ?? _firstTraversable(gridNode))?.requestFocus();
  }

  /// Up from the grid's first row goes to the hero tile nearest the focused column, not to whatever happens to be
  /// above it on screen (the hero is scrolled out of view then, so plain geometry would pick the gear). When down
  /// from the hero tile focused last would land on the focused tile, up goes back to that tile, so a straight round
  /// trip ends where it started even where two hero tiles are about equally near.
  KeyEventResult handleGridKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) {
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
    final last = _lastHeroTile;
    if (last != null && heroTiles.contains(last)) {
      final firstRow = gridNode.traversalDescendants.where((tile) => tile.isOnTheSameRow(current));
      if (_nearestInX(firstRow, last) == current) {
        last.requestFocus();
        return KeyEventResult.handled;
      }
    }
    _nearestInX(heroTiles, current).requestFocus();
    return KeyEventResult.handled;
  }

  FocusNode _nearestInX(Iterable<FocusNode> tiles, FocusNode to) {
    final x = to.rect.center.dx;
    return tiles.reduce((a, b) => (b.rect.center.dx - x).abs() < (a.rect.center.dx - x).abs() ? b : a);
  }

  /// From the gear, left and down go back to the hero: the tile focused there last (where the light still is), else
  /// the one nearest the gear (the last).
  bool focusHeroFromGear() {
    final heroTiles = heroNode.traversalDescendants.toList();
    if (heroTiles.isEmpty) {
      return false;
    }
    final last = _lastHeroTile;
    (last != null && heroTiles.contains(last) ? last : heroTiles.last).requestFocus();
    return true;
  }

  void revealTile(BuildContext tileContext, {required bool inHero}) {
    if (inHero) {
      _lastHeroTile = FocusManager.instance.primaryFocus;
    }
    if (!scroll.hasClients) {
      return;
    }
    final layout = this.layout;
    if (inHero || layout == null) {
      _gridWindow = -1;
      _animateTo(0);
      return;
    }
    final renderObject = tileContext.findRenderObject();
    final viewport = renderObject == null ? null : RenderAbstractViewport.of(renderObject);
    if (renderObject == null || viewport == null) {
      return;
    }
    // The offset that would put the tile at the top edge is its position in the page, which gives its row.
    final tileTop = viewport.getOffsetToReveal(renderObject, 0).offset;
    final row = max(0, ((tileTop - layout.gridTop) / layout.rowPitch).round());
    _gridWindow = layout.windowFor(row, _gridWindow);
    _animateTo(min(layout.windowOffset(_gridWindow), scroll.position.maxScrollExtent));
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
    scroll.animateTo(offset, duration: _scrollDuration, curve: Motion.curve);
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

  RevealOnFocus({super.key, required this.inHero, required this.child});

  @override
  State<RevealOnFocus> createState() => _RevealOnFocusState();
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
