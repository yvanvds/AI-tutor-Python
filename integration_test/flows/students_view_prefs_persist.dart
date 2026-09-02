// End-to-end (#95): the rows-per-page and class filter a teacher picks on
// the Students table survive leaving the page, the same way the sort does
// since #92. Before this, both lived only in the page's widget state, so
// navigating to another section and back reset the table to 25 rows and
// "All classes". The choices are now stored per device (as the page-size
// NUMBER and the class-filter STRING — never a dropdown item index) and
// restored in the page's initState — the same code path an app restart
// takes.
//
// The second leg drives the stale-value fallback: a stored class whose last
// members were reassigned no longer exists next session, and the remounted
// page must fall back to "All" via its in-build normalization instead of
// handing DropdownButton a value with no matching item (an assertion crash).
//
// Driven against the real app: real shell navigation unmounts and remounts
// the real AccountsPage, real 5 s polling streams, prefs pinned in-memory
// by the harness. Assertions are on the "Showing X–Y of Z" counts — row
// counts, never pixel positions.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/students_view_prefs_persist.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
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

  testWidgets('Students page: rows-per-page and class filter survive '
      'navigating away and back, and a stored class that disappeared falls '
      'back to All', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    // Twelve students (13 accounts with the teacher) so a 10-per-page limit
    // is visible in the pagination counts; three of them share class 5A.
    final accounts = harness.cosmos['accounts'];
    final inClassA = ['Anna', 'Ben', 'Cara'];
    for (final (i, f) in [
      ...inClassA,
      'Dave',
      'Eli',
      'Finn',
      'Gus',
      'Hana',
      'Iris',
      'Jo',
      'Kim',
      'Liv',
    ].indexed) {
      accounts.upsert(
        _studentDoc(
          'it-${f.toLowerCase()}',
          f,
          className: i < inClassA.length ? '5A' : null,
        ),
      );
    }

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    // Defaults: 25 per page, all classes — one page of 13.
    await pumpUntilFound(tester, find.text('Showing 1–13 of 13'));

    // Pick 10 per page: the counts now describe a first page of 10.
    await tester.tap(find.byKey(const Key('rows-per-page')));
    await pumpUntilFound(tester, find.text('10 / page'));
    await tester.tap(find.text('10 / page').last);
    await pumpUntilFound(tester, find.text('Showing 1–10 of 13'));

    // Filter to 5A: only the three tagged students.
    await tester.tap(find.byKey(const Key('class-filter')));
    await pumpUntilFound(tester, find.text('No class'));
    await tester.tap(find.text('5A').last);
    await pumpUntilFound(tester, find.text('Showing 1–3 of 3'));

    // Leave the page: the shell swaps the section body, so AccountsPage is
    // unmounted and its widget state — where both choices used to live —
    // dies.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    expect(find.byType(AccountsPage), findsNothing);

    // Back to Students: a fresh AccountsPage runs initState again and
    // restores the stored class filter (async, like on a cold app start).
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(
      tester,
      find.text('Showing 1–3 of 3'),
      timeout: const Duration(seconds: 20),
    );

    // Away again — and while the page is gone, class 5A ceases to exist:
    // every member is reassigned to "no class" (the docs stay, so it is
    // still 13 accounts).
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    for (final f in inClassA) {
      accounts.upsert(_studentDoc('it-${f.toLowerCase()}', f));
    }

    // Back once more: the stored filter still says 5A, but that class no
    // longer exists, so the page falls back to "All" — and the 10-per-page
    // choice must ALSO have been restored, which is exactly what
    // "1–10 of 13" (rather than the default's "1–13 of 13") proves.
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(
      tester,
      find.text('Showing 1–10 of 13'),
      timeout: const Duration(seconds: 20),
    );

    // The fallback is live dropdown state, not a crashed frame: the menu
    // opens again, and the dead class is gone from its options.
    await tester.tap(find.byKey(const Key('class-filter')));
    await pumpUntilFound(tester, find.text('No class'));
    expect(find.text('5A'), findsNothing);
    await tester.tap(find.text('All classes').last);
    await pumpUntilGone(tester, find.text('No class'));
    expect(find.text('Showing 1–10 of 13'), findsOneWidget);

    await harness.dispose(tester);
  });
}
