// One badge (#220): the frame drawn in code, the game-icons.net glyph in it.
// Shape, colours and sizes come from `theme/badge_style.dart`.

import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/theme/badge_style.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BadgeFrame extends StatelessWidget {
  const BadgeFrame({
    super.key,
    required this.icon,
    required this.tone,
    this.size = 64,
    this.pips = 0,
    this.pipsReached = 0,
    this.hidden = false,
    this.palette,
    this.semanticLabel,
  });

  /// [badge] at [tier]: its tone, and its dots past the third tier. A
  /// secret not found yet is [hidden]: a grey "?" instead of its glyph.
  factory BadgeFrame.of(
    BadgeDefinition badge, {
    Key? key,
    required int tier,
    double size = 64,
    bool hidden = false,
    AppPalette? palette,
    String? semanticLabel,
  }) {
    final extra = badge.maxTier - BadgeStyle.colouredTiers;
    final showPips = extra > 0 && tier >= BadgeStyle.colouredTiers;
    return BadgeFrame(
      key: key,
      icon: badge.icon,
      tone: BadgeStyle.toneFor(badge.group, tier),
      size: size,
      pips: showPips ? extra : 0,
      pipsReached: showPips ? tier - BadgeStyle.colouredTiers : 0,
      hidden: hidden,
      palette: palette,
      semanticLabel: semanticLabel,
    );
  }

  final BadgeIcon icon;
  final BadgeTone tone;

  /// The frame's width and height.
  final double size;

  /// Dots past the third tier: how many tiers there are past it…
  final int pips;

  /// …and how many of those are reached.
  final int pipsReached;

  /// A secret not found yet.
  final bool hidden;

  /// The palette to paint in; the active one when `null`. The proof sheet
  /// passes both, side by side.
  final AppPalette? palette;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? AppColors.palette;
    final colors = BadgeStyle.colorsFor(p, hidden ? BadgeTone.locked : tone);
    final glyphSize = size * BadgeStyle.glyphFraction;
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _FramePainter(
            colors: colors,
            pips: hidden ? 0 : pips,
            pipsReached: pipsReached,
            pipColors: BadgeStyle.pipColors(p, colors),
          ),
          child: Center(
            child: hidden
                ? Text(
                    '?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.glyph,
                      fontSize: glyphSize,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  )
                : SvgPicture.asset(
                    icon.asset,
                    width: glyphSize,
                    height: glyphSize,
                    colorFilter: ColorFilter.mode(
                      colors.glyph,
                      BlendMode.srcIn,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.colors,
    required this.pips,
    required this.pipsReached,
    required this.pipColors,
  });

  final BadgeColors colors;
  final int pips;
  final int pipsReached;
  final ({Color reached, Color open, Color edge}) pipColors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rim = s * BadgeStyle.rimFraction;
    canvas.drawPath(BadgeStyle.framePath(s), Paint()..color = colors.rim);
    canvas.drawPath(
      BadgeStyle.framePath(s, inset: rim),
      Paint()..color = colors.fill,
    );
    if (pips <= 0) return;
    final d = BadgeStyle.pipDiameter(s);
    final gap = d * 0.6;
    final width = pips * d + (pips - 1) * gap;
    final y = s * BadgeStyle.pipCentreFraction;
    var x = (s - width) / 2 + d / 2;
    for (var i = 0; i < pips; i++) {
      final centre = Offset(x, y);
      canvas.drawCircle(centre, d / 2 + 0.75, Paint()..color = pipColors.edge);
      canvas.drawCircle(
        centre,
        d / 2,
        Paint()..color = i < pipsReached ? pipColors.reached : pipColors.open,
      );
      x += d + gap;
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.colors.fill != colors.fill ||
      old.colors.rim != colors.rim ||
      old.pips != pips ||
      old.pipsReached != pipsReached ||
      old.pipColors != pipColors;
}
