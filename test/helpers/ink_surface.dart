// Shared probe for the "a ColoredBox hides the ListTile's ink" defect
// (#68 on the goals page, #69 on the instructions editor).
//
// `ListTile` paints its tile colour, its selected highlight and its ink
// splashes into the nearest `Material` *above* it, so any opaque box between
// the row and that Material is painted in front of all three and hides them.
// Flutter's own `ListTile._findIntermediateWidget` walks the tree exactly this
// way before reporting `ListTile background color or ink splashes may be
// invisible.`; this mirrors that walk so a test can assert on the surface
// instead of only on the absence of the framework's error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Walks up from [tile] the way `ListTile` does when it works out where its
/// background and ink will land: the first ancestor that is either a
/// `Material` (the surface it paints on) or an opaque box (which would be
/// painted *over* that surface and hide it).
Widget? firstSurfaceAbove(WidgetTester tester, Finder tile) {
  Widget? found;
  tester.element(tile).visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is Material) {
      found = w;
      return false;
    }
    final Color? color = switch (w) {
      ColoredBox(:final Color color) => color,
      DecoratedBox(decoration: BoxDecoration(:final Color? color)) => color,
      _ => null,
    };
    if (color != null && color.a > 0) {
      found = w;
      return false;
    }
    return true;
  });
  return found;
}
