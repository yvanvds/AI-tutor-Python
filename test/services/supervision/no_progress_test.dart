// The "stuck" alert for the teacher during the lesson (#229): long on the
// active subgoal without progress, with mostly wrong answers, is a strong
// teacher-only event — once per session and subgoal — with thresholds
// calibrated on two classes' turn history.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/no_progress.dart';
import 'package:ai_tutor_python/services/tutor/policy_constants.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _wrong = AnswerQuality.wrong;
const _partial = AnswerQuality.partial;
const _right = AnswerQuality.correct;

/// [minutes] (and [seconds]) after 09:00 UTC on 2 October 2026.
DateTime _t(int minutes, [int seconds = 0]) => DateTime.utc(
  2026,
  10,
  2,
  9,
).add(Duration(minutes: minutes, seconds: seconds));

int _ids = 0;

/// A graded answer on [subgoalId] asking [lo]. [mastered] are the LOs of
/// the subgoal mastered after it; every LO of [los] has a status, at
/// [mean].
PersistedTurnRecord _answer(
  DateTime at, {
  AnswerQuality quality = _wrong,
  String subgoalId = 's1',
  String lo = 'lo1',
  bool followUp = false,
  bool warmUp = false,
  bool recheck = false,
  bool advanced = false,
  Set<String> mastered = const {},
  List<String> los = const ['lo1', 'lo2'],
  double mean = 0.42,
  QuestionDifficulty calibration = QuestionDifficulty.medium,
  String? id,
}) => PersistedTurnRecord(
  id: id ?? 'a${_ids++}',
  turnAt: at,
  subgoalId: subgoalId,
  targetLOIds: [lo],
  questionType: 'completeCodeQuestion',
  difficulty: QuestionDifficulty.medium,
  isFollowUp: followUp,
  chainDepth: followUp ? 1 : 0,
  isWarmUp: warmUp,
  isRecheck: recheck,
  activeSubgoalId: warmUp || recheck ? 's1' : null,
  selectionReason: null,
  overallQuality: quality,
  loSignals: const [],
  hadFallback: false,
  appliedSignals: const [],
  calibrationBefore: calibration,
  calibrationAfter: calibration,
  subgoalProgressAfter: 0.0,
  loStatusAfter: [
    for (final id in los)
      TurnLoStatus(
        loId: id,
        mean: mean,
        evidence: 6,
        mastered: mastered.contains(id),
        stuck: false,
      ),
  ],
  subgoalAdvanced: advanced,
);

/// Answers on `s1` at [minutes], with [qualities] in turn (the last one
/// repeated when it runs out).
List<PersistedTurnRecord> _run(
  List<int> minutes, {
  List<AnswerQuality> qualities = const [_wrong],
  String subgoalId = 's1',
}) => [
  for (final (i, m) in minutes.indexed)
    _answer(
      _t(m),
      subgoalId: subgoalId,
      quality: qualities[i < qualities.length ? i : qualities.length - 1],
    ),
];

void main() {
  group('the thresholds', () {
    test('as calibrated on the turn history up to 2026-10-04', () {
      expect(PolicyConstants.noProgressMinMinutes, 25);
      expect(PolicyConstants.noProgressMinBadShare, 0.5);
      expect(PolicyConstants.noProgressWindow, 10);
      expect(PolicyConstants.noProgressMinAnswers, 6);
      expect(PolicyConstants.noProgressSessionGap, const Duration(minutes: 30));
    });
  });

  group('detectNoProgress', () {
    test('25 minutes without progress and half of the last answers not '
        'right: stuck', () {
      final records = _run(
        [0, 5, 10, 15, 20, 25],
        qualities: [_wrong, _right, _wrong, _right, _wrong, _right],
      );

      final stuck = detectNoProgress(records)!;

      expect(stuck.subgoalId, 's1');
      expect(stuck.since, _t(0));
      expect(stuck.minutes, 25);
      expect(stuck.oefeningen, 6);
      expect(stuck.answers, 6);
      expect(stuck.notRight, 3);
      expect(stuck.calibration, QuestionDifficulty.medium);
      expect(stuck.loId, 'lo1');
      expect(stuck.mean, 0.42);
    });

    test('a minute short of 25 is not long enough', () {
      final records = [
        ..._run([0, 5, 10, 15, 20]),
        _answer(_t(24, 59)),
      ];
      expect(detectNoProgress(records), isNull);
    });

    test('fewer than six answers is too little to go on', () {
      expect(detectNoProgress(_run([0, 10, 20, 30, 40])), isNull);
      expect(detectNoProgress(_run([0, 10, 20, 30, 40, 45])), isNotNull);
    });

    test('less than half not right is not stuck; partly right is not '
        'right', () {
      expect(
        detectNoProgress(
          _run(
            [0, 5, 10, 15, 20, 25, 30],
            qualities: [_wrong, _right, _wrong, _right, _wrong, _right, _right],
          ),
        ),
        isNull,
        reason: '3 of 7',
      );
      final stuck = detectNoProgress(
        _run(
          [0, 5, 10, 15, 20, 25],
          qualities: [_partial, _right, _partial, _right, _partial, _right],
        ),
      );
      expect(stuck?.notRight, 3);
    });

    test('only the last ten answers count', () {
      // Fourteen answers: four wrong, then four wrong among ten. Over all
      // fourteen that is 8 of 14; over the last ten 4 of 10.
      final records = _run(
        [for (var i = 0; i < 14; i++) i * 2],
        qualities: [
          _wrong, _wrong, _wrong, _wrong, //
          _right, _wrong, _right, _wrong, _right, //
          _wrong, _right, _wrong, _right, _right,
        ],
      );
      expect(detectNoProgress(records), isNull);

      // One more wrong: the right one at the front drops out, 5 of 10.
      final stuck = detectNoProgress([...records, _answer(_t(28))])!;
      expect(stuck.answers, 10);
      expect(stuck.notRight, 5);
      expect(stuck.oefeningen, 15);
    });

    test('follow-ups count as answers, not as oefeningen', () {
      final records = [
        _answer(_t(0)),
        _answer(_t(2), followUp: true),
        _answer(_t(8)),
        _answer(_t(10), followUp: true),
        _answer(_t(18)),
        _answer(_t(20), followUp: true),
        _answer(_t(26)),
      ];
      final stuck = detectNoProgress(records)!;
      expect(stuck.answers, 7);
      expect(stuck.oefeningen, 4);
    });

    test('an LO newly mastered starts the clock again; that answer is '
        'progress, not one of the answers since', () {
      final records = [
        for (final m in [0, 3, 6, 9]) _answer(_t(m)),
        _answer(_t(10), quality: _right, mastered: {'lo2'}),
        for (final m in [13, 16, 19, 22, 25, 30])
          _answer(_t(m), mastered: {'lo2'}),
      ];
      expect(detectNoProgress(records), isNull, reason: '20 minutes since');

      final stuck = detectNoProgress([
        ...records,
        _answer(_t(35), mastered: {'lo2'}),
      ])!;
      expect(stuck.since, _t(10));
      expect(stuck.minutes, 25);
      expect(stuck.answers, 7);
      expect(stuck.oefeningen, 7);
    });

    test('an LO that slips under the bar and comes back is not new', () {
      final records = [
        _answer(_t(0), mastered: {'lo2'}),
        _answer(_t(5)),
        _answer(_t(10), mastered: {'lo2'}),
        _answer(_t(15), mastered: {'lo2'}),
        _answer(_t(20), mastered: {'lo2'}),
        _answer(_t(25), mastered: {'lo2'}),
      ];
      expect(detectNoProgress(records)?.since, _t(0));
    });

    test('a subgoal advance starts the clock again', () {
      final records = [
        ..._run([0, 5]),
        _answer(_t(10), quality: _right, advanced: true),
        ..._run([15, 20, 25, 30, 33, 34]),
      ];
      expect(detectNoProgress(records), isNull, reason: '24 minutes since');
      expect(detectNoProgress([...records, _answer(_t(35))])?.since, _t(10));
    });

    test('the clock starts with the first answer on the subgoal after '
        'another one', () {
      final records = [
        ..._run([0, 5, 10, 15], subgoalId: 's2'),
        ..._run([20, 25, 30, 35, 40, 44]),
      ];
      expect(detectNoProgress(records), isNull, reason: '24 minutes on s1');

      final stuck = detectNoProgress([...records, _answer(_t(45))])!;
      expect(stuck.since, _t(20));
      expect(stuck.answers, 7);

      // Back on s1 after a while on s2: again from the first answer.
      final back = [
        ..._run([0, 5, 10, 15, 20]),
        ..._run([22], subgoalId: 's2'),
        ..._run([24, 30, 36, 42, 48]),
      ];
      expect(detectNoProgress(back), isNull);
      expect(detectNoProgress([...back, _answer(_t(49))])?.since, _t(24));
    });

    test('a pause longer than 30 minutes starts a new session; 30 minutes '
        'does not', () {
      final paused = [
        ..._run([0, 5, 10]),
        ..._run([41, 46, 51, 56, 61]),
      ];
      expect(detectNoProgress(paused), isNull);
      expect(detectNoProgress([...paused, _answer(_t(66))])?.since, _t(41));

      final notPaused = [
        ..._run([0, 5, 10]),
        ..._run([40]),
      ];
      expect(detectNoProgress(notPaused)?.since, isNull);
      expect(
        detectNoProgress([...notPaused, _answer(_t(41)), _answer(_t(42))])
            ?.since,
        _t(0),
      );
    });

    test('warm-up reviews and rechecks are about another subgoal: they '
        'neither count nor end the work on this one', () {
      final records = [
        ..._run([0, 5, 10]),
        _answer(_t(12), subgoalId: 's0', warmUp: true, quality: _right),
        _answer(_t(14), subgoalId: 's0', recheck: true, quality: _right),
        _answer(_t(16), quality: _right),
        ..._run([20, 25]),
      ];
      final stuck = detectNoProgress(records)!;
      expect(stuck.since, _t(0));
      expect(stuck.answers, 6);
      expect(stuck.notRight, 5);
    });

    test('the LO asked most since the clock started, the one asked last of '
        'two asked as often, with its μ after the last answer', () {
      final records = [
        for (final (i, lo) in [
          'lo1',
          'lo2',
          'lo1',
          'lo2',
          'lo2',
          'lo1',
        ].indexed)
          _answer(_t(i * 5), lo: lo, mean: 0.69),
      ];
      final stuck = detectNoProgress(records)!;
      expect(stuck.loId, 'lo1');
      expect(stuck.mean, 0.69);

      final lo2 = detectNoProgress([...records, _answer(_t(26), lo: 'lo2')])!;
      expect(lo2.loId, 'lo2');
    });

    test('the level after the last answer', () {
      final records = [
        ..._run([0, 5, 10, 15, 20]),
        _answer(_t(25), calibration: QuestionDifficulty.easy),
      ];
      expect(detectNoProgress(records)?.calibration, QuestionDifficulty.easy);
    });

    test('an answer that made progress is not stuck', () {
      final records = [
        ..._run([0, 5, 10, 15, 20]),
        _answer(_t(25), quality: _right, mastered: {'lo1'}),
      ];
      expect(detectNoProgress(records), isNull);
    });
  });

  group('sessionStartOf', () {
    test('the first answer after the last pause of more than 30 minutes', () {
      expect(sessionStartOf(_run([0, 5, 40, 70, 100])), _t(40));
      expect(sessionStartOf(_run([0, 30, 60])), _t(0));
      expect(sessionStartOf(const []), isNull);
    });

    test('warm-ups and audit records are not answers', () {
      expect(
        sessionStartOf([
          _answer(_t(0), subgoalId: 's0', warmUp: true),
          ..._run([40, 45]),
        ]),
        _t(40),
      );
    });
  });

  group('NoProgress event', () {
    test('strong, and read back as written', () {
      final stuck = NoProgress(
        subgoalId: 's1',
        since: _t(0),
        minutes: 33,
        oefeningen: 9,
        answers: 10,
        notRight: 7,
        calibration: QuestionDifficulty.hard,
        loId: 'lo1',
        mean: 0.69,
      );
      final event = stuck.toEvent();
      expect(event.kind, TurnSignalEventKind.noProgress);
      expect(event.severity, TurnSignalEventSeverity.strong);
      expect(event.details, {
        'subgoalId': 's1',
        'since': '2026-10-02T09:00:00.000Z',
        'minutes': 33,
        'oefeningen': 9,
        'answers': 10,
        'notRight': 7,
        'loId': 'lo1',
        'mean': 0.69,
        'calibration': 'hard',
      });

      final back = NoProgress.fromEvent(
        TurnSignalEvent.tryFromJson(event.toJson())!,
      )!;
      expect(back.subgoalId, 's1');
      expect(back.since, _t(0));
      expect(back.minutes, 33);
      expect(back.oefeningen, 9);
      expect(back.answers, 10);
      expect(back.notRight, 7);
      expect(back.calibration, QuestionDifficulty.hard);
      expect(back.loId, 'lo1');
      expect(back.mean, 0.69);
    });

    test('without an LO, none is written or read', () {
      final event = NoProgress(
        subgoalId: 's1',
        since: _t(0),
        minutes: 25,
        oefeningen: 6,
        answers: 6,
        notRight: 6,
        calibration: QuestionDifficulty.medium,
      ).toEvent();
      expect(event.details.containsKey('loId'), isFalse);
      expect(event.details.containsKey('mean'), isFalse);
      expect(NoProgress.fromEvent(event)?.loId, isNull);
    });

    test('another kind, or details it cannot read, is no alert', () {
      expect(
        NoProgress.fromEvent(
          TurnSignalEvent.of(
            TurnSignalEventKind.singleLoDeadlock,
            details: {'subgoalId': 's1'},
          ),
        ),
        isNull,
      );
      expect(
        NoProgress.fromEvent(
          TurnSignalEvent.of(
            TurnSignalEventKind.noProgress,
            details: {'subgoalId': 's1', 'minutes': 25},
          ),
        ),
        isNull,
      );
    });
  });

  group('NoProgressService.checkAfter', () {
    late InMemoryCosmos store;
    late TurnHistoryService turns;
    late NoProgressService service;

    setUp(() {
      store = InMemoryCosmos();
      turns = TurnHistoryService(
        container: store.container,
        getUid: () => 'u1',
      );
      service = NoProgressService(turns: turns);
    });

    List<Map<String, dynamic>> alertDocs() => [
      for (final d in store.docs.values)
        if ((d['signalEvents'] as List?)?.any(
              (e) => (e as Map)['kind'] == 'noProgress',
            ) ??
            false)
          d,
    ];

    Future<void> seed(List<PersistedTurnRecord> records) async {
      for (final r in records) {
        await turns.append(r);
      }
    }

    test('writes a strong audit record on the subgoal with what the teacher '
        'reads — the answer in hand counts, whether or not its write has '
        'landed', () async {
      await seed(_run([0, 5, 10, 15, 20]));
      final now = _answer(_t(25), mean: 0.69);

      final alert = await service.checkAfter(uid: 'u1', turn: now);

      expect(alert, isNotNull);
      final doc = alertDocs().single;
      expect(doc['uid'], 'u1');
      expect(doc['subgoalId'], 's1');
      expect(doc['questionType'], '', reason: 'an audit record, no oefening');
      final event = (doc['signalEvents'] as List).single as Map;
      expect(event['severity'], 'strong');
      expect(event['details'], {
        'subgoalId': 's1',
        'since': '2026-10-02T09:00:00.000Z',
        'minutes': 25,
        'oefeningen': 6,
        'answers': 6,
        'notRight': 6,
        'loId': 'lo1',
        'mean': 0.69,
        'calibration': 'medium',
      });
      // It drives the badge.
      expect(await turns.countStrongUnacknowledgedFor('u1'), 1);
    });

    test('once per session and subgoal', () async {
      await seed(_run([0, 5, 10, 15, 20]));
      final first = _answer(_t(25));
      expect(await service.checkAfter(uid: 'u1', turn: first), isNotNull);
      await turns.append(first);

      final next = _answer(_t(28));
      await turns.append(next);
      expect(await service.checkAfter(uid: 'u1', turn: next), isNull);

      // Not even from another app on the same student: the record is read.
      final otherApp = NoProgressService(turns: turns);
      expect(await otherApp.checkAfter(uid: 'u1', turn: next), isNull);
      expect(alertDocs(), hasLength(1));
    });

    test('not twice for two answers in quick succession', () async {
      await seed(_run([0, 5, 10, 15, 20]));
      final first = _answer(_t(25));
      final second = _answer(_t(25, 30));
      await seed([first, second]);

      final results = await Future.wait([
        service.checkAfter(uid: 'u1', turn: first),
        service.checkAfter(uid: 'u1', turn: second),
      ]);

      expect(results.whereType<NoProgress>(), hasLength(1));
      expect(alertDocs(), hasLength(1));
    });

    test('a new session may raise it again', () async {
      await seed(_run([0, 5, 10, 15, 20]));
      final first = _answer(_t(25));
      await seed([first]);
      expect(await service.checkAfter(uid: 'u1', turn: first), isNotNull);

      // A pause of more than half an hour, then stuck again.
      await seed(_run([60, 65, 70, 75, 80]));
      final again = _answer(_t(85));
      await seed([again]);
      final alert = await service.checkAfter(uid: 'u1', turn: again);

      expect(alert?.since, _t(60));
      expect(alertDocs(), hasLength(2));
    });

    test('on another subgoal in the same session it is a new alert', () async {
      await seed(_run([0, 5, 10, 15, 20]));
      final first = _answer(_t(25));
      await seed([first]);
      expect(await service.checkAfter(uid: 'u1', turn: first), isNotNull);

      await seed(_run([26, 30, 35, 40, 45], subgoalId: 's2'));
      final onS2 = _answer(_t(51), subgoalId: 's2');
      await seed([onS2]);
      final alert = await service.checkAfter(uid: 'u1', turn: onS2);

      expect(alert?.subgoalId, 's2');
      expect(
        alertDocs().map((d) => d['subgoalId']),
        unorderedEquals(['s1', 's2']),
      );
    });

    test('a warm-up review or a recheck is not checked; the next answer on '
        'the active subgoal is', () async {
      await seed(_run([0, 5, 10, 15, 20, 25]));
      final warmUp = _answer(_t(26), subgoalId: 's0', warmUp: true);
      final recheck = _answer(_t(27), subgoalId: 's0', recheck: true);
      await seed([warmUp, recheck]);

      expect(await service.checkAfter(uid: 'u1', turn: warmUp), isNull);
      expect(await service.checkAfter(uid: 'u1', turn: recheck), isNull);
      expect(alertDocs(), isEmpty);

      final next = _answer(_t(28));
      expect(await service.checkAfter(uid: 'u1', turn: next), isNotNull);
    });

    test('a session longer than the read window counts from the start of '
        'the read', () async {
      expect(PolicyConstants.noProgressLookback, const Duration(hours: 4));
      // Five hours without a pause, an answer every 20 minutes.
      await seed(_run([for (var m = -300; m <= 0; m += 20) m]));
      final now = _answer(_t(20));

      final alert = await service.checkAfter(uid: 'u1', turn: now);

      // Read from four hours before the answer on: 20 - 240 = -220.
      expect(alert?.since, _t(-220));
      expect(alert?.minutes, 240);
    });

    test('silent when the read fails', () async {
      final failing = NoProgressService(
        turns: TurnHistoryService(
          container: _ThrowingContainer(),
          getUid: () => 'u1',
        ),
      );
      expect(
        await failing.checkAfter(uid: 'u1', turn: _answer(_t(25))),
        isNull,
      );
    });
  });
}

/// A container whose every call fails, as an unreachable Cosmos does.
class _ThrowingContainer extends Fake implements CosmosContainer {}
