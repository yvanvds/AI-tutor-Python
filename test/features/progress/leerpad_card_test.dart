// Issue #161 — the leerpad's "finished" marks come from the `advancedAt`
// stamp on the progress doc, while every bar keeps the honest mastered
// fraction. A subgoal the conductor advanced past with a stuck LO shows its
// check mark *and* a bar short of 100%; the root reads "completed" only once
// every required subgoal has been advanced past, whatever its average bar.
// A doc from before the stamp existed (1.0, no stamp) still counts as
// finished, and a half-mastered subgoal without the stamp is simply open.

import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localization.dart';

final _root = Goal(id: 'r', title: 'Basics', order: 0);
final _print = Goal(id: 's1', title: 'Print', parentId: 'r', order: 1);
final _vars = Goal(id: 's2', title: 'Variables', parentId: 'r', order: 2);
final _stamp = DateTime.utc(2026, 9, 23, 10);

Widget _card(Map<String, Progress> progressById) => localizedTestApp(
  Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: LeerpadCard(
        index: 1,
        root: _root,
        children: [_print, _vars],
        progressById: progressById,
        isActive: true,
        onContinue: () {},
      ),
    ),
  ),
);

Finder _chip(String goalId) =>
    find.byWidgetPredicate((w) => w is LeerpadChildChip && w.goal.id == goalId);

Finder _in(Finder chip, Finder what) =>
    find.descendant(of: chip, matching: what);

final _check = find.byIcon(Icons.check_circle);

void main() {
  testWidgets('a subgoal advanced past with a stuck LO shows its check mark '
      'on a bar short of 100%, and the root is completed on the stamps, not '
      'on its average', (tester) async {
    await tester.pumpWidget(
      _card({
        's1': Progress(goalID: 's1', progress: 1.0, advancedAt: _stamp),
        's2': Progress(goalID: 's2', progress: 0.5, advancedAt: _stamp),
      }),
    );
    await tester.pumpAndSettle();

    expect(_in(_chip('s2'), find.text('50%')), findsOneWidget);
    expect(_in(_chip('s2'), _check), findsOneWidget);
    expect(_in(_chip('s1'), find.text('100%')), findsOneWidget);
    expect(_in(_chip('s1'), _check), findsOneWidget);
    // Both required subgoals were advanced past: the root reads completed
    // even though its average bar is 75%.
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('75%'), findsNothing);
  });

  testWidgets('a half-mastered subgoal without the stamp is open, a '
      'pre-stamp full bar still counts as finished, and the root shows its '
      'average', (tester) async {
    await tester.pumpWidget(
      _card({
        's1': Progress(goalID: 's1', progress: 1.0),
        's2': Progress(goalID: 's2', progress: 0.5),
      }),
    );
    await tester.pumpAndSettle();

    expect(_in(_chip('s2'), find.text('50%')), findsOneWidget);
    expect(_in(_chip('s2'), _check), findsNothing);
    expect(_in(_chip('s1'), _check), findsOneWidget);
    expect(find.text('completed'), findsNothing);
    expect(find.text('75%'), findsOneWidget);
  });
}
