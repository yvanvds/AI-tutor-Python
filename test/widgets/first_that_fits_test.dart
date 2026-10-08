// #258 — `FirstThatFits` shows the richest of its forms that fits the room
// it gets, and only that one: the others are measured, not painted, hit,
// announced or found.

import 'package:ai_tutor_python/widgets/first_that_fits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A form of [width] logical pixels that counts its taps in [taps].
  Widget form(String label, double width, Map<String, int> taps) =>
      GestureDetector(
        onTap: () => taps[label] = (taps[label] ?? 0) + 1,
        child: SizedBox(width: width, height: 20, child: Text(label)),
      );

  Future<RenderFirstThatFits> pumpIn(
    WidgetTester tester,
    double room,
    Map<String, int> taps,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: room),
            child: FirstThatFits(
              children: [
                form('wide', 300, taps),
                form('mid', 200, taps),
                form('narrow', 100, taps),
              ],
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderFirstThatFits>(find.byType(FirstThatFits));
  }

  testWidgets('shows the first form that fits, and finds no other', (
    tester,
  ) async {
    final taps = <String, int>{};

    await pumpIn(tester, 400, taps);
    expect(find.text('wide'), findsOneWidget);
    expect(find.text('mid'), findsNothing);
    expect(find.text('narrow'), findsNothing);
    expect(tester.getSize(find.byType(FirstThatFits)).width, 300);

    await pumpIn(tester, 250, taps);
    expect(find.text('wide'), findsNothing);
    expect(find.text('mid'), findsOneWidget);
    expect(find.text('narrow'), findsNothing);
    expect(tester.getSize(find.byType(FirstThatFits)).width, 200);

    // Exactly the room it needs is room enough.
    await pumpIn(tester, 100, taps);
    expect(find.text('narrow'), findsOneWidget);
    expect(find.text('mid'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no room for any form, the last is shown clipped to the '
      'box, not painted past it', (tester) async {
    await pumpIn(tester, 60, <String, int>{});
    expect(tester.takeException(), isNull);
    expect(find.text('narrow'), findsOneWidget);
    expect(tester.getSize(find.byType(FirstThatFits)).width, 60);
    // The 100 px form, clipped to the 60 px box.
    expect(
      find.byType(FirstThatFits),
      paints..clipRect(rect: const Rect.fromLTWH(0, 0, 60, 20)),
    );
  });

  testWidgets('only the form on screen takes a tap', (tester) async {
    final taps = <String, int>{};
    await pumpIn(tester, 250, taps);

    await tester.tap(find.text('mid'));
    expect(taps, {'mid': 1});

    // Where the narrow and the wide form would be too: still only the one
    // on screen.
    await tester.tapAt(
      tester.getTopLeft(find.byType(FirstThatFits)) + const Offset(40, 10),
    );
    expect(taps, {'mid': 2});
  });

  testWidgets('only the form on screen is announced', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpIn(tester, 250, <String, int>{});

    expect(find.bySemanticsLabel('mid'), findsOneWidget);
    expect(find.bySemanticsLabel('wide'), findsNothing);
    expect(find.bySemanticsLabel('narrow'), findsNothing);

    // More room, another form: that one is announced instead.
    await pumpIn(tester, 400, <String, int>{});
    expect(find.bySemanticsLabel('wide'), findsOneWidget);
    expect(find.bySemanticsLabel('mid'), findsNothing);
    semantics.dispose();
  });

  testWidgets('its minimum intrinsic width is its narrowest form, its '
      'maximum the widest', (tester) async {
    final box = await pumpIn(tester, 250, <String, int>{});
    expect(box.getMinIntrinsicWidth(double.infinity), 100);
    expect(box.getMaxIntrinsicWidth(double.infinity), 300);
    expect(
      box.getDryLayout(const BoxConstraints(maxWidth: 250)),
      const Size(200, 20),
    );
    expect(
      box.getDryLayout(const BoxConstraints(maxWidth: 60)),
      const Size(60, 20),
    );
  });
}
