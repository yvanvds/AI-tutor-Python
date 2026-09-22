// The student's "My reports" page (#151), mounted over the real
// `PublishedReportService` against an in-memory `reports` container.
//
// What has to hold:
//   - a student with nothing released sees an empty state, not an error;
//   - a released report shows the milestone, the grade, *when the formula
//     measured*, the justification and the teacher's note;
//   - the breakdown is **collapsed**: the arithmetic exists but sits below
//     the grade and the reasoning, and only opens when asked. That ordering
//     is the issue, not styling;
//   - the page reads one partition — another student's released report is
//     not on it;
//   - newest report date first;
//   - the page survives a Cosmos poll. `pollingStream` is
//     single-subscription, so an empty state that fills on the next tick
//     must not make the builder listen twice ("Stream has already been
//     listened to").
//
// The same page in the real Windows app, reached through the real sidebar,
// is `integration_test/flows/my_reports_tab.dart`.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/my_reports/my_reports_page.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/grading/published_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

const _sam = AccountIdentity(
  oid: 'u1',
  displayName: 'Sam Student',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  isTeacher: false,
);

class _SignedInSam extends AuthService {
  @override
  AccountIdentity? build() => _sam;
}

/// A published report as `PublishedReportService.publish` leaves it in Cosmos.
Map<String, dynamic> _reportDoc({
  String uid = 'u1',
  String milestoneId = 'm1',
  String title = 'Rapport 1',
  DateTime? dueAt,
  int grade = 84,
  String justification = 'Sam beheerst de kern volledig.',
  String note = '',
  DateTime? publishedAt,
  DateTime? updatedAt,
}) => PublishedReport(
  uid: uid,
  milestoneId: milestoneId,
  milestoneTitle: title,
  dueAt: dueAt ?? DateTime(2026, 10, 15),
  grade: grade,
  justification: justification,
  note: note,
  computedAt: DateTime.utc(2026, 10, 15, 12),
  publishedAt: publishedAt ?? DateTime.utc(2026, 10, 20, 17, 30),
  updatedAt: updatedAt ?? publishedAt ?? DateTime.utc(2026, 10, 20, 17, 30),
  formulaVersion: '1.0.7',
  mStart: 50,
  mEnd: 90,
  g: 0.8,
  k: 1,
  u: 0.5,
  d: 0.5,
  coreCounted: 2,
  coreTotal: 2,
  extensionMastered: 2,
  extensionTotal: 4,
  expectedDifficulty: QuestionDifficulty.hard,
).toMap();

void main() {
  late InMemoryCosmos reports;

  Future<void> mount(
    WidgetTester tester, {
    List<Map<String, dynamic>> docs = const [],
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    reports = InMemoryCosmos(docs);
    InMemoryCosmosClient({'reports': reports}).install();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWith(_SignedInSam.new)],
        child: localizedTestApp(const Scaffold(body: MyReportsPage())),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a student with nothing released sees the empty state', (
    tester,
  ) async {
    await mount(tester);

    expect(find.byKey(const Key('my-reports-empty')), findsOneWidget);
    expect(find.byKey(const Key('my-reports-card-m1')), findsNothing);
  });

  testWidgets('a released report shows the grade, when it was computed and '
      'the reasoning', (tester) async {
    await mount(tester, docs: [_reportDoc(note: 'Ziek in week 3.')]);

    expect(find.byKey(const Key('my-reports-card-m1')), findsOneWidget);
    expect(find.text('Rapport 1'), findsOneWidget);
    expect(find.byKey(const Key('my-reports-grade-m1')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('my-reports-grade-m1'))).data,
      '84',
    );
    expect(find.textContaining('Computed on'), findsOneWidget);
    expect(find.text('Sam beheerst de kern volledig.'), findsOneWidget);
    expect(
      find.text('Note from your teacher: Ziek in week 3.'),
      findsOneWidget,
    );
    // Not revised, so no revision line.
    expect(find.byKey(const Key('my-reports-revised-m1')), findsNothing);
  });

  testWidgets('the breakdown is collapsed, sits below the grade and the '
      'reasoning, and opens on request', (tester) async {
    await mount(tester, docs: [_reportDoc()]);

    // Collapsed by design: the numbers are not the first thing on the page.
    expect(find.byKey(const Key('my-reports-breakdown-m1')), findsNothing);
    expect(find.textContaining('Mastery score M'), findsNothing);

    final toggle = find.byKey(const Key('my-reports-breakdown-toggle-m1'));
    expect(toggle, findsOneWidget);
    expect(find.text('How this grade was computed'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('my-reports-grade-m1'))).dy,
      lessThan(tester.getTopLeft(toggle).dy),
      reason: 'the grade comes first',
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('my-reports-justification-m1')))
          .dy,
      lessThan(tester.getTopLeft(toggle).dy),
      reason: 'then the reasoning',
    );

    await tester.tap(toggle);
    await tester.pump();

    expect(find.byKey(const Key('my-reports-breakdown-m1')), findsOneWidget);
    expect(
      find.text('Mastery score M: 50.0 at the start of the period → 90.0 now'),
      findsOneWidget,
    );
    expect(find.text('Growth score G = 0.80'), findsOneWidget);
    expect(
      find.text(
        'k = 1.00 (core) · u = 0.50 (extension) · d = 0.50 (shown at hard)',
      ),
      findsOneWidget,
    );
    expect(find.text('Core at the expected level: 2 / 2'), findsOneWidget);
    expect(find.text('Extension mastered: 2 / 4'), findsOneWidget);
    expect(find.text('Expected level for the core: hard'), findsOneWidget);
    expect(find.textContaining('formula v1.0.7'), findsOneWidget);
    // The two numbers behind d are teacher-side and not in the published
    // doc, so the student page cannot and does not claim them.
    expect(find.textContaining('Demonstrated at hard'), findsNothing);

    await tester.tap(toggle);
    await tester.pump();
    expect(find.byKey(const Key('my-reports-breakdown-m1')), findsNothing);
  });

  testWidgets('a rewritten copy says so', (tester) async {
    await mount(
      tester,
      docs: [
        _reportDoc(
          publishedAt: DateTime.utc(2026, 10, 20, 17, 30),
          updatedAt: DateTime.utc(2026, 10, 23, 9),
        ),
      ],
    );

    expect(find.byKey(const Key('my-reports-revised-m1')), findsOneWidget);
    expect(find.textContaining('Rewritten on'), findsOneWidget);
  });

  testWidgets('only this student\'s reports, newest report date first', (
    tester,
  ) async {
    await mount(
      tester,
      docs: [
        _reportDoc(),
        _reportDoc(
          milestoneId: 'm2',
          title: 'Rapport 2',
          dueAt: DateTime(2026, 12, 20),
          grade: 91,
        ),
        _reportDoc(uid: 'u2', milestoneId: 'm1', title: 'Van een klasgenoot'),
      ],
    );

    expect(find.byKey(const Key('my-reports-card-m2')), findsOneWidget);
    expect(find.byKey(const Key('my-reports-card-m1')), findsOneWidget);
    expect(find.text('Van een klasgenoot'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('my-reports-card-m2'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('my-reports-card-m1'))).dy,
      ),
    );
  });

  testWidgets('a report released while the tab is open appears on the next '
      'poll, without listening to the stream twice', (tester) async {
    await mount(tester);
    expect(find.byKey(const Key('my-reports-empty')), findsOneWidget);

    // The teacher presses Release in the next room.
    reports.upsert(_reportDoc());
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const Key('my-reports-empty')), findsNothing);
    expect(find.byKey(const Key('my-reports-card-m1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
