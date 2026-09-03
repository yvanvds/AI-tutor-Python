// `GradeProposalService` (#99) over in-memory Cosmos and the real services:
// the number from beliefs + milestone, M_start from the stored history,
// the reliability counts, the frozen signed-off doc, the justification
// round trip (only in-window reports reach the model; the stored text is
// the model's, the stored number is not), and sign-off.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal_service.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/milestone_service.dart';
import 'package:ai_tutor_python/services/grading/period_start_snapshot.dart';
import 'package:ai_tutor_python/services/grading/period_start_snapshot_service.dart';
import 'package:ai_tutor_python/services/progress/progress_sample.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _student = 'stu';
const _teacher = 'tea';

/// Canned model; records what it was asked.
class _FakeConnector extends OpenaiConnector {
  _FakeConnector(this.reply);
  final ConnectorResult reply;
  String? lastInstructions;
  String? lastInput;
  PreviousInputs? lastScope;

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    lastInstructions = instructions;
    lastInput = input;
    lastScope = inputs;
    return reply;
  }
}

final DateTime _now = DateTime.utc(2026, 10, 15, 12);
final DateTime _periodStart = DateTime.utc(2026, 9, 1);

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
  String subgoalId,
  String loId, {
  required double alpha,
  required double beta,
  required DateTime at,
  String? highest = 'medium',
  bool calibrated = true,
}) => {
  'id': '${_student}_${subgoalId}_$loId',
  'type': 'lo_belief',
  'uid': _student,
  'subgoalId': subgoalId,
  'loId': loId,
  'alpha': alpha,
  'beta': beta,
  'lastUpdatedAt': at.toIso8601String(),
  if (calibrated) 'lastPositiveAtCalibratedAt': at.toIso8601String(),
  if (highest != null) 'highestPositiveDifficulty': highest,
  'recentNegativesAtCalibrated': 0,
};

Map<String, dynamic> _sample(String goalId, double progress, DateTime at) =>
    ProgressSample(
      goalID: goalId,
      progress: progress,
      at: at,
    ).toMap(uid: _student);

Map<String, dynamic> _turn(DateTime at, {String provenance = 'home'}) => {
  'id': '${at.toIso8601String()}_x',
  'type': 'turn_history',
  'uid': _student,
  'turnAt': at.toIso8601String(),
  'subgoalId': 's1',
  'questionType': 'completeCodeQuestion',
  'provenance': provenance,
  'overallQuality': 'correct',
};

Map<String, dynamic> _report(String goalId, String text, DateTime at) => {
  'id': '${_student}_$goalId',
  'uid': _student,
  'goalId': goalId,
  'statusReport': text,
  'updatedAt': at.toIso8601String(),
};

Milestone _milestone({DateTime? periodStart}) => Milestone(
  id: 'm1',
  title: 'Rapport 1',
  periodStart: periodStart ?? _periodStart,
  dueAt: DateTime.utc(2026, 10, 15),
  expectedDifficulty: QuestionDifficulty.medium,
  subgoalIds: const ['s1', 's2'],
  coreLoKeys: {Milestone.loKey('s1', 'a'), Milestone.loKey('s1', 'b')},
);

/// A `period_start_snapshots` doc as the student app would have written it
/// (#110), from `(subgoalId, loId, mastered, highest, exact)` tuples.
Map<String, dynamic> _snapshot(
  List<(String, String, bool, String?, bool)> los, {
  DateTime? periodStart,
}) => PeriodStartSnapshot(
  uid: _student,
  milestoneId: 'm1',
  periodStart: periodStart ?? _periodStart,
  takenAt: (periodStart ?? _periodStart).add(const Duration(days: 1)),
  los: [
    for (final (sid, lid, mastered, highest, exact) in los)
      SnapshotLo(
        subgoalId: sid,
        loId: lid,
        mastered: mastered,
        highest: highest == null
            ? null
            : QuestionDifficulty.values.byName(highest),
        exact: exact,
      ),
  ],
).toMap();

class _Fixture {
  _Fixture({
    List<Map<String, dynamic>> beliefs = const [],
    List<Map<String, dynamic>> history = const [],
    List<Map<String, dynamic>> turns = const [],
    List<Map<String, dynamic>> reports = const [],
    List<Map<String, dynamic>> proposals = const [],
    List<Map<String, dynamic>> snapshots = const [],
    ConnectorResult reply = const ConnectorOk('Sam did well.'),
  }) : goals = InMemoryCosmos([
         _goal('r'),
         _goal('s1', parentId: 'r', los: ['a', 'b']),
         _goal('s2', parentId: 'r', order: 2000, los: ['c', 'd']),
       ]),
       beliefs = InMemoryCosmos(beliefs),
       progress = InMemoryCosmos(),
       history = InMemoryCosmos(history),
       turns = InMemoryCosmos(turns),
       reports = InMemoryCosmos(reports),
       proposals = InMemoryCosmos(proposals),
       snapshots = InMemoryCosmos(snapshots),
       connector = _FakeConnector(reply);

  final InMemoryCosmos goals;
  final InMemoryCosmos beliefs;
  final InMemoryCosmos progress;
  final InMemoryCosmos history;
  final InMemoryCosmos turns;
  final InMemoryCosmos reports;
  final InMemoryCosmos proposals;
  final InMemoryCosmos snapshots;
  final _FakeConnector connector;

  GradeProposalService service({DateTime? now}) => GradeProposalService(
    container: proposals.container,
    beliefs: LoBeliefsService(
      container: beliefs.container,
      getUid: () => _teacher,
    ),
    goals: GoalsService(container: goals.container),
    progress: ProgressService(
      container: progress.container,
      historyContainer: history.container,
      getUid: () => _teacher,
    ),
    reports: ReportService(
      container: reports.container,
      getUid: () => _teacher,
    ),
    turns: TurnHistoryService(
      container: turns.container,
      getUid: () => _teacher,
    ),
    snapshots: PeriodStartSnapshotService(
      container: snapshots.container,
      milestones: MilestoneService(container: InMemoryCosmos().container),
      beliefs: LoBeliefsService(
        container: beliefs.container,
        getUid: () => _teacher,
      ),
      getUid: () => _teacher,
    ),
    connector: () => connector,
    now: () => now ?? _now,
  );
}

void main() {
  final fresh = _now.subtract(const Duration(days: 3));
  final stale = _now.subtract(const Duration(days: 45));

  group('compute', () {
    test('reads the student\'s beliefs post-decay against the milestone and '
        'persists a draft with the counts', () async {
      final f = _Fixture(
        beliefs: [
          // Core: a mastered at hard, b mastered at medium.
          _belief('s1', 'a', alpha: 6, beta: 1, at: fresh, highest: 'hard'),
          _belief('s1', 'b', alpha: 5, beta: 1, at: fresh),
          // Extension: c mastered, d not (one easy positive, never at
          // calibration).
          _belief('s2', 'c', alpha: 5, beta: 1, at: fresh),
          _belief(
            's2',
            'd',
            alpha: 1.6,
            beta: 1,
            at: fresh,
            highest: 'easy',
            calibrated: false,
          ),
        ],
        turns: [
          _turn(_now.subtract(const Duration(days: 10))),
          _turn(
            _now.subtract(const Duration(days: 9)),
            provenance: 'supervised',
          ),
          // Before the period: not counted.
          _turn(_periodStart.subtract(const Duration(days: 1))),
        ],
      );
      final p = await f.service().compute(
        uid: _student,
        milestone: _milestone(),
      );

      expect(p.coreTotal, 2);
      expect(p.coreCounted, 2);
      expect(p.k, 1.0);
      expect(p.extensionTotal, 2);
      expect(p.extensionMastered, 1);
      expect(p.u, 0.5);
      expect(p.masteredTotal, 3);
      expect(p.hardCount, 1);
      expect(p.d, closeTo(1 / 3, 1e-9));
      // M = 50 + 50·(0.6·0.5 + 0.4·(1/3)) = 50 + 50·0.4333 = 71.67
      expect(p.mEnd, closeTo(71.667, 1e-3));
      // No history at all → M_start = 0 → G = M/100.
      expect(p.mStart, 0.0);
      expect(p.g, closeTo(0.71667, 1e-4));
      // P = 0.6·71.67 + 0.4·71.67 = 71.67 → 72
      expect(p.proposal, 72);
      expect(p.staleLoCount, 0);
      expect(p.neverProbedCount, 0);
      expect(p.supervisedTurns, 1);
      expect(p.homeTurns, 1);
      expect(p.isSignedOff, isFalse);
      expect(p.formulaVersion, '1.0.7');
      expect(p.mStartSource, MStartSource.history);

      final stored = f.proposals.docs['${_student}_m1'];
      expect(stored, isNotNull);
      expect(stored!['proposal'], 72);
      expect(stored['type'], 'grade_proposal');
    });

    test('M_start comes from the latest history sample at or before the '
        'period start, per subgoal, credited to each of its LOs', () async {
      final f = _Fixture(
        beliefs: [
          _belief('s1', 'a', alpha: 6, beta: 1, at: fresh, highest: 'hard'),
          _belief('s1', 'b', alpha: 5, beta: 1, at: fresh),
          _belief('s2', 'c', alpha: 5, beta: 1, at: fresh),
          _belief('s2', 'd', alpha: 5, beta: 1, at: fresh),
        ],
        history: [
          // s1 was half done before the period, then finished inside it:
          // the later sample must not leak into M_start.
          _sample('s1', 0.5, _periodStart.subtract(const Duration(days: 5))),
          _sample('s1', 1.0, _periodStart.add(const Duration(days: 5))),
          // s2 had nothing before the period.
          _sample('s2', 1.0, _periodStart.add(const Duration(days: 20))),
        ],
      );
      final p = await f.service().compute(
        uid: _student,
        milestone: _milestone(),
      );
      // k_start = 0.5 (both core LOs credited s1's 0.5), u_start = 0,
      // d_start = 0 → M_start = 50·0.5 = 25.
      expect(p.mStart, closeTo(25.0, 1e-9));
      // End: k = 1, u = 1, d = 1/4 → 50 + 50·(0.6 + 0.1) = 85.
      expect(p.mEnd, closeTo(85.0, 1e-9));
      expect(p.g, closeTo((85 - 25) / 75, 1e-9));
      // P = 0.6·85 + 0.4·80 = 83.
      expect(p.proposal, 83);
      expect(p.mStartSource, MStartSource.history);
      expect(f.proposals.docs['${_student}_m1']!['mStartSource'], 'history');
    });

    group('M_start from the period-start snapshot (#110)', () {
      final endBeliefs = [
        _belief('s1', 'a', alpha: 6, beta: 1, at: fresh, highest: 'hard'),
        _belief('s1', 'b', alpha: 5, beta: 1, at: fresh),
        _belief('s2', 'c', alpha: 5, beta: 1, at: fresh),
        _belief('s2', 'd', alpha: 5, beta: 1, at: fresh),
      ];
      // The history rule would say M_start = 25 (s1 half done).
      final history = [
        _sample('s1', 0.5, _periodStart.subtract(const Duration(days: 5))),
        _sample('s1', 1.0, _periodStart.add(const Duration(days: 5))),
        _sample('s2', 1.0, _periodStart.add(const Duration(days: 20))),
      ];

      test(
        'is the same §2.3 arithmetic as M_end over the frozen per-LO '
        'state, expected level included, and wins over the history',
        () async {
          final f = _Fixture(
            beliefs: endBeliefs,
            history: history,
            snapshots: [
              _snapshot([
                // Core: a mastered at medium (counts), b not mastered.
                ('s1', 'a', true, 'medium', true),
                ('s1', 'b', false, 'easy', true),
                // Extension: c mastered at medium, d had no belief yet.
                ('s2', 'c', true, 'medium', true),
              ]),
            ],
          );
          final p = await f.service().compute(
            uid: _student,
            milestone: _milestone(),
          );
          // k_start = 1/2, u_start = 1/2, d_start = 0/2 →
          // M_start = 50·0.5 + 50·0.5·(0.6·0.5) = 25 + 7.5 = 32.5.
          expect(p.mStart, closeTo(32.5, 1e-9));
          expect(p.mEnd, closeTo(85.0, 1e-9));
          expect(p.g, closeTo((85 - 32.5) / 67.5, 1e-9));
          // P = 0.6·85 + 0.4·77.78 = 82.1 → 82.
          expect(p.proposal, 82);
          expect(p.mStartSource, MStartSource.snapshot);
          expect(p.mStartInexactCount, 0);
          final stored = f.proposals.docs['${_student}_m1']!;
          expect(stored['mStartSource'], 'snapshot');
          expect(stored['mStartInexactCount'], 0);
        },
      );

      test('the expected level gates k_start like it gates k', () async {
        final f = _Fixture(
          beliefs: endBeliefs,
          snapshots: [
            _snapshot([
              ('s1', 'a', true, 'medium', true),
              ('s1', 'b', true, 'medium', true),
            ]),
          ],
        );
        final hard = Milestone(
          id: 'm1',
          title: 'Rapport 1',
          periodStart: _periodStart,
          dueAt: DateTime.utc(2026, 10, 15),
          expectedDifficulty: QuestionDifficulty.hard,
          subgoalIds: const ['s1', 's2'],
          coreLoKeys: {Milestone.loKey('s1', 'a'), Milestone.loKey('s1', 'b')},
        );
        final p = await f.service().compute(uid: _student, milestone: hard);
        // Both core LOs mastered at the start, but only at medium: k_start
        // = 0 → M_start = 0 (the 50 is gated by the expected level).
        expect(p.mStart, 0.0);
        expect(p.mStartSource, MStartSource.snapshot);
      });

      test('counts the milestone LOs the snapshot read late', () async {
        final f = _Fixture(
          beliefs: endBeliefs,
          snapshots: [
            _snapshot([
              ('s1', 'a', true, 'medium', false),
              ('s1', 'b', false, null, true),
              ('s2', 'c', true, 'medium', false),
              // Not a milestone LO: does not count.
              ('s9', 'z', true, 'hard', false),
            ]),
          ],
        );
        final p = await f.service().compute(
          uid: _student,
          milestone: _milestone(),
        );
        expect(p.mStartSource, MStartSource.snapshot);
        expect(p.mStartInexactCount, 2);
      });

      test('a snapshot taken for another period start is ignored: the '
          'history rule applies', () async {
        final f = _Fixture(
          beliefs: endBeliefs,
          history: history,
          snapshots: [
            _snapshot([
              ('s1', 'a', true, 'hard', true),
            ], periodStart: _periodStart.subtract(const Duration(days: 30))),
          ],
        );
        final p = await f.service().compute(
          uid: _student,
          milestone: _milestone(),
        );
        expect(p.mStart, closeTo(25.0, 1e-9));
        expect(p.mStartSource, MStartSource.history);
        expect(p.mStartInexactCount, 0);
      });

      test('a proposal doc from before #110 reads as history-based', () {
        final p = GradeProposal.fromCosmos({
          'uid': _student,
          'milestoneId': 'm1',
          'mStart': 25,
        });
        expect(p.mStartSource, MStartSource.history);
        expect(p.mStartInexactCount, 0);
      });
    });

    test('stale and never-probed LOs are counted as the honest uncertainty '
        'signal; a narrow posterior is not', () async {
      final f = _Fixture(
        beliefs: [
          _belief('s1', 'a', alpha: 5, beta: 1, at: fresh),
          _belief('s1', 'b', alpha: 5, beta: 1, at: stale),
          // c, d never probed.
        ],
      );
      final p = await f.service().compute(
        uid: _student,
        milestone: _milestone(),
      );
      expect(p.neverProbedCount, 2);
      expect(p.staleLoCount, 3);
    });

    test(
      'a signed-off proposal is returned frozen, never recomputed',
      () async {
        final signed = GradeProposal(
          uid: _student,
          milestoneId: 'm1',
          formulaVersion: '1.0.5',
          computedAt: _now.subtract(const Duration(days: 2)),
          k: 1,
          u: 1,
          d: 0,
          mEnd: 80,
          mStart: 0,
          g: 0.8,
          proposal: 80,
          coreTotal: 2,
          coreCounted: 2,
          extensionTotal: 2,
          extensionMastered: 2,
          masteredTotal: 4,
          hardCount: 0,
          staleLoCount: 0,
          neverProbedCount: 0,
          supervisedTurns: 0,
          homeTurns: 0,
          adjustedGrade: 78,
          adjustmentNote: 'ill in week 3',
          signedOffAt: _now.subtract(const Duration(days: 1)),
        );
        final f = _Fixture(proposals: [signed.toMap()]);
        // The beliefs would now say "nothing mastered" — irrelevant.
        final p = await f.service().compute(
          uid: _student,
          milestone: _milestone(),
        );
        expect(p.proposal, 80);
        expect(p.finalGrade, 78);
        expect(p.isSignedOff, isTrue);
        expect(f.proposals.docs['${_student}_m1']!['proposal'], 80);
      },
    );

    test('recomputing a draft keeps the teacher\'s adjustment and drops a '
        'justification written for another number', () async {
      final f = _Fixture(
        beliefs: [_belief('s1', 'a', alpha: 5, beta: 1, at: fresh)],
      );
      final svc = f.service();
      final first = await svc.compute(uid: _student, milestone: _milestone());
      final justified = await svc.writeJustification(
        proposal: first,
        milestone: _milestone(),
        studentName: 'Sam',
        calibrationLevel: 'medium',
        languageCode: 'en',
      );
      expect(justified.justification, 'Sam did well.');
      // Teacher typed an adjustment but did not sign yet.
      f.proposals.upsert(
        justified.copyWith(adjustedGrade: 40, adjustmentNote: 'note').toMap(),
      );

      // Same data → same number → the justification survives.
      final again = await svc.compute(uid: _student, milestone: _milestone());
      expect(again.proposal, first.proposal);
      expect(again.justification, 'Sam did well.');
      expect(again.adjustedGrade, 40);
      expect(again.adjustmentNote, 'note');

      // More mastery → different number → the narrative is stale and goes.
      f.beliefs.upsert(_belief('s1', 'b', alpha: 5, beta: 1, at: fresh));
      final moved = await svc.compute(uid: _student, milestone: _milestone());
      expect(moved.proposal, isNot(first.proposal));
      expect(moved.justification, isNull);
      expect(moved.adjustedGrade, 40);
    });
  });

  group('writeJustification', () {
    test('hands the model the number and the in-window evidence in a fresh '
        'session, stores the reply, leaves the number alone', () async {
      final f = _Fixture(
        beliefs: [_belief('s1', 'a', alpha: 5, beta: 1, at: fresh)],
        reports: [
          _report('s1', 'Werkt vlot.', _now.subtract(const Duration(days: 4))),
          _report(
            's2',
            'OUD RAPPORT',
            _periodStart.subtract(const Duration(days: 3)),
          ),
        ],
        history: [
          _sample('s1', 0.5, _periodStart.subtract(const Duration(days: 1))),
          _sample('s1', 1.0, _now.subtract(const Duration(days: 4))),
        ],
        reply: const ConnectorOk(
          '<TEXT>Sam beheerst de kern.</TEXT><META>{"type":"x"}</META>',
        ),
      );
      final svc = f.service();
      final draft = await svc.compute(uid: _student, milestone: _milestone());
      final result = await svc.writeJustification(
        proposal: draft,
        milestone: _milestone(),
        studentName: 'Sam',
        calibrationLevel: 'hard',
        languageCode: 'nl',
      );

      expect(f.connector.lastScope, PreviousInputs.newSession);
      expect(f.connector.lastInstructions, contains('${draft.proposal}/100'));
      expect(f.connector.lastInput, contains('Werkt vlot.'));
      expect(f.connector.lastInput, isNot(contains('OUD RAPPORT')));
      expect(f.connector.lastInput, contains('"atPeriodStart":0.5'));
      expect(f.connector.lastInput, contains('"now":1.0'));
      expect(
        f.connector.lastInput,
        contains('"masteryScoreStartSource":"history"'),
      );

      expect(result.justification, 'Sam beheerst de kern.');
      expect(result.justificationAt, _now);
      expect(result.proposal, draft.proposal);
      final stored = f.proposals.docs['${_student}_m1']!;
      expect(stored['justification'], 'Sam beheerst de kern.');
      expect(stored['proposal'], draft.proposal);
    });

    test('a transport failure surfaces as GradeJustificationException and '
        'stores nothing', () async {
      final f = _Fixture(
        beliefs: [_belief('s1', 'a', alpha: 5, beta: 1, at: fresh)],
        reply: ConnectorFailure(
          StateError('boom'),
          StackTrace.current,
          const ChatNotice(ChatNoticeKind.tutorUnreachable),
        ),
      );
      final svc = f.service();
      final draft = await svc.compute(uid: _student, milestone: _milestone());
      await expectLater(
        svc.writeJustification(
          proposal: draft,
          milestone: _milestone(),
          studentName: 'Sam',
          calibrationLevel: 'medium',
          languageCode: 'en',
        ),
        throwsA(isA<GradeJustificationException>()),
      );
      expect(
        f.proposals.docs['${_student}_m1']!.containsKey('justification'),
        isFalse,
      );
    });
  });

  test('signOff stores the adjusted grade, the note and the stamp', () async {
    final f = _Fixture(
      beliefs: [_belief('s1', 'a', alpha: 5, beta: 1, at: fresh)],
    );
    final svc = f.service();
    final draft = await svc.compute(uid: _student, milestone: _milestone());
    final signed = await svc.signOff(
      proposal: draft,
      adjustedGrade: 61,
      note: '  copied in class, week 4 ',
    );
    expect(signed.isSignedOff, isTrue);
    expect(signed.finalGrade, 61);
    expect(signed.adjustmentNote, 'copied in class, week 4');
    expect(signed.signedOffAt, _now);
    final stored = GradeProposal.fromCosmos(
      f.proposals.docs['${_student}_m1']!,
    );
    expect(stored.adjustedGrade, 61);
    expect(stored.signedOffAt, _now);
    expect(stored.proposal, draft.proposal);
  });
}
