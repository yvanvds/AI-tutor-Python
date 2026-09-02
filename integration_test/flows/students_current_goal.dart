// End-to-end (#88): the Students page's "Current goal" column must show
// *which* subgoal a student is on, not just the shared root — a two-line
// cell (root title, then the active subgoal smaller and fainter), one line
// when the active goal is a root, with long titles ellipsized and the full
// titles in a tooltip.
//
// Driven against the real app — shell navigation, the real AccountsPage over
// the harness's in-memory Cosmos, real 5 s polling streams.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/students_current_goal.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

const String _kLongRootTitle =
    'A very long root goal title that cannot possibly fit inside the '
    'current-goal column without being truncated somewhere';
const String _kLongSubTitle =
    'An equally long subgoal title that also needs the ellipsis to stay '
    'on its single faint line';

Map<String, dynamic> _studentDoc(String uid, String first) => {
  'id': uid,
  'uid': uid,
  'email': '$uid@example.com',
  'firstName': first,
  'lastName': 'Student',
  'targetGoal': '',
  'mayUseGlobalKey': true,
  'createdAt': '2026-05-02T10:00:00Z',
  'updatedAt': '2026-05-02T10:00:00Z',
};

Map<String, dynamic> _progressDoc(
  String uid,
  String goalId,
  double value, {
  required String at,
}) => {
  'id': '${uid}_$goalId',
  'uid': uid,
  'goalId': goalId,
  'progress': value,
  'updatedAt': at,
  'lastSessionAt': at,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Students page: Current goal column shows the active subgoal '
      'beneath the root goal', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    // Add a long-titled root + subgoal next to the seeded r1 ("Basics",
    // subgoals "Print" and "Variables") to exercise the truncation path.
    final goals = harness.cosmos['goals'];
    goals.upsert(goalDoc(id: 'r-long', title: _kLongRootTitle, order: 2000));
    goals.upsert(goalDoc(id: 'u1', title: _kLongSubTitle, parentId: 'r-long'));

    final accounts = harness.cosmos['accounts'];
    accounts.upsert(_studentDoc('it-mira', 'Mira'));
    accounts.upsert(_studentDoc('it-omar', 'Omar'));
    accounts.upsert(_studentDoc('it-lina', 'Lina'));

    final progress = harness.cosmos['progress'];
    // Mira is on subgoal s2 ("Variables") of r1 — two-line cell.
    progress.upsert(
      _progressDoc('it-mira', 's1', 1.0, at: '2026-05-03T10:00:00Z'),
    );
    progress.upsert(
      _progressDoc('it-mira', 's2', 0.5, at: '2026-05-03T11:00:00Z'),
    );
    // Omar only has the derived record on root r1 itself — one line.
    progress.upsert(
      _progressDoc('it-omar', 'r1', 0.25, at: '2026-05-03T10:00:00Z'),
    );
    // Lina is on the long-titled subgoal — both lines must ellipsize
    // instead of blowing up the row (an overflow would fail the test).
    progress.upsert(
      _progressDoc('it-lina', 'u1', 0.5, at: '2026-05-03T10:00:00Z'),
    );

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    // The 5 s polls have to deliver the students and their progress before
    // Mira's subgoal line renders.
    await pumpUntilFound(tester, find.text('Variables'));

    // Mira: root goal on top, active subgoal beneath it, and the subgoal
    // line uses the faint secondary style (like the email cell's second
    // line), not the primary row style.
    expect(find.text('Variables'), findsOneWidget);
    final subLine = tester.widget<Text>(find.text('Variables'));
    expect(subLine.style?.color, AppColors.fgFaint);
    expect(subLine.overflow, TextOverflow.ellipsis);
    // The full titles live in the cell's tooltip.
    expect(find.byTooltip('Basics\nVariables'), findsOneWidget);

    // Omar's active goal *is* the root: one line, no subgoal tooltip line.
    expect(find.byTooltip('Basics'), findsOneWidget);
    // Two students on r1 → the root title renders twice, and Mira's
    // finished "Print" subgoal is not the line shown (most recent wins).
    expect(find.text('Basics'), findsNWidgets(2));
    expect(find.text('Print'), findsNothing);

    // Lina's long titles render (ellipsized — the test would fail on a
    // layout overflow) and the tooltip still carries them in full.
    expect(find.byTooltip('$_kLongRootTitle\n$_kLongSubTitle'), findsOneWidget);

    await harness.dispose(tester);
  });
}
