/// Per-widget content scale for drawn desklets. PHASE 4.
///
/// ─── WHY NOT Transform.scale ────────────────────────────────────────────────
///
/// A transform changes what is painted, not what is laid out: a card scaled to
/// 120% still reports its old size, so it either spills over its neighbours or
/// is clipped. Content scale has to be a LAYOUT change. The child is laid out
/// in the space divided by [scale] and then painted multiplied by it, so a
/// bounded card wraps to a narrower width and comes back to exactly the cell's
/// width, larger, with its height growing to match. The `FittedBox` above it
/// still shrinks anything that ends up too tall for the cell, so a scale can
/// make a widget larger but never push it off its tile.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The smallest and largest content scale offered.
const double minContentScale = 0.8;
const double maxContentScale = 1.2;

/// Reads a desklet's stored content scale, clamped on read like every other
/// config value. Anything missing or malformed is 1, as the widget was drawn.
double contentScaleOf(Map<String, Object?> config) {
  final raw = config['scale'];
  if (raw is! num) return 1;
  return raw.toDouble().clamp(minContentScale, maxContentScale);
}

class ContentScale extends SingleChildRenderObjectWidget {
  const ContentScale({super.key, required this.scale, super.child});

  final double scale;

  @override
  RenderContentScale createRenderObject(BuildContext context) =>
      RenderContentScale(scale);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderContentScale renderObject,
  ) =>
      renderObject.scale = scale;
}

class RenderContentScale extends RenderProxyBox {
  RenderContentScale(this._scale);

  double _scale;

  double get scale => _scale;

  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsLayout();
  }

  /// [c] divided by the scale; an unbounded edge stays unbounded.
  BoxConstraints _inner(BoxConstraints c) => BoxConstraints(
        minWidth: c.minWidth / _scale,
        maxWidth: c.maxWidth.isFinite ? c.maxWidth / _scale : double.infinity,
        minHeight: c.minHeight / _scale,
        maxHeight:
            c.maxHeight.isFinite ? c.maxHeight / _scale : double.infinity,
      );

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_inner(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size * _scale);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      child.getDryLayout(_inner(constraints)) * _scale,
    );
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer as TransformLayer?,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}
