// `PeriodStartSnapshot` and its service (#110): a belief untouched since
// the period start still holds its period-start value and is taken as is,
// one already written inside the period is read as of the snapshot moment
// and flagged; the doc round-trips; the service writes
// one doc per started milestone that has none, is idempotent, and takes a
// fresh one when the milestone's period start moves.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/grading/grade_formula.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/milestone_service.dart';
import 'package:ai_tutor_python/services/grading/period_start_snapshot.dart';
import 'package:ai_tutor_python/services/grading/period_start_snapshot_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_belief.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/tutor/belief_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _uid = 'stu';
final DateTime _periodStart = DateTime.utc(2026, 9, 1);
final DateTime _now = DateTime.utc(2026, 10, 11); // 40 days in

Milestone _milestone({String id = 'm1', DateTime? periodStart}) => Milestone(
  id: id,
  title: 'Rapport 1',
  periodStart: periodStart ?? _periodStart,
  dueAt: DateTime.utc(2026, 10, 15),
  expectedDifficulty: QuestionDifficulty.medium,
  subgoalIds: const ['s1', 's2'],
  coreLoKeys: {Milestone.loKey('s1', 'a')},
);

LoBelief _belief(
  String subgoalId,
  String loId, {
  required double alpha,
  required DateTime at,
  QuestionDifficulty? highest = QuestionDifficulty.medium,
  bool calibrated = true,
}) => LoBelief(
  subgoalId: subgoalId,
  loId: loId,
  alpha: alpha,
  beta: 1,
  lastUpdatedAt: at,
  lastPositiveAtCalibratedAt: calibrated ? at : null,
  highestPositiveDifficulty: highest,
  // The one-way stamp the formula reads as "mastered" (#168): on every doc
  // that ever crossed the §1.5 bar — here, whenever the calibrated positive
  // is there.
  firstMasteredAt: calibrated ? at : null,
);

void main() {
  group('build', () {
    test('a belief not written since the period start still holds its '
        'period-start value and is taken as is', () {
      // (8, 1) written 50 days before the period start and untouched since:
      // the doc the snapshot reads *is* the period-start doc. Since v1.0.8
      // no decay is applied on either side, so the age is irrelevant.
      final writtenAt = _periodStart.subtract(const Duration(days: 50));
      final b = _belief('s1', 'a', alpha: 8, at: writtenAt);
      expect(meetsMasteryMeanAndEvidence(const BeliefSnapshot(8, 1)), isTrue);

      final snap = PeriodStartSnapshot.build(
        uid: _uid,
        milestone: _milestone(),
        beliefs: [b],
        now: _now,
      );
      expect(snap.los.single.mastered, isTrue);
      expect(snap.los.single.highest, QuestionDifficulty.medium);
      expect(snap.los.single.exact, isTrue);
      expect(snap.exact, isTrue);
      expect(snap.periodStart, _periodStart);
      expect(snap.takenAt, _now);
    });

    test('a belief already written inside the period is read as of the '
        'snapshot moment and flagged inexact', () {
      final late = _belief(
        's1',
        'a',
        alpha: 6,
        at: _periodStart.add(const Duration(days: 5)),
        highest: QuestionDifficulty.hard,
      );
      final onTime = _belief('s2', 'c', alpha: 6, at: _periodStart);
      final snap = PeriodStartSnapshot.build(
        uid: _uid,
        milestone: _milestone(),
        beliefs: [late, onTime],
        now: _now,
      );
      final byKey = {for (final e in snap.los) e.key: e};
      expect(byKey['s1/a']!.exact, isFalse);
      expect(byKey['s1/a']!.mastered, isTrue);
      expect(byKey['s1/a']!.highest, QuestionDifficulty.hard);
      // Written exactly at the period start counts as untouched since.
      expect(byKey['s2/c']!.exact, isTrue);
      expect(snap.exact, isFalse);

      final los = [
        const MilestoneLo(subgoalId: 's1', loId: 'a', isCore: true),
        const MilestoneLo(subgoalId: 's2', loId: 'c', isCore: false),
        const MilestoneLo(subgoalId: 's2', loId: 'd', isCore: false),
      ];
      expect(snap.inexactCountFor(los), 1);
      // An LO without a belief has no entry: never probed at the start.
      expect(snap.inputs.containsKey('s2/d'), isFalse);
    });

    test('an LO never demonstrated at calibration is not mastered whatever '
        'its mean', () {
      final b = LoBelief(
        subgoalId: 's1',
        loId: 'a',
        alpha: 9,
        beta: 1,
        lastUpdatedAt: _periodStart,
        highestPositiveDifficulty: QuestionDifficulty.easy,
      );
      final snap = PeriodStartSnapshot.build(
        uid: _uid,
        milestone: _milestone(),
        beliefs: [b],
        now: _now,
      );
      expect(snap.los.single.mastered, isFalse);
      expect(snap.los.single.highest, QuestionDifficulty.easy);
    });

    test('the snapshot freezes the stamp, not the live belief (#168): a '
        'stamped LO whose (α, β) had collapsed by the period start is '
        'mastered, an unstamped one at (9, 1) is not', () {
      // M_start must read the same thing M_end reads, or a student whose
      // stamped LO sat under the bar at the period start would be handed
      // growth for a demonstration made before the period.
      final snap = PeriodStartSnapshot.build(
        uid: _uid,
        milestone: _milestone(),
        beliefs: [
          LoBelief(
            subgoalId: 's1',
            loId: 'a',
            alpha: 2,
            beta: 5,
            lastUpdatedAt: _periodStart,
            lastPositiveAtCalibratedAt: _periodStart,
            highestPositiveDifficulty: QuestionDifficulty.hard,
            firstMasteredAt: _periodStart.subtract(const Duration(days: 30)),
          ),
          LoBelief(
            subgoalId: 's1',
            loId: 'b',
            alpha: 9,
            beta: 1,
            lastUpdatedAt: _periodStart,
            lastPositiveAtCalibratedAt: _periodStart,
            highestPositiveDifficulty: QuestionDifficulty.medium,
          ),
        ],
        now: _now,
      );
      expect(snap.inputs['s1/a']!.mastered, isTrue);
      expect(snap.inputs['s1/a']!.highest, QuestionDifficulty.hard);
      expect(snap.inputs['s1/b']!.mastered, isFalse);
    });

    test('a doc from before the ratchet field is frozen at the formula\'s '
        '§2.5 reading (medium), not at "unknown" (#164)', () {
      // The snapshot is M_start's reading of the beliefs; it must agree
      // with what the report-moment formula reads for the same doc, or a
      // legacy student's growth would be measured from a k_start of 0.
      final b = _belief('s1', 'a', alpha: 6, at: _periodStart, highest: null);
      expect(b.highestPositiveDifficulty, isNull);
      final snap = PeriodStartSnapshot.build(
        uid: _uid,
        milestone: _milestone(),
        beliefs: [b],
        now: _now,
      );
      expect(snap.los.single.mastered, isTrue);
      expect(snap.los.single.highest, QuestionDifficulty.medium);
    });
  });

  test('round-trips through the doc map and matches its milestone', () {
    final snap = PeriodStartSnapshot.build(
      uid: _uid,
      milestone: _milestone(),
      beliefs: [
        _belief('s1', 'a', alpha: 6, at: _periodStart),
        // No calibrated positive either: with the flag set, a missing
        // level would read as medium under §2.5 (#164), and this entry
        // is here to round-trip a genuine null.
        _belief(
          's2',
          'c',
          alpha: 1.2,
          at: _periodStart.add(const Duration(days: 1)),
          highest: null,
          calibrated: false,
        ),
      ],
      now: _now,
    );
    final doc = snap.toMap();
    expect(doc['id'], '${_uid}_m1');
    expect(doc['type'], 'period_start_snapshot');
    expect(doc['periodStart'], '2026-09-01T00:00:00.000Z');
    final back = PeriodStartSnapshot.fromCosmos(doc);
    expect(back.uid, _uid);
    expect(back.milestoneId, 'm1');
    expect(back.periodStart, _periodStart);
    expect(back.takenAt, _now);
    expect(back.los.map((e) => e.key), ['s1/a', 's2/c']);
    expect(back.los[0].mastered, isTrue);
    expect(back.los[0].highest, QuestionDifficulty.medium);
    expect(back.los[0].exact, isTrue);
    expect(back.los[1].mastered, isFalse);
    expect(back.los[1].highest, isNull);
    expect(back.los[1].exact, isFalse);

    expect(back.isFor(_milestone()), isTrue);
    expect(
      back.isFor(
        _milestone(periodStart: _periodStart.add(const Duration(days: 1))),
      ),
      isFalse,
    );
    expect(back.isFor(_milestone(id: 'm2')), isFalse);
  });

  group('service', () {
    late InMemoryCosmos milestones;
    late InMemoryCosmos beliefs;
    late InMemoryCosmos snapshots;

    PeriodStartSnapshotService service({String? uid = _uid, DateTime? now}) =>
        PeriodStartSnapshotService(
          container: snapshots.container,
          milestones: MilestoneService(container: milestones.container),
          beliefs: LoBeliefsService(
            container: beliefs.container,
            getUid: () => uid,
          ),
          getUid: () => uid,
          now: () => now ?? _now,
        );

    setUp(() {
      milestones = InMemoryCosmos([
        _milestone().toMap(),
        // Not started yet.
        _milestone(
          id: 'm2',
          periodStart: _now.add(const Duration(days: 20)),
        ).toMap(),
      ]);
      beliefs = InMemoryCosmos([
        _belief('s1', 'a', alpha: 6, at: _periodStart).toMap(uid: _uid),
      ]);
      snapshots = InMemoryCosmos();
    });

    test('writes one snapshot per started milestone without one, and '
        'nothing on the next session', () async {
      final svc = service();
      expect(await svc.ensureForCurrentUser(), 1);
      expect(snapshots.docs.keys, ['${_uid}_m1']);
      final stored = await svc.getStored(_uid, 'm1');
      expect(stored!.los.single.key, 's1/a');
      expect(stored.los.single.mastered, isTrue);
      expect(stored.takenAt, _now);
      expect(await svc.getStored(_uid, 'm2'), isNull);

      // The belief moves inside the period; the snapshot does not.
      beliefs.upsert(
        _belief(
          's1',
          'a',
          alpha: 1.5,
          at: _now.add(const Duration(days: 1)),
        ).toMap(uid: _uid),
      );
      expect(
        await service(now: _now.add(const Duration(days: 2)))
            .ensureForCurrentUser(),
        0,
      );
      expect((await svc.getStored(_uid, 'm1'))!.los.single.mastered, isTrue);
      expect((await svc.getStored(_uid, 'm1'))!.takenAt, _now);
    });

    test(
      'takes a fresh snapshot when the milestone\'s period start moved',
      () async {
        await service().ensureForCurrentUser();
        final moved = _periodStart.add(const Duration(days: 7));
        milestones.upsert(_milestone(periodStart: moved).toMap());
        expect(await service().ensureForCurrentUser(), 1);
        final stored = await service().getStored(_uid, 'm1');
        expect(stored!.periodStart, moved);
      },
    );

    test('a milestone whose period starts later is frozen on the first '
        'session after that', () async {
      final later = _now.add(const Duration(days: 21));
      final svc = service(now: later);
      expect(await svc.ensureForCurrentUser(), 2);
      expect(snapshots.docs.keys, containsAll(['${_uid}_m1', '${_uid}_m2']));
    });

    test('no milestones, nothing written', () async {
      milestones.docs.clear();
      expect(await service().ensureForCurrentUser(), 0);
      expect(snapshots.docs, isEmpty);
    });

    test('no signed-in user is an error, not a silent skip', () async {
      await expectLater(
        service(uid: null).ensureForCurrentUser(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
