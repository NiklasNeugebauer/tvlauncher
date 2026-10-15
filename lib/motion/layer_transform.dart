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

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [Transform] about [alignment] that lives in its own layer: changing [transform] updates that layer and
/// repaints nothing, neither the child nor what is around it. A plain [Transform] repaints its parent's picture on
/// every step, and with it every sibling there. For a child that moves on every frame of an animation.
class LayerTransform extends SingleChildRenderObjectWidget {
  final Matrix4 transform;
  final Alignment alignment;

  const LayerTransform({super.key, required this.transform, this.alignment = Alignment.center, super.child});

  @override
  RenderLayerTransform createRenderObject(BuildContext context) =>
      RenderLayerTransform(transform: transform, alignment: alignment);

  @override
  void updateRenderObject(BuildContext context, RenderLayerTransform renderObject) => renderObject
    ..transform = transform
    ..alignment = alignment;
}

class RenderLayerTransform extends RenderProxyBox {
  RenderLayerTransform({required this._transform, required this._alignment});

  Matrix4 _transform;
  set transform(Matrix4 value) {
    if (_transform == value) return;
    _transform = value;
    _changed();
  }

  Alignment _alignment;
  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    _changed();
  }

  void _changed() {
    markNeedsCompositedLayerUpdate();
    markNeedsSemanticsUpdate();
  }

  @override
  bool get isRepaintBoundary => true;

  // The aligned point moves with the size.
  @override
  void performLayout() {
    final old = hasSize ? size : null;
    super.performLayout();
    if (size != old) markNeedsCompositedLayerUpdate();
  }

  /// [transform] about the aligned point, in the layer's coordinates (the framework adds the offset).
  Matrix4 get _effective {
    final origin = _alignment.alongSize(size);
    return Matrix4.translationValues(origin.dx, origin.dy, 0)
      ..multiply(_transform)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
  }

  @override
  OffsetLayer updateCompositedLayer({required covariant TransformLayer? oldLayer}) =>
      (oldLayer ?? TransformLayer())..transform = _effective;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintTransform(
    transform: _effective,
    position: position,
    hitTest: (result, position) => super.hitTestChildren(result, position: position),
  );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_effective);
}
