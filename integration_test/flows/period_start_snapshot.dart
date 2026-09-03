// End-to-end (#110): the exact per-LO period-start snapshot behind M_start.
//
//   1. A student's first session after a milestone's `periodStart` freezes
//      the period start: `period_start_snapshots` gets one doc for the
//      started milestone, with per-LO mastery and difficulty ratchet as of
//      `periodStart`; a milestone whose period has not started gets none.
//   2. Later in the period the teacher computes the proposal: M_start comes
//      from that doc — the same §2.3 arithmetic as M_end, expected level
//      included — and the drawer says so. The `progress_history` estimate
//      is only the fallback for a period without a snapshot
//      (grade_proposal.dart covers it).
//
// Real app both times: the student's real session start (TutorService →
// snapshot service → Cosmos), then the real Students page and drawer over
// the in-memory Cosmos. No model call is needed for the number.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/period_start_snapshot.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

final DateTime _now = DateTime.now().toUtc();
final DateTime _periodStart = _now.subtract(const Duration(days: 10));

Map<String, dynamic> _belief(
  String subgoalId,
  String loId, {
  required double alpha,
  required double beta,
  required int daysAgo,
  required String highest,
}) {
  final at = _now.subtract(Duration(days: daysAgo)).toIso8601String();
  return {
    'id': '${kStudentUid}_${subgoalId}_$loId',
    'type': 'lo_belief',
    'uid': kStudentUid,
    'subgoalId': subgoalId,
    'loId': loId,
    'alpha': alpha,
    'beta': beta,
    'lastUpdatedAt': at,
    'lastPositiveAtCalibratedAt': at,
    'highestPositiveDifficulty': highest,
    'recentNegativesAtCalibrated': 0,
    'firstMasteredAt': at,
  };
}

/// Core: "Print" at *hard*; extension: "Variables".
Map<String, dynamic> _milestone(String id, {required DateTime periodStart}) => {
  'id': id,
  'type': 'milestone',
  'title': 'Rapport $id',
  'periodStart': periodStart.toIso8601String(),
  'dueAt': _now.add(const Duration(days: 7)).toIso8601String(),
  'expectedDifficulty': 'hard',
  'subgoalIds': ['s1', 's2'],
  'coreLoKeys': ['s1/lo-print'],
  'updatedAt': _now.toIso8601String(),
};

Map<String, dynamic> _sample(String goalId, double progress, int daysAgo) {
  final at = _now.subtract(Duration(days: daysAgo));
  return {
    'id': '${at.toIso8601String()}_seed$goalId',
    'uid': kStudentUid,
    'goalId': goalId,
    'progress': progress,
    'at': at.toIso8601String(),
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder drawerList() => find
      .descendant(
        of: find.byType(StudentDetailDrawer),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Scrolls the drawer's *outer* list until [finder] is built (see
  /// grade_proposal.dart for why not `scrollUntilVisible`).
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      final position = tester.state<ScrollableState>(drawerList()).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  testWidgets('the first student session after the period start freezes it '
      "per LO, and the teacher's proposal reads M_start from that snapshot", (
    tester,
  ) async {
    // ---- Student side: the session after the period started -------------
    final student = AppHarness(
      extraDocs: {
        'milestones': [
          _milestone('m1', periodStart: _periodStart),
          _milestone('m2', periodStart: _now.add(const Duration(days: 20))),
        ],
        'lo_beliefs': [
          // Mastered, demonstrated at *medium*, last written before the
          // period: that is what the period start looked like.
          _belief(
            's1',
            'lo-print',
            alpha: 6,
            beta: 1,
            daysAgo: 20,
            highest: 'medium',
          ),
        ],
      },
    );
    await student.boot(tester);
    final snapshots = student.cosmos['period_start_snapshots'];
    await pumpUntil(
      tester,
      () => snapshots.docs.containsKey('${kStudentUid}_m1'),
      reason: 'the session did not freeze the started milestone',
    );
    final snapshot = snapshots.docs['${kStudentUid}_m1']!;
    expect(snapshot['uid'], kStudentUid);
    expect(snapshot['milestoneId'], 'm1');
    expect(snapshot['periodStart'], _periodStart.toIso8601String());
    final los = (snapshot['los'] as List).cast<Map>();
    expect(los, hasLength(1));
    expect(los.single['subgoalId'], 's1');
    expect(los.single['loId'], 'lo-print');
    expect(los.single['mastered'], isTrue);
    expect(los.single['highest'], 'medium');
    expect(los.single['exact'], isTrue);
    // The period of m2 has not started: nothing to freeze yet.
    expect(snapshots.docs.containsKey('${kStudentUid}_m2'), isFalse);
    await student.dispose(tester);

    // ---- Teacher side, later in the period --------------------------------
    // Since the snapshot, "Print" was demonstrated at hard and "Variables"
    // mastered. The history says "Print" was done before the period, so the
    // v1.0.5 rule would credit k_start = 1 (M_start = 50, proposal 86);
    // the snapshot knows its ratchet stood at medium, below the expected
    // hard: k_start = 0.
    final teacher = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'accounts': [accountDoc(studentIdentity)],
        'milestones': [_milestone('m1', periodStart: _periodStart)],
        'period_start_snapshots': [snapshot],
        'lo_beliefs': [
          _belief(
            's1',
            'lo-print',
            alpha: 6,
            beta: 1,
            daysAgo: 5,
            highest: 'hard',
          ),
          _belief(
            's2',
            'lo-var',
            alpha: 5,
            beta: 1,
            daysAgo: 3,
            highest: 'medium',
          ),
        ],
        'progress_history': [_sample('s1', 1.0, 45), _sample('s2', 1.0, 10)],
      },
    );
    await teacher.boot(tester);

    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Sam Student'));
    await tester.tap(find.text('Sam Student'));
    await pumpUntilFound(tester, find.byType(StudentDetailDrawer));

    await reveal(tester, find.text('Grade proposal'));
    await pumpUntilFound(tester, find.byKey(const Key('grade-compute')));
    await reveal(tester, find.byKey(const Key('grade-compute')));
    await tester.tap(find.byKey(const Key('grade-compute')));
    await pumpUntilFound(tester, find.byKey(const Key('grade-proposal')));

    // M_end = 50 + 50·(0.6·1 + 0.4·0.5) = 90; M_start = 0 (snapshot);
    // G = 0.9; P = 0.6·90 + 0.4·90 = 90.
    expect(
      tester.widget<Text>(find.byKey(const Key('grade-proposal'))).data,
      '90',
    );
    expect(find.text('Mastery now: 90.0'), findsOneWidget);
    expect(find.text('Mastery at period start: 0.0'), findsOneWidget);
    expect(find.text('Growth: 0.90'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('grade-start-source'))).data,
      'Period start: exact per-LO snapshot',
    );

    final doc = teacher.cosmos['grade_proposals'].docs['${kStudentUid}_m1']!;
    expect(doc['proposal'], 90);
    expect(doc['mStart'], 0.0);
    expect(doc['mStartSource'], 'snapshot');
    expect(doc['mStartInexactCount'], 0);
    expect(doc['formulaVersion'], '1.0.7');

    await teacher.dispose(tester);
  });
}
