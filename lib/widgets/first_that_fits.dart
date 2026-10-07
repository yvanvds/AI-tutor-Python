import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Rounding slack when a width is compared with the room for it.
const double _tolerance = 1e-6;

/// Shows the first of [children] that fits the width it is given, and only
/// that one (#258).
///
/// The children are the same content spelled out less and less: the richest
/// form first, the most compact one last. Each is measured at its natural
/// width; the first that is no wider than the incoming maximum is the one on
/// screen, and the box takes its size. When none fits, the last is shown,
/// clipped to the box, so the content never paints past it.
///
/// The others are measured only: they are not painted, not hit, not
/// announced to accessibility and — like the hidden pages of an
/// [IndexedStack] — skipped by a test's finders, so a `find.text` finds the
/// form that is on screen and nothing else.
///
/// A parent that wants to know how little room the content can do with asks
/// the minimum intrinsic width: the natural width of the narrowest form. The
/// maximum intrinsic width is that of the widest.
///
/// Each child is laid out with an unbounded width, so it must size itself
/// (no [Expanded] or `double.infinity` at its top).
class FirstThatFits extends MultiChildRenderObjectWidget {
  const FirstThatFits({super.key, required super.children});

  @override
  RenderFirstThatFits createRenderObject(BuildContext context) =>
      RenderFirstThatFits();

  @override
  MultiChildRenderObjectElement createElement() => _FirstThatFitsElement(this);
}

class _FirstThatFitsElement extends MultiChildRenderObjectElement {
  _FirstThatFitsElement(FirstThatFits super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final shown = (renderObject as RenderFirstThatFits).shown;
    for (final child in children) {
      if (child.renderObject == shown) visitor(child);
    }
  }
}

class FirstThatFitsParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object behind [FirstThatFits].
class RenderFirstThatFits extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, FirstThatFitsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, FirstThatFitsParentData> {
  /// The child on screen after the last layout; `null` before the first one
  /// or without children.
  RenderBox? get shown => _shown;
  RenderBox? _shown;

  bool _clipped = false;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! FirstThatFitsParentData) {
      child.parentData = FirstThatFitsParentData();
    }
  }

  List<RenderBox> get _children {
    final all = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      all.add(child);
      child = childAfter(child);
    }
    return all;
  }

  /// What a child is measured against: any width, the incoming height.
  static BoxConstraints _measuring(BoxConstraints constraints) =>
      BoxConstraints(maxHeight: constraints.maxHeight);

  static bool _fits(double width, double maxWidth) =>
      width <= maxWidth + _tolerance;

  @override
  double computeMinIntrinsicWidth(double height) {
    final all = _children;
    if (all.isEmpty) return 0;
    return all.map((c) => c.getMaxIntrinsicWidth(height)).reduce(math.min);
  }

  @override
  double computeMaxIntrinsicWidth(double height) => _children.fold(
    0,
    (most, c) => math.max(most, c.getMaxIntrinsicWidth(height)),
  );

  /// The child that would be on screen at [width], judged by intrinsics.
  RenderBox? _intrinsicPick(double width) {
    final all = _children;
    for (final c in all) {
      if (_fits(c.getMaxIntrinsicWidth(double.infinity), width)) return c;
    }
    return all.isEmpty ? null : all.last;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicPick(width)?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicPick(width)?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final measuring = _measuring(constraints);
    Size? last;
    for (final c in _children) {
      final size = c.getDryLayout(measuring);
      if (_fits(size.width, constraints.maxWidth)) {
        return constraints.constrain(size);
      }
      last = size;
    }
    return constraints.constrain(last ?? Size.zero);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _shown?.getDistanceToActualBaseline(baseline);

  @override
  void performLayout() {
    final measuring = _measuring(constraints);
    RenderBox? pick;
    for (final c in _children) {
      c.layout(measuring, parentUsesSize: true);
      if (pick == null && _fits(c.size.width, constraints.maxWidth)) pick = c;
    }
    pick ??= lastChild;
    if (pick != _shown) {
      _shown = pick;
      // Another form, another text to announce.
      markNeedsSemanticsUpdate();
    }
    if (pick == null) {
      size = constraints.smallest;
      _clipped = false;
      return;
    }
    size = constraints.constrain(pick.size);
    _clipped =
        pick.size.width > size.width + _tolerance ||
        pick.size.height > size.height + _tolerance;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shown = _shown;
    if (shown == null) return;
    if (!_clipped) {
      _clip.layer = null;
      context.paintChild(shown, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(shown, offset),
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final shown = _shown;
    if (shown == null) return false;
    return shown.hitTest(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final shown = _shown;
    if (shown != null) visitor(shown);
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
