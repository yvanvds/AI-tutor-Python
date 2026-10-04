// The passive supervised-vs-home check (#107): per student, per LO, home
// credit that the supervised work after it contradicts is a teacher-only
// event — audit by default, strong when large and well-evidenced — and the
// thresholds are frugal, because there is very little home work.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/provenance_gap.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _home = EvidenceProvenance.home;
const _supervised = EvidenceProvenance.supervised;

/// Day [day] of October 2026, at [hour] UTC.
DateTime _at(int day, [int hour = 10, int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);

/// A pattern of direct signals, one character pair each: `H`/`S` for home or
/// supervised, `+`/`-` for the direction, an hour apart from 1 October on.
List<ProvenanceSignal> _signals(String pattern) {
  final out = <ProvenanceSignal>[];
  for (var i = 0; i + 1 < pattern.length; i += 2) {
    out.add(
      ProvenanceSignal(
        at: _at(1).add(Duration(hours: i ~/ 2)),
        supervised: pattern[i] == 'S',
        positive: pattern[i + 1] == '+',
      ),
    );
  }
  return out;
}

ProvenanceGap? _detect(String pattern) => detectProvenanceGap(
  subgoalId: 's1',
  loId: 'lo1',
  signals: _signals(pattern),
);

/// A graded turn on [loId] of `s1` with one direct applied signal, positive
/// or negative at the unit weight — or exactly [applied].
PersistedTurnRecord _turn(
  String id,
  DateTime at, {
  EvidenceProvenance provenance = _home,
  bool positive = true,
  String subgoalId = 's1',
  String loId = 'lo1',
  List<String>? targets,
  List<TurnAppliedSignal>? applied,
}) => PersistedTurnRecord(
  id: id,
  turnAt: at,
  subgoalId: subgoalId,
  targetLOIds: targets ?? [loId],
  questionType: 'completeCodeQuestion',
  difficulty: QuestionDifficulty.medium,
  isFollowUp: false,
  chainDepth: 0,
  selectionReason: null,
  overallQuality: positive ? AnswerQuality.correct : AnswerQuality.wrong,
  loSignals: const [],
  hadFallback: false,
  appliedSignals:
      applied ??
      [
        TurnAppliedSignal(
          subgoalId: subgoalId,
          loId: loId,
          alphaDelta: positive ? 2.0 : 0.0,
          betaDelta: positive ? 0.0 : 2.0,
        ),
      ],
  calibrationBefore: QuestionDifficulty.medium,
  calibrationAfter: QuestionDifficulty.medium,
  subgoalProgressAfter: 0.0,
  loStatusAfter: const [],
  subgoalAdvanced: false,
  provenance: provenance,
);

/// A timetable that reads [lessonTime] as lesson time, and counts its reads.
class _Timetable extends SupervisionSource {
  _Timetable([this.lessonTime = const {}]);

  final Set<DateTime> lessonTime;
  int reads = 0;
  bool fail = false;

  @override
  bool isWiredFor(String className) => true;

  @override
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  }) async => lessonTime.contains(at) ? _supervised : _home;

  @override
  Future<List<EvidenceProvenance>> provenancesFor({
    required String uid,
    required List<DateTime> ats,
  }) async {
    reads += 1;
    if (fail) throw StateError('timetable unreachable');
    return [
      for (final at in ats) lessonTime.contains(at) ? _supervised : _home,
    ];
  }
}

void main() {
  group('detectProvenanceGap', () {
    test('three positive home signals and three negative supervised ones '
        'after them: an audit gap', () {
      final gap = _detect('H+H+H+S-S-S-')!;
      expect(gap.severity, TurnSignalEventSeverity.audit);
      expect(gap.homeSignals, 3);
      expect(gap.homePositive, 3);
      expect(gap.supervisedSignals, 3);
      expect(gap.supervisedPositive, 0);
      expect(gap.subgoalId, 's1');
      expect(gap.loId, 'lo1');
    });

    test('frugal: fewer than three signals on either side is no gap', () {
      expect(PolicyConstants.provenanceGapMinSignals, 3);
      expect(_detect('H+H+S-S-S-'), isNull);
      expect(_detect('H+H+H+S-S-'), isNull);
      expect(_detect('H+H+H+'), isNull);
    });

    test('class work from before the home work is left out: failing in '
        'class and then getting it at home is the system working', () {
      expect(_detect('S-S-S-H+H+H+'), isNull);
      // … and it does not water a later contradiction down either.
      expect(_detect('S+S+S+H+H+H+S-S-S-'), isNotNull);
    });

    test('home work no class work came after yet is not counted: it can '
        'still be confirmed', () {
      // Two home signals before the class work, one after: two count.
      expect(_detect('H+H+S-S-S-H+'), isNull);
      // A home signal at the same moment as the last class signal is not
      // before it.
      final sameMoment = [
        ..._signals('H+H+S-S-'),
        ProvenanceSignal(at: _at(1, 20), supervised: true, positive: false),
        ProvenanceSignal(at: _at(1, 20), supervised: false, positive: true),
      ];
      expect(
        detectProvenanceGap(subgoalId: 's1', loId: 'lo1', signals: sameMoment),
        isNull,
      );
    });

    test('the signs must differ: home mostly positive, class mostly '
        'negative', () {
      // 3 of 3 against 2 of 3: class is still mostly positive.
      expect(_detect('H+H+H+S+S+S-'), isNull);
      // 1 of 3 at home: home is not mostly positive.
      expect(_detect('H+H-H-S-S-S-'), isNull);
      // A class share of exactly one half is not below it.
      expect(_detect('H+H+H+S+S-S+S-'), isNull);
    });

    test('and the shares lie at least 0.4 apart', () {
      expect(PolicyConstants.provenanceGapMinShareGap, 0.4);
      // 2 of 3 against 1 of 3: on either side of a half, but 0.33 apart.
      expect(_detect('H+H+H-S+S-S-'), isNull);
      // 2 of 3 against 0 of 3, and 3 of 3 against 1 of 3: 0.67 apart.
      expect(_detect('H+H+H-S-S-S-'), isNotNull);
      expect(_detect('H+H+H+S+S-S-'), isNotNull);
      // 4 of 5 against 2 of 5: exactly 0.4 — the last bit does not rule
      // it out.
      expect(_detect('H+H+H+H+H-S+S+S-S-S-'), isNotNull);
    });

    test('strong only with six signals a side and the shares 0.6 apart', () {
      expect(PolicyConstants.provenanceGapStrongMinSignals, 6);
      expect(PolicyConstants.provenanceGapStrongMinShareGap, 0.6);
      // 6 of 6 against 2 of 6: 0.67.
      expect(
        _detect('H+H+H+H+H+H+S+S+S-S-S-S-')!.severity,
        TurnSignalEventSeverity.strong,
      );
      // 5 of 6 against 2 of 6: 0.5 — a gap, but audit.
      expect(
        _detect('H+H+H+H+H+H-S+S+S-S-S-S-')!.severity,
        TurnSignalEventSeverity.audit,
      );
      // Five home signals, all positive, against 0 of 6: audit.
      expect(
        _detect('H+H+H+H+H+S-S-S-S-S-S-')!.severity,
        TurnSignalEventSeverity.audit,
      );
    });
  });

  group('directSignalsOn', () {
    test('only the signals on the turn\'s own target LO, each by the sign '
        'of its belief delta', () {
      final records = [
        _turn(
          't1',
          _at(1),
          targets: ['lo1'],
          applied: const [
            // At the evidence cap a positive grows α and shrinks β.
            TurnAppliedSignal(
              subgoalId: 's1',
              loId: 'lo1',
              alphaDelta: 0.3,
              betaDelta: -0.1,
            ),
            // An incidental signal on another LO of the subgoal.
            TurnAppliedSignal(
              subgoalId: 's1',
              loId: 'lo2',
              alphaDelta: 2.0,
              betaDelta: 0.0,
            ),
            // An incidental signal on an LO of another subgoal.
            TurnAppliedSignal(
              subgoalId: 's0',
              loId: 'lo1',
              alphaDelta: 2.0,
              betaDelta: 0.0,
            ),
          ],
        ),
        _turn(
          't2',
          _at(2),
          applied: const [
            // At the cap a negative shrinks α and grows β.
            TurnAppliedSignal(
              subgoalId: 's1',
              loId: 'lo1',
              alphaDelta: -0.4,
              betaDelta: 1.6,
            ),
          ],
        ),
        _turn(
          't3',
          _at(3),
          applied: const [
            // Moved neither way: says nothing.
            TurnAppliedSignal(
              subgoalId: 's1',
              loId: 'lo1',
              alphaDelta: 0.0,
              betaDelta: 0.0,
            ),
          ],
        ),
        // Not about lo1: lo1 is not its target.
        _turn('t4', _at(4), loId: 'lo2'),
      ];
      final signals = directSignalsOn(
        subgoalId: 's1',
        loId: 'lo1',
        records: records,
        supervised: const [false, true, false, false],
      );
      expect(signals.map((s) => (s.positive, s.supervised)), [
        (true, false),
        (false, true),
      ]);
    });
  });

  group('ProvenanceGapService.checkAfter', () {
    late InMemoryCosmos store;
    late TurnHistoryService turns;
    late _Timetable timetable;
    late ProvenanceGapService service;

    setUp(() {
      store = InMemoryCosmos();
      turns = TurnHistoryService(
        container: store.container,
        getUid: () => 'u1',
      );
      timetable = _Timetable();
      service = ProvenanceGapService(turns: turns, supervision: timetable);
    });

    List<Map<String, dynamic>> gapDocs() => [
      for (final d in store.docs.values)
        if ((d['signalEvents'] as List?)?.any(
              (e) => (e as Map)['kind'] == 'provenanceGap',
            ) ??
            false)
          d,
    ];

    Future<void> seed(List<PersistedTurnRecord> records) async {
      for (final r in records) {
        await turns.append(r);
      }
    }

    test('writes an audit record on the LO\'s subgoal with the counts the '
        'teacher reads', () async {
      await seed([
        _turn('h1', _at(1, 19)),
        _turn('h2', _at(1, 20)),
        _turn('h3', _at(1, 21)),
        _turn('s1', _at(2), provenance: _supervised, positive: false),
        _turn('s2', _at(2, 10, 5), provenance: _supervised, positive: false),
      ]);
      final now = _turn(
        's3',
        _at(2, 10, 10),
        provenance: _supervised,
        positive: false,
      );
      await turns.append(now);

      final gaps = await service.checkAfter(uid: 'u1', turn: now);

      expect(gaps, hasLength(1));
      final doc = gapDocs().single;
      expect(doc['uid'], 'u1');
      expect(doc['subgoalId'], 's1');
      expect(doc['questionType'], '', reason: 'an audit record, no oefening');
      final event = (doc['signalEvents'] as List).single as Map;
      expect(event['severity'], 'audit');
      expect(event['details'], {
        'subgoalId': 's1',
        'loId': 'lo1',
        'homeSignals': 3,
        'homePositive': 3,
        'supervisedSignals': 3,
        'supervisedPositive': 0,
        'windowDays': 42,
      });
      // It reads back as what was written.
      final read = PersistedTurnRecord.fromCosmos(doc);
      final back = ProvenanceGap.fromEvent(read.signalEvents.single)!;
      expect(back.homePositive, 3);
      expect(back.supervisedSignals, 3);
      expect(back.severity, TurnSignalEventSeverity.audit);
    });

    test('the turn in hand counts once, whether or not its write has '
        'landed', () async {
      await seed([
        _turn('h1', _at(1, 19)),
        _turn('h2', _at(1, 20)),
        _turn('h3', _at(1, 21)),
        _turn('s1', _at(2), provenance: _supervised, positive: false),
        _turn('s2', _at(2, 10, 5), provenance: _supervised, positive: false),
      ]);
      final now = _turn(
        's3',
        _at(2, 10, 10),
        provenance: _supervised,
        positive: false,
      );

      // Not stored yet: still the third class signal.
      final gaps = await service.checkAfter(uid: 'u1', turn: now);
      expect(gaps.single.supervisedSignals, 3);
    });

    test('an older turn recorded as home but in lesson time counts as '
        'supervised (#219)', () async {
      // The two class answers before the timetable was the source: `home`
      // on the record, in a lesson by the timetable.
      timetable = _Timetable({_at(2), _at(2, 10, 5)});
      service = ProvenanceGapService(turns: turns, supervision: timetable);
      await seed([
        _turn('h1', _at(1, 19)),
        _turn('h2', _at(1, 20)),
        _turn('h3', _at(1, 21)),
        _turn('s1', _at(2), positive: false),
        _turn('s2', _at(2, 10, 5), positive: false),
      ]);
      final now = _turn(
        's3',
        _at(2, 10, 10),
        provenance: _supervised,
        positive: false,
      );

      final gaps = await service.checkAfter(uid: 'u1', turn: now);

      expect(gaps.single.homeSignals, 3);
      expect(gaps.single.supervisedSignals, 3);

      // Read by the record alone the two would be home work, and there
      // would be no gap.
      store = InMemoryCosmos();
      turns = TurnHistoryService(
        container: store.container,
        getUid: () => 'u1',
      );
      final byRecord = ProvenanceGapService(
        turns: turns,
        supervision: const NoSupervisionSource(),
      );
      await seed([
        _turn('h1', _at(1, 19)),
        _turn('h2', _at(1, 20)),
        _turn('h3', _at(1, 21)),
        _turn('s1', _at(2), positive: false),
        _turn('s2', _at(2, 10, 5), positive: false),
      ]);
      expect(await byRecord.checkAfter(uid: 'u1', turn: now), isEmpty);
    });

    test('once per LO per window: the same gap is not raised again, a gap '
        'grown strong is', () async {
      final history = [
        for (var i = 0; i < 6; i++) _turn('h$i', _at(1, 12 + i)),
        _turn('s0', _at(2, 9), provenance: _supervised, positive: false),
        _turn('s1', _at(2, 9, 5), provenance: _supervised, positive: false),
      ];
      await seed(history);
      final third = _turn(
        's2',
        _at(2, 9, 10),
        provenance: _supervised,
        positive: false,
      );
      await turns.append(third);
      expect(
        (await service.checkAfter(uid: 'u1', turn: third)).single.severity,
        TurnSignalEventSeverity.audit,
      );

      // The fourth and fifth class answer: still audit — nothing new.
      for (final (i, minute) in [(3, 15), (4, 20)]) {
        final next = _turn(
          's$i',
          _at(2, 9, minute),
          provenance: _supervised,
          positive: false,
        );
        await turns.append(next);
        expect(await service.checkAfter(uid: 'u1', turn: next), isEmpty);
      }
      expect(gapDocs(), hasLength(1));

      // The sixth: six a side, 6 of 6 against 0 of 6 — strong, raised.
      final sixth = _turn(
        's5',
        _at(2, 9, 25),
        provenance: _supervised,
        positive: false,
      );
      await turns.append(sixth);
      expect(
        (await service.checkAfter(uid: 'u1', turn: sixth)).single.severity,
        TurnSignalEventSeverity.strong,
      );
      expect(gapDocs(), hasLength(2));

      // And a strong one is not raised again.
      final seventh = _turn(
        's6',
        _at(2, 9, 30),
        provenance: _supervised,
        positive: false,
      );
      await turns.append(seventh);
      expect(await service.checkAfter(uid: 'u1', turn: seventh), isEmpty);
    });

    test('home work older than the window is out of it', () async {
      expect(PolicyConstants.provenanceGapWindow, const Duration(days: 42));
      final now = _turn(
        's3',
        _at(20),
        provenance: _supervised,
        positive: false,
      );
      final old = now.turnAt.subtract(const Duration(days: 43));
      await seed([
        _turn('h1', old),
        _turn('h2', _at(19, 19)),
        _turn('h3', _at(19, 20)),
        _turn('s1', _at(19, 21), provenance: _supervised, positive: false),
        _turn('s2', _at(19, 22), provenance: _supervised, positive: false),
      ]);
      expect(await service.checkAfter(uid: 'u1', turn: now), isEmpty);
    });

    test(
      'another student\'s or another subgoal\'s turns are not read',
      () async {
        final other = TurnHistoryService(
          container: store.container,
          getUid: () => 'u2',
        );
        for (final r in [
          _turn('h1', _at(1, 19)),
          _turn('h2', _at(1, 20)),
          _turn('h3', _at(1, 21)),
        ]) {
          await other.append(r);
        }
        await seed([
          _turn('x1', _at(1, 19), subgoalId: 's0'),
          _turn('x2', _at(1, 20), subgoalId: 's0'),
          _turn('x3', _at(1, 21), subgoalId: 's0'),
          _turn('s1', _at(2), provenance: _supervised, positive: false),
          _turn('s2', _at(2, 10, 5), provenance: _supervised, positive: false),
        ]);
        final now = _turn(
          's3',
          _at(2, 10, 10),
          provenance: _supervised,
          positive: false,
        );
        expect(await service.checkAfter(uid: 'u1', turn: now), isEmpty);
      },
    );

    test('without enough home signals on the record the timetable is not '
        'read: since #219 almost every turn is recorded supervised', () async {
      await seed([
        _turn('h1', _at(1, 19)),
        _turn('h2', _at(1, 20)),
        _turn('s1', _at(2), provenance: _supervised, positive: false),
        _turn('s2', _at(2, 10, 5), provenance: _supervised, positive: false),
      ]);
      final now = _turn(
        's3',
        _at(2, 10, 10),
        provenance: _supervised,
        positive: false,
      );
      expect(await service.checkAfter(uid: 'u1', turn: now), isEmpty);
      expect(timetable.reads, 0);
    });

    test('a turn without a direct signal reads nothing', () async {
      final store0 = store.docs.length;
      final now = _turn('s3', _at(2), applied: const []);
      expect(await service.checkAfter(uid: 'u1', turn: now), isEmpty);
      expect(store.docs.length, store0);
      expect(timetable.reads, 0);
    });

    test(
      'a failure is swallowed: the student never hears of the check',
      () async {
        await seed([
          _turn('h1', _at(1, 19)),
          _turn('h2', _at(1, 20)),
          _turn('h3', _at(1, 21)),
          _turn('s1', _at(2), provenance: _supervised, positive: false),
          _turn('s2', _at(2, 10, 5), provenance: _supervised, positive: false),
        ]);
        timetable.fail = true;
        final now = _turn(
          's3',
          _at(2, 10, 10),
          provenance: _supervised,
          positive: false,
        );
        expect(await service.checkAfter(uid: 'u1', turn: now), isEmpty);
        expect(gapDocs(), isEmpty);
      },
    );
  });

  group('ProvenanceGap.fromEvent', () {
    test('reads its own event back, and nothing else', () {
      const gap = ProvenanceGap(
        subgoalId: 's1',
        loId: 'lo1',
        homeSignals: 6,
        homePositive: 6,
        supervisedSignals: 6,
        supervisedPositive: 1,
        severity: TurnSignalEventSeverity.strong,
      );
      final json = gap.toEvent().toJson();
      final back = ProvenanceGap.fromEvent(TurnSignalEvent.tryFromJson(json)!)!;
      expect(back.severity, TurnSignalEventSeverity.strong);
      expect(back.supervisedPositive, 1);
      expect(
        ProvenanceGap.fromEvent(
          TurnSignalEvent.of(TurnSignalEventKind.cascadeHalt),
        ),
        isNull,
      );
      expect(
        ProvenanceGap.fromEvent(
          const TurnSignalEvent(
            kind: TurnSignalEventKind.provenanceGap,
            severity: TurnSignalEventSeverity.audit,
            details: {'loId': 'lo1'},
          ),
        ),
        isNull,
      );
    });
  });
}
