import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A stretched vertical stack that puts [gap] only between children that
/// actually draw something.
///
/// `Column` with `SizedBox` spacers (or `Column.spacing`) spends the gap on a
/// child that collapsed to `SizedBox.shrink()`, so an optional section that
/// had nothing to show still left a blank strip behind it. Here a child laid
/// out at zero height is skipped, gap included.
class GapColumn extends MultiChildRenderObjectWidget {
  const GapColumn({super.key, required super.children, this.gap = 12});

  final double gap;

  @override
  RenderGapColumn createRenderObject(BuildContext context) =>
      RenderGapColumn(gap: gap);

  @override
  void updateRenderObject(BuildContext context, RenderGapColumn renderObject) {
    renderObject.gap = gap;
  }
}

class _GapParentData extends ContainerBoxParentData<RenderBox> {}

class RenderGapColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GapParentData> {
  RenderGapColumn({required double gap}) : _gap = gap;

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GapParentData) {
      child.parentData = _GapParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;
    final childConstraints = BoxConstraints.tightFor(width: width);
    var y = 0.0;
    var drawn = false;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _GapParentData;
      child.layout(childConstraints, parentUsesSize: true);
      final h = child.size.height;
      if (h > 0 && drawn) y += _gap;
      data.offset = Offset(0, y);
      if (h > 0) {
        y += h;
        drawn = true;
      }
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsic(
        (c) => c.getMinIntrinsicHeight(width),
      );

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsic(
        (c) => c.getMaxIntrinsicHeight(width),
      );

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widest((c) => c.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widest((c) => c.getMaxIntrinsicWidth(double.infinity));

  double _intrinsic(double Function(RenderBox) measure) {
    var total = 0.0;
    var drawn = false;
    var child = firstChild;
    while (child != null) {
      final h = measure(child);
      if (h > 0) {
        if (drawn) total += _gap;
        total += h;
        drawn = true;
      }
      child = (child.parentData! as _GapParentData).nextSibling;
    }
    return total;
  }

  double _widest(double Function(RenderBox) measure) {
    var widest = 0.0;
    var child = firstChild;
    while (child != null) {
      widest = math.max(widest, measure(child));
      child = (child.parentData! as _GapParentData).nextSibling;
    }
    return widest;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
