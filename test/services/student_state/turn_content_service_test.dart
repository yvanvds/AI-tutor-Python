// #228 — the content of an oefening goes to `turn_content`: one doc per
// graded turn, with the turn record's id, under the student's partition,
// and a `ttl` that runs out at the end of the school year. Best-effort like
// the question bank: without the container, or when Cosmos fails or does
// not answer, nothing is thrown and nothing waits.

import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/keep_until.dart';
import 'package:ai_tutor_python/services/student_state/turn_content.dart';
import 'package:ai_tutor_python/services/student_state/turn_content_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/mocks.dart';
import '../../helpers/unprovisioned_cosmos.dart';

final DateTime _turnAt = DateTime.utc(2026, 10, 2, 9, 15);

TurnContent _content({String id = 't-1', DateTime? at}) => TurnContent(
  id: id,
  turnAt: at ?? _turnAt,
  subgoalId: 's1',
  questionType: 'mcQuestion',
  isFollowUp: false,
  question: const TurnContentQuestion(
    text: 'Wat drukt print(1 + 1) af?',
    code: 'print(1 + 1)',
    options: ['11', '2', 'Error'],
    correctOption: '2',
    questionId: 's1_abc123',
  ),
  answer: const TurnContentAnswer(picked: '11'),
  feedback: 'Nee: 1 + 1 is een som.',
  rawSignals: const [
    TurnLoSignal(
      subgoalId: 's1',
      loId: 'lo-1',
      signal: 'negative',
      strength: 'moderate',
    ),
    TurnLoSignal(
      subgoalId: 's9',
      loId: 'lo-x',
      signal: 'positive',
      strength: 'weak',
    ),
  ],
  droppedSignals: const [
    TurnDroppedSignal(
      subgoalId: 's9',
      loId: 'lo-x',
      signal: 'positive',
      strength: 'weak',
      reason: 'outOfScope',
    ),
  ],
  context: const TurnContentContext(
    activeRootId: 'r1',
    activeSubgoalId: 's1',
    selectedRootId: 'r1',
    selectedChildId: 's1',
    sessionStart: 'continueLearningPath',
  ),
  hintCount: 2,
  clientVersion: '2.8.0+25',
);

void main() {
  late DateTime now;
  late InMemoryCosmos store;
  String? uid;

  setUp(() {
    now = DateTime.utc(2026, 10, 2, 9, 15, 3);
    store = InMemoryCosmos();
    uid = 'u1';
  });

  TurnContentService service({CosmosContainer? container}) =>
      TurnContentService(
        container: container ?? store.container,
        getUid: () => uid,
        now: () => now,
      );

  test('writes one doc with the turn record\'s id under the student\'s '
      'partition: question, answer, feedback, the grader\'s signals with '
      'the dropped ones and why, the context and the hints', () async {
    await service().record(_content());

    final doc = store['t-1']!;
    expect(doc['uid'], 'u1');
    expect(doc['type'], 'turn_content');
    expect(doc['turnAt'], '2026-10-02T09:15:00.000Z');
    expect(doc['subgoalId'], 's1');
    expect(doc['questionType'], 'mcQuestion');
    expect(doc['isFollowUp'], isFalse);
    expect(doc['question'], {
      'text': 'Wat drukt print(1 + 1) af?',
      'code': 'print(1 + 1)',
      'options': ['11', '2', 'Error'],
      'correctOption': '2',
      'questionId': 's1_abc123',
    });
    expect(doc['answer'], {'picked': '11'});
    expect(doc['feedback'], 'Nee: 1 + 1 is een som.');
    expect(doc['rawSignals'], hasLength(2));
    expect(doc['droppedSignals'], [
      {
        'subgoalId': 's9',
        'loId': 'lo-x',
        'signal': 'positive',
        'strength': 'weak',
        'reason': 'outOfScope',
      },
    ]);
    expect(doc['context'], {
      'activeRootId': 'r1',
      'activeSubgoalId': 's1',
      'selectedRootId': 'r1',
      'selectedChildId': 's1',
      'preferredRootId': null,
      'preferredChildId': null,
      'sessionStart': 'continueLearningPath',
    });
    expect(doc['hintCount'], 2);
    expect(doc['clientVersion'], '2.8.0+25');
  });

  test('keeps it until 1 July after the turn, midnight Belgian time: the '
      'ttl is the seconds from the write until then', () async {
    await service().record(_content());

    final doc = store['t-1']!;
    final until = DateTime.utc(2027, 6, 30, 22);
    expect(doc['keepUntil'], until.toIso8601String());
    expect(doc['ttl'], until.difference(now).inSeconds);
  });

  test('keeps it until the school\'s own day when config sets one', () async {
    await service().record(_content(), keepUntil: const KeepUntil(12, 20));

    final doc = store['t-1']!;
    expect(doc['keepUntil'], '2026-12-19T23:00:00.000Z');
    expect(
      doc['ttl'],
      DateTime.utc(2026, 12, 19, 23).difference(now).inSeconds,
    );
  });

  test(
    'the ttl is counted at the write, not when the turn was graded',
    () async {
      // A write that lands a minute later is kept a minute less: Cosmos
      // counts from the write.
      now = now.add(const Duration(minutes: 1));
      await service().record(_content());
      expect(
        store['t-1']!['ttl'],
        DateTime.utc(2027, 6, 30, 22).difference(now).inSeconds,
      );
    },
  );

  test('writes nothing without a signed-in student', () async {
    uid = null;
    await service().record(_content());
    expect(store.docs, isEmpty);
  });

  test('writes land in the order they were made', () async {
    final s = service();
    unawaited(s.record(_content(id: 't-1')));
    unawaited(s.record(_content(id: 't-2')));
    await s.idle;
    expect(store.docs.keys, ['t-1', 't-2']);
  });

  test('a failing write is swallowed: nothing is thrown', () async {
    final failing = MockCosmosContainer();
    when(() => failing.upsert(any(), partitionKey: any(named: 'partitionKey')))
        .thenThrow(CosmosException(503, 'Service unavailable'));
    await expectLater(
      service(container: failing).record(_content()),
      completes,
    );
  });

  group('without a `turn_content` container', () {
    test('the write completes without throwing, and the container is left '
        'alone for a while before it is tried again', () async {
      final missing = UnprovisionedCosmos('turn_content');
      final s = service(container: missing.container);

      await expectLater(s.record(_content(id: 't-1')), completes);
      final afterFirst = missing.requests.length;
      expect(afterFirst, greaterThan(0));

      await s.record(_content(id: 't-2'));
      expect(
        missing.requests.length,
        afterFirst,
        reason: 'within the back-off nothing is sent',
      );

      now = now.add(kTurnContentRetryAfter);
      await s.record(_content(id: 't-3'));
      expect(missing.requests.length, greaterThan(afterFirst));
    });
  });
}
