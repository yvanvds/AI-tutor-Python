// End-to-end (#89): the Students page's Progress column must describe the
// student's *active* root goal honestly — averaging over every non-optional
// subgoal defined under that root, with unstarted subgoals counting as 0.
// Before the fix the column averaged only the subgoals that had a progress
// record, so finishing 1 of 3 read as 100%.
//
// Driven against the real app — shell navigation, the real AccountsPage over
// the harness's in-memory Cosmos, real 5 s polling streams.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/students_progress_column.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

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

  testWidgets('Students page: Progress column averages over all non-optional '
      'subgoals of the active root, counting unstarted ones as 0', (
    tester,
  ) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    // Grow the seeded curriculum: root r1 ends up with three non-optional
    // subgoals (s1, s2, s3) plus an optional one; a second root r2 gets two.
    final goals = harness.cosmos['goals'];
    goals.upsert(
      goalDoc(id: 's3', title: 'Loops', parentId: 'r1', order: 3000),
    );
    goals.upsert(
      goalDoc(
        id: 's-opt',
        title: 'Extra credit',
        parentId: 'r1',
        order: 4000,
        optional: true,
      ),
    );
    goals.upsert(goalDoc(id: 'r2', title: 'Functions', order: 2000));
    goals.upsert(goalDoc(id: 't1', title: 'Defining', parentId: 'r2'));
    goals.upsert(
      goalDoc(id: 't2', title: 'Calling', parentId: 'r2', order: 2000),
    );

    final accounts = harness.cosmos['accounts'];
    accounts.upsert(_studentDoc('it-lena', 'Lena'));
    accounts.upsert(_studentDoc('it-lore', 'Lore'));
    accounts.upsert(_studentDoc('it-noor', 'Noor'));

    // Lena finished 1 of r1's 3 subgoals (plus the optional one, which must
    // not count) → 33%, where the old average-of-records said 100%.
    final progress = harness.cosmos['progress'];
    progress.upsert(
      _progressDoc('it-lena', 's1', 1.0, at: '2026-05-03T10:00:00Z'),
    );
    progress.upsert(
      _progressDoc('it-lena', 's-opt', 1.0, at: '2026-05-03T09:00:00Z'),
    );
    // Lore has records on 2 of 3 (1.0 and 0.5) → 50%, not 75%.
    progress.upsert(
      _progressDoc('it-lore', 's1', 1.0, at: '2026-05-03T10:00:00Z'),
    );
    progress.upsert(
      _progressDoc('it-lore', 's2', 0.5, at: '2026-05-03T11:00:00Z'),
    );
    // Noor moved on to root r2 (t1 at 0.5 of {t1, t2} → 25%); her finished
    // r1 subgoal belongs to a root she is no longer on, so it neither
    // inflates the number (old code: (100% + 50%) / 2 roots = 75%) nor
    // shows up as the current goal.
    progress.upsert(
      _progressDoc('it-noor', 's1', 1.0, at: '2026-05-01T10:00:00Z'),
    );
    progress.upsert(
      _progressDoc('it-noor', 't1', 0.5, at: '2026-05-03T10:00:00Z'),
    );

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    // The 5 s polls have to pick up the three students and their progress;
    // Lena's 33% only renders once both streams delivered.
    await pumpUntilFound(tester, find.text('33%'));

    expect(find.text('33%'), findsOneWidget); // Lena
    expect(find.text('50%'), findsOneWidget); // Lore
    expect(find.text('25%'), findsOneWidget); // Noor
    expect(find.text('0%'), findsOneWidget); // the teacher's own row
    // Nobody reads as done, and the old inflated numbers are gone.
    expect(find.text('100%'), findsNothing);
    expect(find.text('75%'), findsNothing);

    // The column stays consistent with its neighbour: Noor's current goal is
    // r2 ("Functions"), the root her 25% describes.
    expect(find.text('Functions'), findsOneWidget);

    await harness.dispose(tester);
  });
}
