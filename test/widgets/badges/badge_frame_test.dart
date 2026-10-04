// Issue #220 — one badge's look, set in `badge_style.dart`: bronze, silver
// and gold for the first three tiers and dots past them, grey when not
// earned, a "?" for a secret not found, the glyph at half the frame — and,
// in both themes, a glyph that stands off its metal by light and dark.

import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/theme/badge_style.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/badges/badge_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast of two colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final effort = BadgeCatalog.byId('effort')!; // six tiers
  final writer = BadgeCatalog.byId('writer')!; // three tiers

  group('the tone and the dots of a badge at a tier', () {
    test('none earned is grey; then bronze, silver, gold', () {
      expect(BadgeFrame.of(effort, tier: 0).tone, BadgeTone.locked);
      expect(BadgeFrame.of(effort, tier: 1).tone, BadgeTone.bronze);
      expect(BadgeFrame.of(effort, tier: 2).tone, BadgeTone.silver);
      expect(BadgeFrame.of(effort, tier: 3).tone, BadgeTone.gold);
      expect(BadgeFrame.of(effort, tier: 6).tone, BadgeTone.gold);
    });

    test('past the third tier, a dot per tier: reached ones and the ones '
        'still to come', () {
      expect(BadgeFrame.of(effort, tier: 2).pips, 0);
      final third = BadgeFrame.of(effort, tier: 3);
      expect((third.pips, third.pipsReached), (3, 0));
      final fifth = BadgeFrame.of(effort, tier: 5);
      expect((fifth.pips, fifth.pipsReached), (3, 2));
      final top = BadgeFrame.of(writer, tier: 3);
      expect(top.pips, 0, reason: 'nothing past three to count');
    });

    test('a "Kenner van …" and a single badge have their own tone', () {
      expect(
        BadgeFrame.of(BadgeCatalog.expert('r1'), tier: 1).tone,
        BadgeTone.expert,
      );
      expect(
        BadgeFrame.of(BadgeCatalog.byId('helloWorld')!, tier: 1).tone,
        BadgeTone.fun,
      );
      expect(
        BadgeFrame.of(BadgeCatalog.byId('helloWorld')!, tier: 0).tone,
        BadgeTone.locked,
      );
    });
  });

  group('the colours, in both themes', () {
    const earned = [
      BadgeTone.bronze,
      BadgeTone.silver,
      BadgeTone.gold,
      BadgeTone.expert,
      BadgeTone.fun,
    ];

    for (final palette in const [AppPalette.dark, AppPalette.light]) {
      final name = palette.isDark ? 'dark' : 'light';

      test('$name: every earned tone has its own metal', () {
        final fills = {
          for (final t in earned) BadgeStyle.colorsFor(palette, t).fill,
        };
        expect(fills, hasLength(earned.length));
      });

      test(
        '$name: the glyph stands off the metal by value (at least 4.5:1)',
        () {
          for (final tone in earned) {
            final c = BadgeStyle.colorsFor(palette, tone);
            expect(
              _contrast(c.fill, c.glyph),
              greaterThanOrEqualTo(4.5),
              reason: '$name $tone',
            );
          }
        },
      );

      test('$name: the rim is darker than the fill', () {
        for (final tone in earned) {
          final c = BadgeStyle.colorsFor(palette, tone);
          expect(
            c.rim.computeLuminance(),
            lessThan(c.fill.computeLuminance()),
            reason: '$name $tone',
          );
        }
      });

      test('$name: gold is the palette\'s own soft gold', () {
        expect(
          BadgeStyle.colorsFor(palette, BadgeTone.gold).fill,
          palette.accent2,
        );
      });

      test('$name: not earned is the palette\'s grey', () {
        final c = BadgeStyle.colorsFor(palette, BadgeTone.locked);
        expect(c.fill, palette.ink2);
        expect(c.glyph, palette.fgFaint);
      });
    }
  });

  group('the widget', () {
    Future<void> pump(WidgetTester tester, Widget frame) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: frame)),
      ),
    );

    for (final size in [32.0, 64.0, 128.0]) {
      testWidgets('at $size px the glyph takes half the frame', (tester) async {
        await pump(tester, BadgeFrame.of(effort, tier: 2, size: size));
        expect(tester.getSize(find.byType(BadgeFrame)), Size(size, size));
        final glyph = find.byType(SvgPicture);
        expect(glyph, findsOneWidget);
        expect(tester.getSize(glyph), Size(size / 2, size / 2));
        expect(
          tester.widget<SvgPicture>(glyph).bytesLoader,
          isA<SvgAssetLoader>().having(
            (l) => l.assetName,
            'asset',
            'assets/badges/weight-lifting-up.svg',
          ),
        );
      });
    }

    testWidgets('a secret not found shows a "?" and not its glyph', (
      tester,
    ) async {
      await pump(
        tester,
        BadgeFrame.of(BadgeCatalog.byId('rubberDuck')!, tier: 0, hidden: true),
      );
      expect(find.text('?'), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('a label reaches the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        BadgeFrame.of(effort, tier: 1, semanticLabel: 'Effort'),
      );
      expect(find.bySemanticsLabel('Effort'), findsOneWidget);
      handle.dispose();
    });
  });
}
