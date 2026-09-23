// `ReportBatchService` (#148): the class-wide run behind the Reports page.
//
// What it has to get right, over in-memory Cosmos and the real
// `GradeProposalService`:
//   - the deterministic number for every student in the list, then one
//     model call per student who still needs one;
//   - a student with no belief data on the milestone's objectives is
//     skipped rather than handed a computed 0;
//   - a re-run does not re-bill the model for a student who already has a
//     justification, and never touches a signed-off doc;
//   - a model failure is a *row* failure: the number survives, the error is
//     reported for that student, the rest of the class still runs, and a
//     single-row retry finishes the job.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal_service.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/milestone_service.dart';
import 'package:ai_tutor_python/services/grading/period_start_snapshot_service.dart';
import 'package:ai_tutor_python/services/grading/report_batch.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

final DateTime _now = DateTime.utc(2026, 10, 15, 12);
final DateTime _periodStart = DateTime.utc(2026, 9, 1);

/// Canned model, keyed on the student name the prompt carries. A name in
/// [fails] answers with a failure instead.
class _FakeConnector extends OpenaiConnector {
  _FakeConnector({this.fails = const {}});

  final Set<String> fails;
  final List<String> asked = <String>[];

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    final name = RegExp(r'"student":"([^"]*)"').firstMatch(input)!.group(1)!;
    asked.add(name);
    if (fails.contains(name)) {
      return ConnectorFailure(
        StateError('model is down'),
        StackTrace.current,
        const ChatNotice(ChatNoticeKind.tutorUnreachable),
      );
    }
    return ConnectorOk('$name did well.');
  }
}

Account _account(String uid, String first, {String className = '5A'}) =>
    Account(
      uid: uid,
      email: '$uid@example.com',
      firstName: first,
      lastName: 'Student',
      targetGoal: 'Python',
      className: className,
    );

Map<String, dynamic> _goal(
  String id, {
  String? parentId,
  int order = 1000,
  List<String> los = const [],
}) => {
  'id': id,
  'type': 'goal',
  'title': 'Goal $id',
  'parentId': parentId,
  'order': order,
  'optional': false,
  'objectives': [
    for (final lo in los)
      {'id': lo, 'statement': 'LO $lo', 'kind': 'apply', 'weight': 1.0},
  ],
  'moduleId': 'python-basics',
};

Map<String, dynamic> _belief(
  String uid,
  String subgoalId,
  String loId, {
  double alpha = 8,
  double beta = 1,
}) => {
  'id': '${uid}_${subgoalId}_$loId',
  'type': 'lo_belief',
  'uid': uid,
  'subgoalId': subgoalId,
  'loId': loId,
  'alpha': alpha,
  'beta': beta,
  'lastUpdatedAt': _now.subtract(const Duration(days: 3)).toIso8601String(),
  'lastPositiveAtCalibratedAt': _now
      .subtract(const Duration(days: 3))
      .toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
};

Milestone _milestone() => Milestone(
  id: 'm1',
  title: 'Rapport 1',
  periodStart: _periodStart,
  dueAt: DateTime.utc(2026, 10, 15),
  expectedDifficulty: QuestionDifficulty.medium,
  subgoalIds: const ['s1'],
  coreLoKeys: {Milestone.loKey('s1', 'a')},
);

class _Fixture {
  _Fixture({
    List<Map<String, dynamic>> beliefs = const [],
    List<Map<String, dynamic>> proposals = const [],
    Set<String> fails = const {},
  }) : goals = InMemoryCosmos([
         _goal('r'),
         _goal('s1', parentId: 'r', los: ['a', 'b']),
       ]),
       beliefs = InMemoryCosmos(beliefs),
       proposalDocs = InMemoryCosmos(proposals),
       connector = _FakeConnector(fails: fails);

  final InMemoryCosmos goals;
  final InMemoryCosmos beliefs;
  final InMemoryCosmos proposalDocs;
  final _FakeConnector connector;

  final InMemoryCosmos _progress = InMemoryCosmos();
  final InMemoryCosmos _history = InMemoryCosmos();
  final InMemoryCosmos _turns = InMemoryCosmos();
  final InMemoryCosmos _reports = InMemoryCosmos();
  final InMemoryCosmos _snapshots = InMemoryCosmos();

  late final LoBeliefsService beliefsService = LoBeliefsService(
    container: beliefs.container,
    getUid: () => 'teacher',
  );

  late final GoalsService goalsService = GoalsService(
    container: goals.container,
  );

  late final GradeProposalService proposals = GradeProposalService(
    container: proposalDocs.container,
    beliefs: beliefsService,
    goals: goalsService,
    progress: ProgressService(
      container: _progress.container,
      historyContainer: _history.container,
      getUid: () => 'teacher',
    ),
    reports: ReportService(
      container: _reports.container,
      getUid: () => 'teacher',
    ),
    turns: TurnHistoryService(
      container: _turns.container,
      getUid: () => 'teacher',
    ),
    snapshots: PeriodStartSnapshotService(
      container: _snapshots.container,
      milestones: MilestoneService(container: InMemoryCosmos().container),
      beliefs: beliefsService,
      getUid: () => 'teacher',
    ),
    supervision: const NoSupervisionSource(),
    connector: () => connector,
    now: () => _now,
  );

  late final ReportBatchService batch = ReportBatchService(
    proposals: proposals,
    beliefs: beliefsService,
    goals: goalsService,
  );
}

void main() {
  group('reportStatusOf', () {
    GradeProposal proposal({String? justification, DateTime? signedOffAt}) =>
        GradeProposal(
          uid: 'u',
          milestoneId: 'm1',
          formulaVersion: '1.0.7',
          computedAt: _now,
          k: 1,
          u: 1,
          d: 0,
          mEnd: 100,
          mStart: 0,
          g: 1,
          proposal: 90,
          coreTotal: 1,
          coreCounted: 1,
          extensionTotal: 1,
          extensionMastered: 1,
          masteredTotal: 2,
          hardCount: 0,
          staleLoCount: 0,
          neverProbedCount: 0,
          supervisedTurns: 0,
          homeTurns: 0,
          justification: justification,
          signedOffAt: signedOffAt,
        );

    test('no stored doc reads as "no data"', () {
      expect(reportStatusOf(null), ReportStatus.noData);
    });

    test('a bare number reads as "computed"', () {
      expect(reportStatusOf(proposal()), ReportStatus.computed);
    });

    test('a justification reads as "justification"', () {
      expect(
        reportStatusOf(proposal(justification: 'Sam did well.')),
        ReportStatus.justified,
      );
    });

    test('a signature wins over everything else', () {
      expect(
        reportStatusOf(proposal(justification: 'x', signedOffAt: _now)),
        ReportStatus.signedOff,
      );
    });
  });

  group('run', () {
    test('computes for every student and asks the model once each', () async {
      final f = _Fixture(
        beliefs: [
          _belief('u1', 's1', 'a'),
          _belief('u1', 's1', 'b'),
          _belief('u2', 's1', 'a'),
        ],
      );
      final results = <String, ReportBatchResult>{};
      await f.batch.run(
        milestone: _milestone(),
        students: [_account('u1', 'Ann'), _account('u2', 'Bo')],
        languageCode: 'nl',
        onResult: (uid, r) => results[uid] = r,
      );

      expect(f.connector.asked..sort(), ['Ann', 'Bo']);
      expect(results['u1']!.proposal!.justification, 'Ann did well.');
      expect(results['u2']!.proposal!.justification, 'Bo did well.');
      expect(results.values.every((r) => r.error == null), isTrue);
      // Both docs are on the server, with the numbers and the prose.
      expect(f.proposalDocs.docs.keys.toSet(), {'u1_m1', 'u2_m1'});
      expect(f.proposalDocs.docs['u2_m1']!['justification'], 'Bo did well.');
    });

    test('a student with no belief on the milestone is skipped, not given a '
        'computed 0', () async {
      final f = _Fixture(
        beliefs: [
          _belief('u1', 's1', 'a'),
          // u2 has only worked on a subgoal the milestone does not cover.
          _belief('u2', 's9', 'z'),
        ],
      );
      final results = <String, ReportBatchResult>{};
      await f.batch.run(
        milestone: _milestone(),
        students: [_account('u1', 'Ann'), _account('u2', 'Bo')],
        languageCode: 'nl',
        onResult: (uid, r) => results[uid] = r,
      );

      expect(results['u2']!.noData, isTrue);
      expect(results['u2']!.proposal, isNull);
      expect(reportStatusOf(results['u2']!.proposal), ReportStatus.noData);
      // Nothing was written for them, and the model was never asked.
      expect(f.proposalDocs.docs.keys, ['u1_m1']);
      expect(f.connector.asked, ['Ann']);
    });

    test('a re-run keeps an existing justification and does not pay for it '
        'again', () async {
      final f = _Fixture(beliefs: [_belief('u1', 's1', 'a')]);
      final students = [_account('u1', 'Ann')];
      await f.batch.run(
        milestone: _milestone(),
        students: students,
        languageCode: 'nl',
        onResult: (_, _) {},
      );
      expect(f.connector.asked, ['Ann']);

      ReportBatchResult? second;
      await f.batch.run(
        milestone: _milestone(),
        students: students,
        languageCode: 'nl',
        onResult: (_, r) => second = r,
      );

      expect(f.connector.asked, ['Ann'], reason: 'no second model call');
      expect(second!.proposal!.justification, 'Ann did well.');
    });

    test('a signed-off student is never recomputed or rewritten', () async {
      final f = _Fixture(beliefs: [_belief('u1', 's1', 'a')]);
      final students = [_account('u1', 'Ann')];
      await f.batch.run(
        milestone: _milestone(),
        students: students,
        languageCode: 'nl',
        onResult: (_, _) {},
      );
      final signed = await f.proposals.signOff(
        proposal: (await f.proposals.getStored('u1', 'm1'))!,
        adjustedGrade: 70,
        note: 'Ziek.',
      );
      f.connector.asked.clear();
      // The student masters another objective after signing.
      f.beliefs.upsert(_belief('u1', 's1', 'b'));

      ReportBatchResult? result;
      await f.batch.run(
        milestone: _milestone(),
        students: students,
        languageCode: 'nl',
        onResult: (_, r) => result = r,
      );

      expect(f.connector.asked, isEmpty);
      expect(result!.proposal!.proposal, signed.proposal);
      expect(result!.proposal!.adjustedGrade, 70);
      expect(reportStatusOf(result!.proposal), ReportStatus.signedOff);
    });

    test('a failed model call is one row: the number survives, the rest of '
        'the class still runs, and a retry finishes it', () async {
      final f = _Fixture(
        beliefs: [_belief('u1', 's1', 'a'), _belief('u2', 's1', 'a')],
        fails: {'Ann'},
      );
      final results = <String, ReportBatchResult>{};
      await f.batch.run(
        milestone: _milestone(),
        students: [_account('u1', 'Ann'), _account('u2', 'Bo')],
        languageCode: 'nl',
        onResult: (uid, r) => results[uid] = r,
      );

      expect(results['u1']!.error, isNotNull);
      expect(results['u1']!.proposal, isNotNull, reason: 'the number survived');
      expect(results['u1']!.proposal!.justification, isNull);
      expect(reportStatusOf(results['u1']!.proposal), ReportStatus.computed);
      // The other student was unaffected.
      expect(results['u2']!.error, isNull);
      expect(results['u2']!.proposal!.justification, 'Bo did well.');

      // The teacher retries the one row once the model is back.
      final healthy = _Fixture(
        beliefs: [_belief('u1', 's1', 'a')],
        proposals: [results['u1']!.proposal!.toMap()],
      );
      final retried = await healthy.batch.runOne(
        milestone: _milestone(),
        student: _account('u1', 'Ann'),
        languageCode: 'nl',
      );
      expect(retried.error, isNull);
      expect(retried.proposal!.justification, 'Ann did well.');
    });

    test(
      'runs the model calls concurrently and still answers for everyone',
      () async {
        final f = _Fixture(
          beliefs: [
            for (final uid in ['u1', 'u2', 'u3', 'u4']) _belief(uid, 's1', 'a'),
          ],
        );
        final results = <String, ReportBatchResult>{};
        await f.batch.run(
          milestone: _milestone(),
          students: [
            _account('u1', 'Ann'),
            _account('u2', 'Bo'),
            _account('u3', 'Cas'),
            _account('u4', 'Dee'),
          ],
          languageCode: 'nl',
          onResult: (uid, r) => results[uid] = r,
        );

        expect(f.connector.asked..sort(), ['Ann', 'Bo', 'Cas', 'Dee']);
        expect(results.values.map((r) => r.proposal?.justification).toSet(), {
          'Ann did well.',
          'Bo did well.',
          'Cas did well.',
          'Dee did well.',
        });
      },
    );
  });

  group('getForMilestone', () {
    test(
      'returns every student\'s doc for one milestone, across partitions',
      () async {
        final f = _Fixture(
          beliefs: [_belief('u1', 's1', 'a'), _belief('u2', 's1', 'a')],
        );
        await f.batch.run(
          milestone: _milestone(),
          students: [_account('u1', 'Ann'), _account('u2', 'Bo')],
          languageCode: 'nl',
          onResult: (_, _) {},
        );

        final stored = await f.proposals.getForMilestone('m1');
        expect(stored.map((p) => p.uid).toSet(), {'u1', 'u2'});
        expect(await f.proposals.getForMilestone('other'), isEmpty);
        expect(await f.proposals.milestoneIdsWithProposals(), {'m1'});
      },
    );
  });
}
