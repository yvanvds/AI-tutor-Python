// End-to-end (#87): the teacher sorts the Students table by clicking column
// headers. Sorting is stage 3 of the list pipeline (class filter → search →
// sort → paginate) and runs on the FULL result set — so the order must hold
// across pages, not just reorder the visible slice — and clicking the same
// header again reverses it. The flow drives the NAME and PROGRESS columns
// and checks composition with search and with pagination.
//
// Driven against the real app — shell navigation, the real AccountsPage over
// the harness's in-memory Cosmos, real 5 s polling streams.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/students_sort.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:flutter/material.dart';
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
    // the name-sort assertions below cannot pass by accident.
    'createdAt': at,
    'updatedAt': at,
  };
}

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

  testWidgets('Students page: clicking a header sorts the whole result set, '
      'clicking again reverses, and the order composes with search and '
      'pagination', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    // Twelve students (all lastName "Student", so the name sort falls
    // through to first names) plus the teacher ("Yvan Teacher", whose last
    // name sorts after every "Student").
    const firsts = [
      'Anna', 'Ben', 'Cara', 'Dave', 'Elin', 'Fien', //
      'Gus', 'Hana', 'Iris', 'Jef', 'Kato', 'Lena',
    ];
    final accounts = harness.cosmos['accounts'];
    for (final (i, f) in firsts.indexed) {
      accounts.upsert(_studentDoc('it-${f.toLowerCase()}', f, n: i));
    }

    // The seeded curriculum's root r1 has two non-optional subgoals (s1,
    // s2): Ben 100%, Anna 50%, Cara 25%, everyone else 0%.
    final progress = harness.cosmos['progress'];
    progress.upsert(
      _progressDoc('it-anna', 's1', 1.0, at: '2026-05-03T10:00:00Z'),
    );
    progress.upsert(
      _progressDoc('it-ben', 's1', 1.0, at: '2026-05-03T10:00:00Z'),
    );
    progress.upsert(
      _progressDoc('it-ben', 's2', 1.0, at: '2026-05-03T11:00:00Z'),
    );
    progress.upsert(
      _progressDoc('it-cara', 's1', 0.5, at: '2026-05-03T10:00:00Z'),
    );

    double dy(String email) => tester.getTopLeft(find.text(email)).dy;

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    // The 5 s polls have to pick up the twelve students and the progress
    // docs (Ben's 100% renders only once both streams delivered).
    await pumpUntilFound(tester, find.text('Showing 1–13 of 13'));
    await pumpUntilFound(tester, find.text('100%'));

    // Storage order (createdAt newest-first) shows Lena before Anna.
    expect(dy('it-lena@example.com'), lessThan(dy('it-anna@example.com')));

    // NAME ascending: last name first, so every Student precedes Teacher.
    await tester.tap(find.text('NAME'));
    await tester.pump();
    expect(dy('it-anna@example.com'), lessThan(dy('it-ben@example.com')));
    expect(dy('it-ben@example.com'), lessThan(dy('it-lena@example.com')));
    expect(dy('it-lena@example.com'), lessThan(dy('yvan@example.com')));

    // Clicking NAME again reverses the whole order.
    await tester.tap(find.text('NAME'));
    await tester.pump();
    expect(dy('yvan@example.com'), lessThan(dy('it-lena@example.com')));
    expect(dy('it-lena@example.com'), lessThan(dy('it-anna@example.com')));

    // Search composes on top of the sort: "na" narrows to Anna, Hana and
    // Lena, still in descending name order.
    await tester.enterText(find.byType(TextField).first, 'na');
    await pumpUntilFound(tester, find.text('Showing 1–3 of 3'));
    expect(dy('it-lena@example.com'), lessThan(dy('it-hana@example.com')));
    expect(dy('it-hana@example.com'), lessThan(dy('it-anna@example.com')));
    await tester.enterText(find.byType(TextField).first, '');
    await pumpUntilFound(tester, find.text('Showing 1–13 of 13'));

    // Shrink the page to 10 rows so the sort has to cross a page boundary.
    await tester.tap(find.byType(DropdownButton<int>));
    await pumpUntilFound(tester, find.text('10 / page'));
    await tester.tap(find.text('10 / page').last);
    await pumpUntilFound(tester, find.text('Showing 1–10 of 13'));

    // PROGRESS ascending: the ten 0% rows fill page 1, pushing Cara (25%),
    // Anna (50%) and Ben (100%) off to page 2 — the sort ordered the full
    // set BEFORE pagination.
    await tester.tap(find.text('PROGRESS'));
    await tester.pump();
    expect(find.text('Showing 1–10 of 13'), findsOneWidget);
    expect(find.text('it-dave@example.com'), findsOneWidget);
    expect(find.text('it-ben@example.com'), findsNothing);
    expect(find.text('it-anna@example.com'), findsNothing);
    expect(find.text('it-cara@example.com'), findsNothing);
    expect(find.text('100%'), findsNothing);

    // PROGRESS descending: Ben, Anna, Cara lead page 1.
    await tester.tap(find.text('PROGRESS'));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    expect(dy('it-ben@example.com'), lessThan(dy('it-anna@example.com')));
    expect(dy('it-anna@example.com'), lessThan(dy('it-cara@example.com')));
    // ...and every 0% row (here Lena's) sits below the three with progress.
    expect(dy('it-cara@example.com'), lessThan(dy('it-lena@example.com')));

    await harness.dispose(tester);
  });
}
