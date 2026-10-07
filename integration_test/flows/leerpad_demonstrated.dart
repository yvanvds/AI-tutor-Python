// End-to-end (#243): on the learning path a finished goal shows its subgoal
// tiles too, each tile says how many of its learning objectives are
// demonstrated — the mastery stamp the grade reads, not the cached bar —
// and opens the list of those objectives, each demonstrated or not yet.
//
// Sam finished "Basics" before #161: both subgoal docs still say 1.0, but
// only "Assign a value" carries the stamp in "Variables"; "Convert to a
// number" stands high on the belief without ever having been stamped, the
// way the grade does not count it either. "Conditions" is the goal in
// progress. The tiles of the finished goal read "1 of 1" and "1 of 2
// demonstrated", the bar of "Variables" stands half full, and the list of
// "Variables" says which one is open — with nothing to press. The statement
// with an English translation shows in English, the other in Dutch.
// Nederlands says it all in Dutch. Opening the Leerpad and the list writes
// nothing: no belief, no stamp, no progress doc.
//
// Real app, real navigation, real Leerpad, real ProgressService,
// LoBeliefsService and TranslationService over the (in-memory) Cosmos
// containers. No model: nothing here asks one.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/leerpad_demonstrated.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

const String kAssign = 'Je kan een waarde aan een naam geven.';
const String kAssignEn = 'You can give a value a name.';
const String kConvert = 'Je kan tekst omzetten naar een getal.';

/// "Variables" with two LOs in Dutch, and a second goal, "Conditions",
/// with one subgoal.
List<Map<String, dynamic>> curriculum() => [
  goalDoc(
    id: 's2',
    title: 'Variables',
    parentId: 'r1',
    order: 2000,
    objectives: [objective('lo-var', kAssign), objective('lo-cast', kConvert)],
  ),
  goalDoc(id: 'r2', title: 'Conditions', order: 2000),
  goalDoc(
    id: 's3',
    title: 'Comparisons',
    parentId: 'r2',
    order: 1000,
    objectives: [objective('lo-cmp', 'Je kan twee getallen vergelijken.')],
  ),
];

/// A subgoal doc as the conductor wrote it before #161: finished as 1.0,
/// whatever was mastered.
Map<String, dynamic> progressDoc(String goalId, double value, String at) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'progress': value,
  'updatedAt': at,
  'lastSessionAt': at,
};

Map<String, dynamic> belief(
  String subgoalId,
  String loId, {
  required double alpha,
  required double beta,
  bool stamped = false,
}) => {
  'id': '${kStudentUid}_${subgoalId}_$loId',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': subgoalId,
  'loId': loId,
  'alpha': alpha,
  'beta': beta,
  'lastUpdatedAt': '2026-09-15T10:00:00.000Z',
  'lastQuestionType': 'completeCodeQuestion',
  'lastPositiveAtCalibratedAt': '2026-09-15T10:00:00.000Z',
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
  if (stamped) 'firstMasteredAt': '2026-09-15T10:00:00.000Z',
};

/// The English statement of `lo-var`, as `translations` stores it: its own
/// doc per LO, made from the Dutch statement as seeded.
Map<String, dynamic> englishAssign() => {
  'id': 'objective_s2.lo-var',
  'language': 'en',
  'kind': 'objective',
  'refId': 's2.lo-var',
  'statement': kAssignEn,
  // `objectiveSourceHash` of the seeded statement — translationSourceHash
  // ('', kAssign) — as the Python tooling computes it.
  'sourceHash':
      'b9279aab7cdf1d5fc4666bac4bbcb8a7a8fbb6fce30f4919453a800ed342b350',
  'updatedAt': '2026-10-07T08:00:00.000Z',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder card(String rootId) =>
      find.byWidgetPredicate((w) => w is LeerpadCard && w.root.id == rootId);
  Finder inCard(String rootId, Finder what) =>
      find.descendant(of: card(rootId), matching: what);
  Finder chip(String goalId) => find.byWidgetPredicate(
    (w) => w is LeerpadChildChip && w.goal.id == goalId,
  );
  Finder inChip(String goalId, Finder what) =>
      find.descendant(of: chip(goalId), matching: what);

  /// The status line under the statement [statement] in the open list: in
  /// the row nearest to the statement, not anywhere in the shell's own row.
  Finder statusOf(String statement, String status) => find.descendant(
    of: find
        .ancestor(of: find.text(statement), matching: find.byType(Row))
        .first,
    matching: find.text(status),
  );

  double bar(WidgetTester tester, String goalId) => tester
      .widget<FractionallySizedBox>(
        inChip(goalId, find.byType(FractionallySizedBox)),
      )
      .widthFactor!;

  testWidgets('a finished goal shows its subgoals with how many learning '
      'objectives are demonstrated, as the grade counts them, and a subgoal '
      'opens which ones are — in English and in Dutch, writing nothing', (
    tester,
  ) async {
    final harness = AppHarness(
      extraDocs: {
        'goals': curriculum(),
        'progress': [
          progressDoc('s1', 1.0, '2026-09-10T10:00:00.000Z'),
          progressDoc('s2', 1.0, '2026-09-15T10:00:00.000Z'),
          progressDoc('s3', 0.0, '2026-10-01T10:00:00.000Z'),
        ],
        'lo_beliefs': [
          belief('s1', 'lo-print', alpha: 5, beta: 1, stamped: true),
          belief('s2', 'lo-var', alpha: 5, beta: 1, stamped: true),
          // μ 0,86 on evidence 7 with the ratchet set: mastered by the
          // belief, never stamped — not demonstrated, as for the grade.
          belief('s2', 'lo-cast', alpha: 6, beta: 1),
        ],
        'translations': [englishAssign()],
      },
    );
    await harness.boot(tester);
    String snapshot(String container) =>
        jsonEncode(harness.cosmos[container].docs);
    final beliefsBefore = snapshot('lo_beliefs');
    final progressBefore = snapshot('progress');

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, card('r2'));

    // "Basics" is finished and not the goal in progress: no "Continue",
    // but its subgoal tiles are there.
    expect(inCard('r1', find.text('completed')), findsOneWidget);
    expect(inCard('r1', find.text('Continue')), findsNothing);
    expect(inCard('r2', find.text('Continue')), findsOneWidget);
    await pumpUntilFound(
      tester,
      inChip('s2', find.text('1 of 2 demonstrated')),
    );
    expect(inCard('r1', chip('s1')), findsOneWidget);
    expect(inChip('s1', find.text('1 of 1 demonstrated')), findsOneWidget);
    expect(inChip('s3', find.text('0 of 1 demonstrated')), findsOneWidget);
    // The bar of "Variables" counts the stamps: half, where the cache
    // still says full. Its check mark stays: it was finished.
    expect(bar(tester, 's2'), closeTo(0.5, 1e-9));
    expect(bar(tester, 's1'), closeTo(1.0, 1e-9));
    expect(inChip('s2', find.byIcon(Icons.check_circle)), findsOneWidget);

    // "Variables" opens what it asks, and which one is still open.
    await tester.tap(chip('s2'));
    await pumpUntilFound(tester, find.text(kAssignEn));
    expect(statusOf(kAssignEn, 'demonstrated'), findsOneWidget);
    expect(find.text(kConvert), findsOneWidget);
    expect(statusOf(kConvert, 'not yet demonstrated'), findsOneWidget);
    expect(find.text(kAssign), findsNothing);
    // Nothing to press in the finished goal: no advice, no retry.
    for (final type in [ButtonStyleButton, IconButton, InkWell]) {
      expect(inCard('r1', find.byType(type)), findsNothing);
    }

    // Nederlands: the same, in Dutch.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));
    await tester.tap(find.byTooltip('Leerpad'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, inChip('s2', find.text('1 van 2 aangetoond')));
    expect(inCard('r1', find.text('voltooid')), findsOneWidget);
    await tester.tap(chip('s2'));
    await pumpUntilFound(tester, find.text(kAssign));
    expect(statusOf(kAssign, 'aangetoond'), findsOneWidget);
    expect(statusOf(kConvert, 'nog niet aangetoond'), findsOneWidget);
    expect(find.text(kAssignEn), findsNothing);

    // Display only: nothing was written.
    expect(snapshot('lo_beliefs'), beliefsBefore);
    expect(snapshot('progress'), progressBefore);

    await harness.dispose(tester);
  });
}
