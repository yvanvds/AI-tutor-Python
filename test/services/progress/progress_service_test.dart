// 2.2 — Tests `ProgressService`. The service is a thin wrapper over a
// Cosmos container with composite doc-id `${uid}_${goalId}` and partition
// key = uid. We inject a `MockCosmosContainer` via the constructor and a
// `MockAuthService` via the locator (the service reads `currentUser.value
// .oid` to compute uid).

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
  late MockAuthService auth;
  late ValueNotifier<AccountIdentity?> currentUser;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    container = MockCosmosContainer();
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
  });

  tearDown(() async {
    await resetLocator();
    currentUser.dispose();
  });

  ProgressService build() => ProgressService(container: container);

  group('uid resolution', () {
    test('throws StateError when no user is signed in', () {
      currentUser.value = null;
      final svc = build();
      expect(() => svc.getAll(), throwsA(isA<StateError>()));
      expect(() => svc.upsert(Progress(goalID: 'g', progress: 0.5)),
          throwsA(isA<StateError>()));
      expect(() => svc.delete('g'), throwsA(isA<StateError>()));
      expect(() => svc.getByGoalId('g'), throwsA(isA<StateError>()));
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
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => null);
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
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

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
}
