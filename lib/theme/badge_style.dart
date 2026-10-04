// How a badge looks (#220) — the frame's shape, the tier colours and the
// glyph's size, in this one file, so the teacher's review of the proof sheet
// turns into a change here and nowhere else.
//
// The game-icons.net silhouettes are heavier than the rest of the app. The
// frame makes up for that:
//
//   - the glyph takes about half the frame ([glyphFraction]), with plenty of
//     room around it;
//   - contrast comes from light against dark, not from bright colour: the
//     metals are muted tones mixed from the palette's own accents (`accent2`
//     is already a soft gold), and the glyph is the canvas colour on them in
//     the dark theme and near-white in the light one;
//   - bronze, silver and gold are the first three tiers; past the third,
//     dots under the glyph count the tiers ([pipColors]);
//   - a badge not earned is grey; a secret one not found is a grey "?".
//
// Every colour is worked out from an [AppPalette], so the same badge reads
// in both themes and the proof sheet can put the two side by side.

import 'dart:math' as math;

import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The colour family of a frame.
enum BadgeTone {
  /// Not earned.
  locked,
  bronze,
  silver,
  gold,

  /// "Kenner van …": a muted leaf green.
  expert,

  /// The single, not so serious badges: a muted blue.
  fun,
}

/// The colours one frame is painted with.
@immutable
class BadgeColors {
  const BadgeColors({
    required this.fill,
    required this.rim,
    required this.glyph,
  });

  final Color fill;
  final Color rim;
  final Color glyph;
}

class BadgeStyle {
  BadgeStyle._();

  /// The glyph's width and height, as a share of the frame's.
  static const double glyphFraction = 0.5;

  /// The rim's width, as a share of the frame's.
  static const double rimFraction = 0.06;

  /// How round the hexagon's corners are, as a share of the frame's width.
  static const double cornerFraction = 0.1;

  /// The tiers shown by colour; the ones past it by dots.
  static const int colouredTiers = 3;

  /// The dots' diameter, as a share of the frame — never under 2.5 px, so
  /// they stay visible on a 32 px frame.
  static double pipDiameter(double size) => math.max(2.5, size * 0.08);

  /// Where the dots sit: their centres, as a share of the frame's height.
  static const double pipCentreFraction = 0.86;

  /// The tone of [badge] at [tier].
  static BadgeTone toneFor(BadgeGroup group, int tier) {
    if (tier <= 0) return BadgeTone.locked;
    return switch (group) {
      BadgeGroup.experts => BadgeTone.expert,
      BadgeGroup.fun => BadgeTone.fun,
      BadgeGroup.tiers => switch (tier) {
        1 => BadgeTone.bronze,
        2 => BadgeTone.silver,
        _ => BadgeTone.gold,
      },
    };
  }

  /// The fill of [tone] in [p]: the metals mixed from the palette, muted
  /// toward its foreground grey.
  static Color fillOf(AppPalette p, BadgeTone tone) => switch (tone) {
    BadgeTone.locked => p.ink2,
    // Sand pulled toward terracotta: a warm, darker bronze.
    BadgeTone.bronze => Color.lerp(
      Color.lerp(p.accent2, p.danger, 0.5)!,
      p.isDark ? p.ink0 : p.fgMute,
      p.isDark ? 0.15 : 0.3,
    )!,
    // The foreground grey with a touch of the info blue: a cool silver.
    BadgeTone.silver => Color.lerp(
      p.isDark ? p.fgMute : p.fgFaint,
      p.accent3,
      0.2,
    )!,
    // `accent2` is the palette's soft gold already.
    BadgeTone.gold => p.accent2,
    BadgeTone.expert => Color.lerp(p.accent, p.fgMute, 0.3)!,
    BadgeTone.fun => Color.lerp(p.accent3, p.fgMute, 0.3)!,
  };

  /// The colours of a frame of [tone] in [p].
  static BadgeColors colorsFor(AppPalette p, BadgeTone tone) {
    if (tone == BadgeTone.locked) {
      return BadgeColors(fill: p.ink2, rim: p.ink3, glyph: p.fgFaint);
    }
    final fill = fillOf(p, tone);
    return BadgeColors(
      fill: fill,
      // A darker edge of the same metal: depth by value, not by colour.
      rim: Color.lerp(fill, p.isDark ? p.ink0 : Colors.black, 0.3)!,
      glyph: p.isDark ? p.ink0 : p.ink1,
    );
  }

  /// The dots past the third tier: a reached one in the palette's leaf
  /// green, one still to come in the divider grey, each with an edge in the
  /// glyph colour so it stands off the metal.
  static ({Color reached, Color open, Color edge}) pipColors(
    AppPalette p,
    BadgeColors frame,
  ) => (reached: p.accent, open: p.ink3, edge: frame.glyph);

  /// The frame: a hexagon with a point at the top and the bottom and round
  /// corners, filling the [size] × [size] square from top to bottom.
  static Path framePath(double size, {double inset = 0}) {
    final centre = Offset(size / 2, size / 2);
    final radius = size / 2 - inset;
    final corners = <Offset>[
      for (var i = 0; i < 6; i++)
        centre + Offset.fromDirection(-math.pi / 2 + i * math.pi / 3, radius),
    ];
    final round = size * cornerFraction;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final corner = corners[i];
      final before = corners[(i + 5) % 6];
      final after = corners[(i + 1) % 6];
      final into = corner + _toward(corner, before, round);
      final out = corner + _toward(corner, after, round);
      if (i == 0) {
        path.moveTo(into.dx, into.dy);
      } else {
        path.lineTo(into.dx, into.dy);
      }
      path.quadraticBezierTo(corner.dx, corner.dy, out.dx, out.dy);
    }
    return path..close();
  }

  static Offset _toward(Offset from, Offset to, double distance) {
    final d = to - from;
    return d / d.distance * distance;
  }
}
