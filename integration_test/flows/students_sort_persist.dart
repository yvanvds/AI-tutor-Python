// End-to-end (#92): the sort a teacher picks on the Students table survives
// leaving the page. Before this, the chosen column + direction lived only in
// the page's widget state (#87), so navigating to another section and back
// reset the table to storage order. The choice is now stored per device (as
// the StudentsSortKey NAME — #91's select column already shifted every
// column index by one, which a stored index would not have survived) and
// restored in the page's initState — the same code path an app restart
// takes.
//
// Driven against the real app: real shell navigation unmounts and remounts
// the real AccountsPage, real 5 s polling streams, prefs pinned in-memory
// by the harness.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/students_sort_persist.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

Map<String, dynamic> _studentDoc(String uid, String first, {required int n}) {
  final at = '2026-05-02T10:${n.toString().padLeft(2, '0')}:00Z';
  return {
    'id': uid,
    'uid': uid,
    'email': '$uid@example.com',
    'firstName': first,
    'lastName': 'Student',
    'targetGoal': '',
    'mayUseGlobalKey': true,
    // Distinct createdAt per student: the accounts stream returns docs
    // newest-first, so the unsorted table order is REVERSE alphabetical —
    // the restored-sort assertions below cannot pass by accident.
    'createdAt': at,
    'updatedAt': at,
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Students page: the chosen sort survives navigating away and '
      'back — the remounted page restores column and direction from local '
      'prefs', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    // Three students (all lastName "Student", so the name sort falls
    // through to first names) plus the teacher ("Yvan Teacher", whose last
    // name sorts after every "Student").
    final accounts = harness.cosmos['accounts'];
    for (final (i, f) in ['Anna', 'Ben', 'Cara'].indexed) {
      accounts.upsert(_studentDoc('it-${f.toLowerCase()}', f, n: i));
    }

    double dy(String email) => tester.getTopLeft(find.text(email)).dy;

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Showing 1–4 of 4'));

    // Storage order (createdAt newest-first) shows Cara before Anna.
    expect(dy('it-cara@example.com'), lessThan(dy('it-anna@example.com')));

    // Sort by NAME, then click again for DESCENDING — both the column and
    // the non-default direction have to make it back after the round trip.
    await tester.tap(find.text('NAME'));
    await tester.pump();
    await tester.tap(find.text('NAME'));
    await tester.pump();
    expect(dy('yvan@example.com'), lessThan(dy('it-cara@example.com')));
    expect(dy('it-cara@example.com'), lessThan(dy('it-ben@example.com')));
    expect(dy('it-ben@example.com'), lessThan(dy('it-anna@example.com')));

    // Leave the page: the shell swaps the section body, so AccountsPage is
    // unmounted and its widget state — where the sort used to live — dies.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    expect(find.byType(AccountsPage), findsNothing);

    // Back to Students: a fresh AccountsPage runs initState again and
    // restores the stored choice (async, like on a cold app start).
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Showing 1–4 of 4'));
    await pumpUntil(
      tester,
      () =>
          find.text('yvan@example.com').evaluate().isNotEmpty &&
          dy('yvan@example.com') < dy('it-cara@example.com'),
      reason: 'remounted page should restore the NAME-descending sort',
    );
    expect(dy('it-cara@example.com'), lessThan(dy('it-ben@example.com')));
    expect(dy('it-ben@example.com'), lessThan(dy('it-anna@example.com')));

    // The restored direction is live header state, not a frozen row order:
    // one more click on NAME toggles back to ascending.
    await tester.tap(find.text('NAME'));
    await tester.pump();
    expect(dy('it-anna@example.com'), lessThan(dy('it-ben@example.com')));
    expect(dy('it-ben@example.com'), lessThan(dy('yvan@example.com')));

    await harness.dispose(tester);
  });
}
