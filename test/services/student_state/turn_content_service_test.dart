// #228 — the content of an oefening goes to `turn_content`: one doc per
// graded turn, with the turn record's id, under the student's partition,
// and a `ttl` that runs out at the end of the school year. Best-effort like
// the question bank: without the container, or when Cosmos fails or does
// not answer, nothing is thrown and nothing waits.
//
// #232 — a progress reset deletes it: the student's docs, all or one
// subgoal's, after the writes still on their way. Best-effort as well.

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

/// A stored doc of [uid] on [subgoalId], as far as a delete reads it.
Map<String, dynamic> _stored(String id, String uid, String subgoalId) => {
  'id': id,
  'uid': uid,
  'type': 'turn_content',
  'subgoalId': subgoalId,
};

/// [InMemoryCosmos], with the writes held until [open] and the deletes of
/// [goneIds] answered as Cosmos answers a doc whose `ttl` ran out between
/// the query and the delete.
class _HeldContainer implements CosmosContainer {
  _HeldContainer(this._store, {this.goneIds = const {}});

  final InMemoryCosmos _store;
  final Set<String> goneIds;
  final Completer<void> _gate = Completer<void>();

  void open() => _gate.complete();

  @override
  Future<Map<String, dynamic>> upsert(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    await _gate.future;
    return _store.container.upsert(doc, partitionKey: partitionKey);
  }

  @override
  Future<void> delete(String id, {required Object partitionKey}) async {
    if (goneIds.contains(id)) {
      throw CosmosException(
        404,
        'Entity with the specified id does not exist in the system.',
        code: 'NotFound',
      );
    }
    return _store.container.delete(id, partitionKey: partitionKey);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) => _store.container.query(
    sql,
    parameters: parameters,
    partitionKey: partitionKey,
    crossPartition: crossPartition,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

TurnContent _content({
  String id = 't-1',
  DateTime? at,
  String subgoalId = 's1',
}) => TurnContent(
  id: id,
  turnAt: at ?? _turnAt,
  subgoalId: subgoalId,
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

  group('a progress reset (#232)', () {
    setUp(() {
      store = InMemoryCosmos([
        _stored('t-1', 'u1', 's1'),
        _stored('t-2', 'u1', 's2'),
        _stored('t-3', 'u2', 's1'),
      ]);
    });

    test(
      'deletes every doc of the signed-in student, and only theirs',
      () async {
        await service().deleteAllForCurrentUser();
        expect(store.docs.keys, ['t-3']);
      },
    );

    test('of one subgoal deletes the docs of the student on it, and only '
        'those', () async {
      await service().deleteAllForSubgoal('s1');
      expect(store.docs.keys, ['t-2', 't-3']);
    });

    test('deletes nothing without a signed-in student', () async {
      uid = null;
      await service().deleteAllForCurrentUser();
      await service().deleteAllForSubgoal('s1');
      expect(store.docs.keys, ['t-1', 't-2', 't-3']);
    });

    test('also deletes a write that was still on its way: the delete waits '
        'for the writes queued before it', () async {
      final held = _HeldContainer(store);
      final s = service(container: held);

      unawaited(s.record(_content(id: 't-4', subgoalId: 's1')));
      final deleted = s.deleteAllForCurrentUser();
      held.open();
      await deleted;

      expect(store.docs.keys, ['t-3']);
    });

    test('skips a doc that is already gone and deletes the rest', () async {
      final held = _HeldContainer(store, goneIds: {'t-1'})..open();
      await service(container: held).deleteAllForCurrentUser();
      expect(store.docs.keys, ['t-1', 't-3']);
    });

    test('a failing delete is swallowed: nothing is thrown', () async {
      final failing = MockCosmosContainer();
      when(
        () => failing.query(
          any(),
          parameters: any(named: 'parameters'),
          partitionKey: any(named: 'partitionKey'),
          crossPartition: any(named: 'crossPartition'),
        ),
      ).thenThrow(CosmosException(503, 'Service unavailable'));
      final s = service(container: failing);
      await expectLater(s.deleteAllForCurrentUser(), completes);
      await expectLater(s.deleteAllForSubgoal('s1'), completes);
    });

    test('without the container it completes, and is tried even while the '
        'writes are left alone', () async {
      final missing = UnprovisionedCosmos('turn_content');
      final s = service(container: missing.container);

      await s.record(_content());
      final afterWrite = missing.requests.length;

      await expectLater(s.deleteAllForCurrentUser(), completes);
      expect(missing.requests.length, greaterThan(afterWrite));
    });
  });
}
