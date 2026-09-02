// End-to-end (#91): the teacher assigns a class to MANY students in one
// action instead of one dialog per row. Two entry points are driven:
//
//  1. per-row checkboxes — check two students, "Assign class", one dialog,
//     both account docs are patched;
//  2. the header select-all checkbox — scoped to the FULL filtered set, so
//     "filter to a class, select all, assign" retags every match at once.
//
// The bulk action reuses AccountService.setClassName (one patch per
// account) and leaves the filter → search → sort → paginate pipeline
// untouched; the flow checks that the class filter's options and counts
// follow the bulk writes.
//
// Driven against the real app — shell navigation, the real AccountsPage over
// the harness's in-memory Cosmos, real 5 s polling streams.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/students_bulk_class.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

Map<String, dynamic> _studentDoc(
  String uid,
  String first, {
  String? className,
}) => {
  'id': uid,
  'uid': uid,
  'email': '$uid@example.com',
  'firstName': first,
  'lastName': 'Student',
  'targetGoal': '',
  'mayUseGlobalKey': true,
  'createdAt': '2026-05-02T10:00:00Z',
  'updatedAt': '2026-05-02T10:00:00Z',
  if (className != null) 'className': className,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Students page: bulk class assignment via row checkboxes and '
      'the filter-scoped select-all', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    final accounts = harness.cosmos['accounts'];
    accounts.upsert(_studentDoc('it-anna', 'Anna', className: '5A'));
    accounts.upsert(_studentDoc('it-ben', 'Ben', className: '5A'));
    accounts.upsert(_studentDoc('it-cara', 'Cara', className: '5B'));
    accounts.upsert(_studentDoc('it-dave', 'Dave'));

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    // The 5 s account poll has to pick up the four seeded students.
    await pumpUntilFound(tester, find.text('it-dave@example.com'));
    expect(find.text('Showing 1–5 of 5'), findsOneWidget);

    // No selection → no bulk bar.
    expect(find.byKey(const Key('bulk-assign-class')), findsNothing);

    // 1. Row checkboxes: check Cara and Dave, assign both to 6C in ONE
    // dialog.
    await tester.tap(find.byKey(const Key('select-student-it-cara')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('select-student-it-dave')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bulk-assign-class')));
    await pumpUntilFound(
      tester,
      find.text('Class name (leave empty to clear)'),
    );
    await tester.enterText(find.byType(TextField).last, '6C');
    await tester.tap(find.text('Save'));
    await pumpUntil(
      tester,
      () =>
          accounts['it-cara']?['className'] == '6C' &&
          accounts['it-dave']?['className'] == '6C',
      reason: 'the bulk assignment should patch every selected Cosmos doc',
    );
    // Untouched rows keep their class.
    expect(accounts['it-anna']?['className'], '5A');
    expect(accounts['it-ben']?['className'], '5A');
    // The selection clears after a successful bulk action.
    await pumpUntilGone(tester, find.text('2 selected'));

    // Wait for the account poll to reflect both writes in the table (two 6C
    // class badges) BEFORE opening the dropdown: an already-open menu keeps
    // the option list it was built with.
    await pumpUntil(
      tester,
      () => find.text('6C').evaluate().length >= 2,
      reason: 'both retagged rows should show their new class badge',
    );

    // The new class is a filter option and narrows to exactly the two.
    await tester.tap(find.byKey(const Key('class-filter')));
    await pumpUntilFound(tester, find.text('No class'));
    await tester.tap(find.text('6C').last);
    await pumpUntilFound(tester, find.text('Showing 1–2 of 2'));
    expect(find.text('it-cara@example.com'), findsOneWidget);
    expect(find.text('it-dave@example.com'), findsOneWidget);
    expect(find.text('it-anna@example.com'), findsNothing);

    // 2. Select-all is scoped to the current filtered set: with the 6C
    // filter active it selects Cara and Dave only — not Anna, Ben or the
    // teacher — and the assign retags exactly those two.
    await tester.tap(find.byKey(const Key('select-all-students')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bulk-assign-class')));
    await pumpUntilFound(
      tester,
      find.text('Class name (leave empty to clear)'),
    );
    await tester.enterText(find.byType(TextField).last, '7A');
    await tester.tap(find.text('Save'));
    await pumpUntil(
      tester,
      () =>
          accounts['it-cara']?['className'] == '7A' &&
          accounts['it-dave']?['className'] == '7A',
      reason: 'select-all should assign the class to every filtered student',
    );
    expect(accounts['it-anna']?['className'], '5A');
    expect(accounts['it-ben']?['className'], '5A');
    expect(accounts['it-teacher']?['className'] ?? '', isNot('7A'));

    // 6C no longer exists, so once the poll catches up the stale filter
    // value falls back to "All classes" and the counts follow.
    await pumpUntilFound(tester, find.text('Showing 1–5 of 5'));

    await harness.dispose(tester);
  });
}
