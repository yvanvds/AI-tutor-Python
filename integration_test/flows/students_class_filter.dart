// End-to-end (#86): the teacher tags students with a class and filters the
// Students page by it. The class filter is stage 1 of the list pipeline
// (filter → search → paginate), so the flow checks that it composes with the
// free-text search and that the "Showing X–Y of Z" counts always describe
// the filtered set. Assignment itself is driven through the UI: the class
// cell opens a dialog whose save lands on the account doc in Cosmos.
//
// Driven against the real app — shell navigation, the real AccountsPage over
// the harness's in-memory Cosmos, real 5 s polling streams.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/students_class_filter.dart -d windows

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

  testWidgets('Students page: class tags filter the list, compose with '
      'search, and are assignable from the row', (tester) async {
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

    // "All": every account, including the teacher's own — 5 in total.
    expect(find.text('Showing 1–5 of 5'), findsOneWidget);

    // Filter to 5A: only Anna and Ben, and the counts follow.
    await tester.tap(find.byKey(const Key('class-filter')));
    await pumpUntilFound(tester, find.text('No class'));
    await tester.tap(find.text('5A').last);
    await pumpUntilFound(tester, find.text('Showing 1–2 of 2'));
    expect(find.text('it-anna@example.com'), findsOneWidget);
    expect(find.text('it-ben@example.com'), findsOneWidget);
    expect(find.text('it-cara@example.com'), findsNothing);
    expect(find.text('it-dave@example.com'), findsNothing);

    // Search composes on top of the class filter.
    await tester.enterText(find.byType(TextField).first, 'anna');
    await pumpUntilFound(tester, find.text('Showing 1–1 of 1'));
    expect(find.text('it-ben@example.com'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await pumpUntilFound(tester, find.text('Showing 1–2 of 2'));

    // "No class": the untagged student and the teacher stay reachable.
    // (Wait on Dave appearing — he was absent under 5A — rather than on the
    // count, which reads "1–2 of 2" in both states.)
    await tester.tap(find.byKey(const Key('class-filter')));
    await pumpUntilFound(tester, find.text('No class'));
    await tester.tap(find.text('No class').last);
    await pumpUntilFound(tester, find.text('it-dave@example.com'));
    expect(find.text('Showing 1–2 of 2'), findsOneWidget);
    expect(find.text('yvan@example.com'), findsOneWidget);
    expect(find.text('it-anna@example.com'), findsNothing);

    // Assign Dave to a brand-new class through the row's class cell.
    await tester.tap(find.byKey(const Key('class-cell-it-dave')));
    await pumpUntilFound(tester, find.text('Assign class'));
    await tester.enterText(find.byType(TextField).last, '6C');
    await tester.tap(find.text('Save'));
    await pumpUntil(
      tester,
      () => accounts['it-dave']?['className'] == '6C',
      reason: 'the class assignment should land on the Cosmos doc',
    );
    // Wait for the account poll to reflect the write in the UI (Dave leaves
    // the "No class" set) BEFORE opening the dropdown: an already-open menu
    // keeps the option list it was built with.
    await pumpUntilGone(tester, find.text('it-dave@example.com'));

    // The new class shows up as a filter option and narrows to Dave alone.
    await tester.tap(find.byKey(const Key('class-filter')));
    await pumpUntilFound(tester, find.text('6C'));
    await tester.tap(find.text('6C').last);
    await pumpUntilFound(tester, find.text('it-dave@example.com'));
    expect(find.text('Showing 1–1 of 1'), findsOneWidget);
    expect(find.text('yvan@example.com'), findsNothing);

    await harness.dispose(tester);
  });
}
