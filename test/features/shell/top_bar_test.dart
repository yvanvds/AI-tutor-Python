// #258 — the top bar stays inside narrow windows: its greeting, mode
// switcher and stat strip never overlap and never run past the bar. Outside
// Session the mode switcher gives its place back; the stat strip drops the
// word "days" first, then the word of the difficulty chip (#256) and then
// the XP count when it has less room.
//
// Under the test font (Ahem, every glyph a full em) the parts are wider than
// in the app, so the widths here are not the app's; the real font and the
// real shell are in `integration_test/flows/top_bar_narrow.dart`.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/tutor/exercise_difficulty.dart';
import 'package:ai_tutor_python/widgets/first_that_fits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localization.dart';

const _student = Profile(
  name: 'Sam',
  topic: 'Basics',
  level: 1,
  xp: 0,
  xpNext: 500,
  streak: 3,
  role: Role.student,
);

/// The bar's horizontal padding (`AppSpacing.xxl`).
const double _padding = 28;

/// The room between its parts (`AppSpacing.lg`).
const double _gap = 16;

void main() {
  setUp(() {
    // As in app_locale_switch_test: Ahem at full size makes the mode
    // switcher alone ~390 px wide; at 0.7 the parts compare the way the
    // real font has them.
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .textScaleFactorTestValue =
        0.7;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearTextScaleFactorTestValue();
  });

  late ProviderContainer container;

  Future<void> pumpBar(WidgetTester tester, double windowWidth) async {
    tester.view.physicalSize = Size(windowWidth, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(
          const Scaffold(
            body: Row(
              children: [
                SizedBox(width: sidebarWidth),
                Expanded(child: Column(children: [TopBar()])),
              ],
            ),
          ),
        ),
      ),
    );
    // Past the switcher's fade, either way.
    await tester.pumpAndSettle();
  }

  setUp(() {
    container = ProviderContainer(
      overrides: [
        profileProvider.overrideWithValue(_student),
        ambientProgressProvider.overrideWithValue(0),
        calibrationDifficultyProvider.overrideWithValue(
          QuestionDifficulty.medium,
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);
  final bar = find.byType(TopBar);
  final greeting = find.text('Hi Sam,');
  final modes = find.byType(ModeSwitcher);
  final stats = find.byType(StatStrip);
  final difficulty = find.byType(DifficultyChip);

  /// The difficulty chip's word, when it is on screen (#256): the account's
  /// calibration, with no exercise in these tests.
  final difficultyWord = find.descendant(
    of: difficulty,
    matching: find.text('medium'),
  );
  const difficultyTooltip = 'Your difficulty level: medium';

  /// Inside the bar's padding, in order, a gap apart; the difficulty chip
  /// inside the strip.
  void expectLaidOut(WidgetTester tester, String where) {
    expect(tester.takeException(), isNull, reason: where);
    final b = rectOf(tester, bar);
    final g = rectOf(tester, greeting);
    final s = rectOf(tester, stats);
    expect(g.left, moreOrLessEquals(b.left + _padding), reason: where);
    expect(s.right, moreOrLessEquals(b.right - _padding), reason: where);
    final d = rectOf(tester, difficulty);
    expect(d.left, greaterThanOrEqualTo(s.left - 0.01), reason: where);
    expect(d.right, lessThanOrEqualTo(s.right + 0.01), reason: where);
    if (modes.evaluate().isEmpty) {
      expect(g.right + _gap, lessThanOrEqualTo(s.left + 0.01), reason: where);
    } else {
      final m = rectOf(tester, modes);
      expect(g.right + _gap, lessThanOrEqualTo(m.left + 0.01), reason: where);
      expect(m.right + _gap, lessThanOrEqualTo(s.left + 0.01), reason: where);
    }
  }

  /// The narrowest the strip can be: its last form, whole.
  double stripLeast(WidgetTester tester) => tester
      .renderObject<RenderFirstThatFits>(
        find.descendant(of: stats, matching: find.byType(FirstThatFits)),
      )
      .getMinIntrinsicWidth(double.infinity);

  testWidgets('in a wide window the strip spells everything out, the '
      'switcher centred', (tester) async {
    await pumpBar(tester, 1400);
    expectLaidOut(tester, '1400 px');
    expect(find.text('days'), findsOneWidget);
    expect(difficultyWord, findsOneWidget);
    expect(find.text('0 / 500'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    // One tooltip: the hidden forms' are not there to hover.
    expect(find.byTooltip(difficultyTooltip), findsOneWidget);
    final b = rectOf(tester, bar);
    expect(rectOf(tester, modes).center.dx, moreOrLessEquals(b.center.dx));
  });

  testWidgets('from 1400 down to 700 px the parts stay inside the bar and '
      'apart, in Session and outside it', (tester) async {
    for (final section in [Section.session, Section.map]) {
      container.read(sectionProvider.notifier).state = section;
      for (var width = 1400.0; width >= 700; width -= 20) {
        await pumpBar(tester, width);
        expectLaidOut(tester, '$section at $width px');
        expect(
          find.text('Level 1'),
          findsOneWidget,
          reason: '$section at $width px',
        );
      }
    }
  });

  testWidgets('at 700 px the strip drops "days", the difficulty word and '
      'then the count in Session, and has them back where the switcher gave '
      'its place back', (tester) async {
    await pumpBar(tester, 700);
    expect(modes, findsOneWidget);
    expect(find.text('days'), findsNothing);
    expect(difficultyWord, findsNothing);
    expect(find.text('0 / 500'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    // The chip itself stays, its bars and all.
    expect(difficulty, findsOneWidget);
    expect(find.byType(DifficultyBars), findsOneWidget);
    // What is dropped is still there to hover.
    expect(find.byTooltip('3 days'), findsOneWidget);
    expect(find.byTooltip(difficultyTooltip), findsOneWidget);
    expect(find.byTooltip('0 / 500'), findsOneWidget);

    container.read(sectionProvider.notifier).state = Section.map;
    await tester.pumpAndSettle();
    expect(modes, findsNothing);
    expect(find.text('Explain'), findsNothing);
    expect(find.text('days'), findsOneWidget);
    expect(difficultyWord, findsOneWidget);
    expect(find.text('0 / 500'), findsOneWidget);
    expectLaidOut(tester, 'Learning path at 700 px');
  });

  testWidgets('when the strip at its narrowest needs more than its side of a '
      'centred switcher, the switcher moves left to make room', (tester) async {
    await pumpBar(tester, 1400);
    final switcher = rectOf(tester, modes).width;
    final least = stripLeast(tester);

    // The bar's inner width with room for the switcher and twice the
    // narrowest strip: a centred switcher leaves the strip `least - gap`.
    final inner = switcher + 2 * least;
    await pumpBar(tester, sidebarWidth + 2 * _padding + inner);
    expectLaidOut(tester, 'switcher + 2 strips');
    expect(rectOf(tester, stats).width, moreOrLessEquals(least));
    expect(
      rectOf(tester, modes).center.dx,
      lessThan(rectOf(tester, bar).center.dx),
    );
  });

  testWidgets('the mode switcher in a narrow bar still takes a click', (
    tester,
  ) async {
    await pumpBar(tester, 700);
    expect(container.read(modeProvider), SessionMode.explain);
    await tester.tap(find.text('Practice'));
    await tester.pump();
    expect(container.read(modeProvider), SessionMode.practice);
  });
}
