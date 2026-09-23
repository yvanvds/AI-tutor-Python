// End-to-end (#151): the other end of the report chain — the student reads
// their own released reports.
//
// `grade_proposal.dart` drives the teacher's half up to "Release", and stops
// where the frozen docs land in the `reports` container. This flow starts
// there: Sam opens "My reports" in the real sidebar and reads what came out.
//
// What only a full-app run can pin:
//   - the section is really wired into the shell — sidebar entry, routing,
//     top bar — for a student, whose shell has no teacher sections at all;
//   - the real `PublishedReportService` really reads Sam's own partition of
//     the real container through the app's polling stream: a classmate's
//     released report is not on the page;
//   - the *order* on the real page in the real font: the grade and the
//     reasoning above the fold, the breakdown folded away below them. That
//     ordering is the issue, and a widget test cannot see the page's real
//     layout;
//   - the page holds still through a Cosmos poll (5 s) with the breakdown
//     open, and survives leaving the tab and coming back — `pollingStream`
//     is single-subscription, so a second listen would throw;
//   - who gets the entry: a teacher does not. They are never graded, so the
//     page would be empty for them next to the class-wide "Reports" they
//     actually want — which a real run is the only thing that shows. (The
//     rail no longer leans on that: it fits, and scrolls, on its own since
//     #156 — see sidebar_rail.dart.)
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/my_reports_tab.dart -d windows

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/my_reports/my_reports_page.dart';
import 'package:ai_tutor_python/features/reports/reports_page.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/services/grading/published_report.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// A published report exactly as `PublishedReportService.publish` leaves it.
Map<String, dynamic> _reportDoc({
  String uid = kStudentUid,
  required String milestoneId,
  required String title,
  required DateTime dueAt,
  required int grade,
  required String justification,
  String note = '',
  DateTime? updatedAt,
}) {
  final publishedAt = dueAt.toUtc().add(const Duration(days: 5));
  return PublishedReport(
    uid: uid,
    milestoneId: milestoneId,
    milestoneTitle: title,
    dueAt: dueAt,
    grade: grade,
    justification: justification,
    note: note,
    computedAt: dueAt.toUtc().subtract(const Duration(days: 1)),
    publishedAt: publishedAt,
    updatedAt: updatedAt ?? publishedAt,
    formulaVersion: '1.0.7',
    mEnd: 90,
    k: 1,
    u: 0.5,
    d: 0.5,
    coreCounted: 2,
    coreTotal: 2,
    extensionMastered: 2,
    extensionTotal: 4,
    expectedDifficulty: QuestionDifficulty.hard,
  ).toMap();
}

const String kFirstPeriod = 'Sam kende de kern van periode 1 volledig.';
const String kSecondPeriod = 'Sam toonde print() op moeilijk niveau aan.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a student reads their released reports, newest first, with the '
      'breakdown folded away under the grade and the reasoning', (
    tester,
  ) async {
    final harness = AppHarness(
      extraDocs: {
        'reports': [
          _reportDoc(
            milestoneId: 'm1',
            title: 'Rapport 1',
            dueAt: DateTime(2026, 10, 15),
            grade: 84,
            justification: kFirstPeriod,
          ),
          _reportDoc(
            milestoneId: 'm2',
            title: 'Rapport 2',
            dueAt: DateTime(2026, 12, 20),
            grade: 91,
            justification: kSecondPeriod,
            note: 'Ziek in week 3.',
          ),
          // A classmate's released report, in the same container.
          _reportDoc(
            uid: 'it-classmate',
            milestoneId: 'm2',
            title: 'Van een klasgenoot',
            dueAt: DateTime(2026, 12, 20),
            grade: 55,
            justification: 'Niet voor Sam.',
          ),
        ],
      },
    );
    await harness.boot(tester);
    expect(find.text('Hi Sam,'), findsOneWidget);
    // A student's shell has the student sections only: the teacher's
    // class-wide run is a different entry, and Sam has none of it.
    expect(find.byTooltip('Reports'), findsNothing);

    await tester.tap(find.byTooltip('My reports'));
    await pumpUntilFound(tester, find.byType(MyReportsPage));
    expect(find.byType(ReportsPage), findsNothing);
    await pumpUntilFound(tester, find.byKey(const Key('my-reports-card-m2')));
    await pumpUntilFound(tester, find.byKey(const Key('my-reports-card-m1')));

    // One partition: the classmate's report is in the container and not on
    // the page.
    expect(find.text('Van een klasgenoot'), findsNothing);
    expect(find.text('Niet voor Sam.'), findsNothing);

    // Newest report moment first.
    expect(
      tester.getTopLeft(find.byKey(const Key('my-reports-card-m2'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('my-reports-card-m1'))).dy,
      ),
    );

    // The grade, then the reasoning, then — folded away — the arithmetic.
    expect(
      tester.widget<Text>(find.byKey(const Key('my-reports-grade-m2'))).data,
      '91',
    );
    expect(find.text(kSecondPeriod), findsOneWidget);
    expect(
      find.text('Note from your teacher: Ziek in week 3.'),
      findsOneWidget,
    );
    expect(find.textContaining('Computed on'), findsWidgets);
    expect(find.byKey(const Key('my-reports-breakdown-m2')), findsNothing);
    expect(find.textContaining('Mastery score M'), findsNothing);

    final toggle = find.byKey(const Key('my-reports-breakdown-toggle-m2'));
    expect(
      tester.getTopLeft(find.byKey(const Key('my-reports-grade-m2'))).dy,
      lessThan(tester.getTopLeft(toggle).dy),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('my-reports-justification-m2')))
          .dy,
      lessThan(tester.getTopLeft(toggle).dy),
    );

    await tester.tap(toggle);
    await pumpUntilFound(
      tester,
      find.byKey(const Key('my-reports-breakdown-m2')),
    );
    expect(
      find.text('Mastery score M = 90.0 (the proposed grade is M, rounded)'),
      findsOneWidget,
    );
    // P = M since v1.0.16 (#191): no period-start score, no growth term.
    expect(find.textContaining('Growth score'), findsNothing);
    expect(find.textContaining('start of the period'), findsNothing);
    expect(
      find.text(
        'k = 1.00 (core) · u = 0.50 (extension) · d = 0.50 (shown at hard)',
      ),
      findsOneWidget,
    );
    expect(find.text('Core at the expected level: 2 / 2'), findsOneWidget);
    expect(find.text('Extension mastered: 2 / 4'), findsOneWidget);
    expect(find.text('Expected level for the core: hard'), findsOneWidget);
    // The two teacher-side numbers behind d are not in the published doc, so
    // the student page never claims them.
    expect(find.textContaining('Demonstrated at hard'), findsNothing);

    // Hold still through a Cosmos poll with the breakdown open (#128): the
    // 5 s tick re-emits the same reports and must not fold the page back up
    // or listen to the stream a second time.
    final deadline = DateTime.now().add(
      kCosmosPollInterval + const Duration(seconds: 1),
    );
    var blankFrames = 0;
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const Key('my-reports-breakdown-m2')).evaluate().isEmpty) {
        blankFrames++;
      }
    }
    expect(
      blankFrames,
      0,
      reason: 'the open breakdown was missing from $blankFrames frame(s)',
    );
    expect(tester.takeException(), isNull);

    // Away and back: a fresh page, a fresh subscription, the same reports.
    await tester.tap(find.byTooltip('Session'));
    await pumpUntilFound(tester, find.byType(SessionView));
    expect(find.byType(MyReportsPage), findsNothing);

    await tester.tap(find.byTooltip('My reports'));
    await pumpUntilFound(tester, find.byType(MyReportsPage));
    await pumpUntilFound(tester, find.byKey(const Key('my-reports-card-m2')));
    expect(tester.takeException(), isNull);
    // Collapsed again, as every first look at the page is.
    expect(find.byKey(const Key('my-reports-breakdown-m2')), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('nothing released yet is an empty state, and a release while '
      'the tab is open arrives on the poll', (tester) async {
    final harness = AppHarness();
    await harness.boot(tester);

    await tester.tap(find.byTooltip('My reports'));
    await pumpUntilFound(tester, find.byType(MyReportsPage));
    await pumpUntilFound(tester, find.byKey(const Key('my-reports-empty')));
    expect(find.byKey(const Key('my-reports-card-m1')), findsNothing);
    expect(tester.takeException(), isNull);

    // The teacher presses Release in the next room.
    harness.cosmos['reports'].upsert(
      _reportDoc(
        milestoneId: 'm1',
        title: 'Rapport 1',
        dueAt: DateTime(2026, 10, 15),
        grade: 84,
        justification: kFirstPeriod,
      ),
    );
    await pumpUntilFound(tester, find.byKey(const Key('my-reports-card-m1')));
    expect(find.byKey(const Key('my-reports-empty')), findsNothing);
    expect(find.text(kFirstPeriod), findsOneWidget);
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });

  testWidgets('a teacher gets the class-wide Reports instead, and their rail '
      'still fits the runner window', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    expect(find.text('Hi Yvan,'), findsOneWidget);

    // A teacher is never graded, so "My reports" would be an empty page next
    // to the class-wide run they actually want. The rail's own fit is no
    // longer part of that argument — it scrolls and keeps an entry of slack
    // since #156, which sidebar_rail.dart pins.
    expect(find.byTooltip('My reports'), findsNothing);
    expect(
      tester.getTopLeft(find.byTooltip('Reports')).dy,
      greaterThan(tester.getTopLeft(find.text('TEACHER')).dy),
    );
    expect(find.byType(MyReportsPage), findsNothing);

    await harness.dispose(tester);
  });
}
