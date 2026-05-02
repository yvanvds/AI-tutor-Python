// 2.2 — Tests `ProgressService`. The service is a thin wrapper over a
// Cosmos container with composite doc-id `${uid}_${goalId}` and partition
// key = uid. We inject a `MockCosmosContainer` via the constructor and a
// `MockAuthService` via the locator (the service reads `currentUser.value
// .oid` to compute uid).
//
// Step 4 added a `progress_history` time-series container whose writes
// happen inside `upsert` whenever the persisted progress value actually
// changes. Tests inject a second `MockCosmosContainer` for that and pin
// down the change-detection rules and best-effort failure handling.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/locator.dart';
import '../../helpers/mocks.dart';

const _uid = 'oid-123';

void main() {
  late MockCosmosContainer container;
  late MockCosmosContainer history;
  late MockAuthService auth;
  late ValueNotifier<AccountIdentity?> currentUser;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    container = MockCosmosContainer();
    history = MockCosmosContainer();
    auth = MockAuthService();
    currentUser = ValueNotifier<AccountIdentity?>(
      const AccountIdentity(
        oid: _uid,
        displayName: 'Test',
        email: '',
        firstName: '',
        lastName: '',
        isTeacher: false,
      ),
    );
    when(() => auth.currentUser).thenReturn(currentUser);
    registerMock<AuthService>(auth);

    // Default stubs that most tests share. Individual groups override as
    // needed.
    when(
      () => container.read(
        any<String>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => container.upsert(
        any<Map<String, Object?>>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((_) async => <String, dynamic>{});
    when(
      () => history.create(
        any<Map<String, Object?>>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((_) async => <String, dynamic>{});
  });

  tearDown(() async {
    await resetLocator();
    currentUser.dispose();
  });

  ProgressService build() => ProgressService(
        container: container,
        historyContainer: history,
      );

  group('uid resolution', () {
    test('throws StateError when no user is signed in', () {
      currentUser.value = null;
      final svc = build();
      expect(() => svc.getAll(), throwsA(isA<StateError>()));
      expect(() => svc.upsert(Progress(goalID: 'g', progress: 0.5)),
          throwsA(isA<StateError>()));
      expect(() => svc.delete('g'), throwsA(isA<StateError>()));
      expect(() => svc.getByGoalId('g'), throwsA(isA<StateError>()));
      expect(() => svc.getHistoryByGoalId('g'),
          throwsA(isA<StateError>()));
      expect(() => svc.getAllHistory(), throwsA(isA<StateError>()));
    });
  });

  group('getAll', () {
    test('queries with the uid as both partition key and parameter, then maps '
        'rows to Progress', () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <Map<String, dynamic>>[
            {'goalId': 'g1', 'progress': 0.4},
            {'goalId': 'g2', 'progress': 1.0},
          ]);

      final out = await build().getAll();
      expect(out.map((p) => p.goalID).toList(), ['g1', 'g2']);
      expect(out.map((p) => p.progress).toList(), [0.4, 1.0]);

      final captured = verify(
        () => container.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: captureAny<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], contains('c.uid = @uid'));
      expect(captured[1], {'@uid': _uid});
      expect(captured[2], _uid);
    });
  });

  group('getByGoalId', () {
    test('reads with composite doc-id and uid partition, returns null on miss',
        () async {
      expect(await build().getByGoalId('g1'), isNull);
      verify(
        () => container.read('${_uid}_g1', partitionKey: _uid),
      ).called(1);
    });

    test('maps a doc to Progress on hit', () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {'goalId': 'g1', 'progress': 0.6});
      final p = await build().getByGoalId('g1');
      expect(p, isNotNull);
      expect(p!.goalID, 'g1');
      expect(p.progress, 0.6);
    });
  });

  group('upsert', () {
    test('builds a doc with composite id, uid + goalId fields, and partitions '
        'on uid', () async {
      await build().upsert(Progress(goalID: 'g1', progress: 0.5));

      final captured = verify(
        () => container.upsert(
          captureAny<Map<String, Object?>>(),
          partitionKey: captureAny<Object>(named: 'partitionKey'),
        ),
      ).captured;
      final doc = captured[0] as Map<String, Object?>;
      expect(doc['id'], '${_uid}_g1');
      expect(doc['uid'], _uid);
      expect(doc['goalId'], 'g1');
      expect(doc['progress'], 0.5);
      expect(captured[1], _uid);
    });
  });

  group('delete', () {
    test('deletes by composite id, partitions on uid', () async {
      when(
        () => container.delete(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async {});
      await build().delete('g1');
      verify(() => container.delete('${_uid}_g1', partitionKey: _uid))
          .called(1);
    });
  });

  group('history writes', () {
    test('writes a history sample when progress actually changes', () async {
      // No previous doc → progress changed from "nothing" to 0.5.
      await build().upsert(
        Progress(
          goalID: 'g1',
          progress: 0.5,
          difficulty: QuestionDifficulty.medium,
        ),
        quality: AnswerQuality.correct,
      );

      final captured = verify(
        () => history.create(
          captureAny<Map<String, Object?>>(),
          partitionKey: captureAny<Object>(named: 'partitionKey'),
        ),
      ).captured;
      final doc = captured[0] as Map<String, Object?>;
      expect(doc['uid'], _uid);
      expect(doc['goalId'], 'g1');
      expect(doc['progress'], 0.5);
      expect(doc['difficulty'], 'medium');
      expect(doc['quality'], 'correct');
      expect(doc['isWarmUp'], false);
      expect(doc['at'], isA<String>());
      expect(doc['id'], isA<String>());
      expect(captured[1], _uid);
    });

    test('omits the quality field when none was provided', () async {
      await build().upsert(Progress(goalID: 'g1', progress: 0.5));

      final captured = verify(
        () => history.create(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      final doc = captured[0] as Map<String, Object?>;
      expect(doc.containsKey('quality'), isFalse);
    });

    test('flags the sample as warm-up when isWarmUp is true', () async {
      await build().upsert(
        Progress(goalID: 'g1', progress: 0.4),
        quality: AnswerQuality.wrong,
        isWarmUp: true,
      );

      final captured = verify(
        () => history.create(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      final doc = captured[0] as Map<String, Object?>;
      expect(doc['isWarmUp'], true);
      expect(doc['quality'], 'wrong');
    });

    test('skips the history write when progress is unchanged', () async {
      // Pre-existing doc with same progress: idempotent upsert (recheck
      // recentAnswers / lastSessionAt etc.) should not produce a sample.
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {
            'goalId': 'g1',
            'progress': 0.5,
          });

      await build().upsert(
        Progress(goalID: 'g1', progress: 0.5),
        quality: AnswerQuality.correct,
      );

      verifyNever(
        () => history.create(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });

    test('skips the history write when recordHistory is false (root recompute)',
        () async {
      await build().upsert(
        Progress(goalID: 'root-1', progress: 0.42),
        recordHistory: false,
      );

      verifyNever(
        () => history.create(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
      // Pre-read is also skipped — nothing to compare against.
      verifyNever(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      );
    });

    test('history-write failure does not propagate from upsert', () async {
      when(
        () => history.create(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenThrow(
        CosmosException(500, 'history container down'),
      );

      // Must not throw — the user-visible progress write already succeeded.
      await build().upsert(Progress(goalID: 'g1', progress: 0.5));

      verify(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).called(1);
    });

    test('pre-read failure is swallowed: the main upsert still runs and '
        'a history sample is written (we prefer a possibly-redundant sample '
        'over a missed one when we cannot detect the delta)', () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenThrow(CosmosException(500, 'read failed'));

      // Should still complete without throwing.
      await build().upsert(Progress(goalID: 'g1', progress: 0.5));

      verify(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).called(1);
      verify(
        () => history.create(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).called(1);
    });
  });

  group('history reads', () {
    test('getHistoryByGoalId queries the uid + goalId, ordered by at ASC',
        () async {
      when(
        () => history.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <Map<String, dynamic>>[
            {
              'goalId': 'g1',
              'progress': 0.2,
              'difficulty': 'easy',
              'isWarmUp': false,
              'at': '2026-04-01T10:00:00.000Z',
            },
            {
              'goalId': 'g1',
              'progress': 0.4,
              'difficulty': 'easy',
              'isWarmUp': false,
              'at': '2026-04-02T10:00:00.000Z',
            },
          ]);

      final out = await build().getHistoryByGoalId('g1');
      expect(out, hasLength(2));
      expect(out.map((s) => s.progress).toList(), [0.2, 0.4]);

      final captured = verify(
        () => history.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: captureAny<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      final sql = captured[0] as String;
      expect(sql, contains('c.uid = @uid'));
      expect(sql, contains('c.goalId = @goalId'));
      expect(sql, contains('ORDER BY c.at ASC'));
      expect(captured[1], {'@uid': _uid, '@goalId': 'g1'});
      expect(captured[2], _uid);
    });

    test('getHistoryByGoalId honours since and limit', () async {
      when(
        () => history.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => const <Map<String, dynamic>>[]);

      final since = DateTime.utc(2026, 4, 1);
      await build().getHistoryByGoalId('g1', since: since, limit: 50);

      final captured = verify(
        () => history.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      final sql = captured[0] as String;
      final params = captured[1] as Map<String, Object?>;
      expect(sql, contains('c.at >= @since'));
      expect(sql, contains('SELECT TOP 50'));
      expect(params['@since'], since.toIso8601String());
    });

    test('getAllHistory omits the goalId clause and queries by uid only',
        () async {
      when(
        () => history.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => const <Map<String, dynamic>>[]);

      await build().getAllHistory();

      final captured = verify(
        () => history.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: captureAny<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      final sql = captured[0] as String;
      expect(sql, contains('c.uid = @uid'));
      expect(sql, isNot(contains('@goalId')));
      expect(captured[1], {'@uid': _uid});
      expect(captured[2], _uid);
    });
  });

  group('teacher-scoped reads', () {
    test('getAllProgress fans out cross-partition and groups by uid',
        () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
          crossPartition: any<bool>(named: 'crossPartition'),
        ),
      ).thenAnswer((_) async => <Map<String, dynamic>>[
            {'uid': 'u1', 'goalId': 'g1', 'progress': 0.5},
            {'uid': 'u1', 'goalId': 'g2', 'progress': 0.6},
            {'uid': 'u2', 'goalId': 'g1', 'progress': 0.1},
          ]);

      final out = await build().getAllProgress();
      expect(out.keys.toSet(), {'u1', 'u2'});
      expect(out['u1']!.map((p) => p.goalID).toList(), ['g1', 'g2']);
      expect(out['u2']!.map((p) => p.goalID).toList(), ['g1']);

      final captured = verify(
        () => container.query(
          captureAny<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
          crossPartition: captureAny<bool>(named: 'crossPartition'),
        ),
      ).captured;
      expect(captured[0], contains('SELECT * FROM c'));
      expect(captured[1], isTrue);
    });

    test('getProgressForUser scopes to the supplied uid', () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <Map<String, dynamic>>[
            {'goalId': 'g1', 'progress': 0.4},
          ]);

      final out = await build().getProgressForUser('other-uid');
      expect(out, hasLength(1));

      final captured = verify(
        () => container.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: captureAny<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], contains('c.uid = @uid'));
      expect(captured[1], {'@uid': 'other-uid'});
      expect(captured[2], 'other-uid');
    });

    test('getHistoryForUser scopes the history query to the supplied uid',
        () async {
      when(
        () => history.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => const <Map<String, dynamic>>[]);

      await build().getHistoryForUser('other-uid');

      final captured = verify(
        () => history.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: captureAny<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], contains('c.uid = @uid'));
      expect(captured[1], {'@uid': 'other-uid'});
      expect(captured[2], 'other-uid');
    });
  });
}
