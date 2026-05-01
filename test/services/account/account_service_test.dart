// 2.4 — Tests `AccountService`. Container is injected; auth and tutor are
// registered as locator mocks. The constructor immediately attaches a
// listener to AuthService.currentUser and (re)subscribes a polling stream
// when the user becomes non-null. To keep these tests pure-Dart and fast we
// keep the user null in setUp; tests that exercise the listener flip it
// explicitly and await the microtask queue so `_ensureProfile` has a chance
// to run.

import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/locator.dart';
import '../../helpers/mocks.dart';

const _uid = 'oid-abc';

AccountIdentity _identity({String oid = _uid, String firstName = 'Test'}) =>
    AccountIdentity(
      oid: oid,
      displayName: '$firstName User',
      email: '$oid@example.com',
      firstName: firstName,
      lastName: 'User',
      isTeacher: false,
    );

void main() {
  late MockCosmosContainer container;
  late MockAuthService auth;
  late MockTutorService tutor;
  late ValueNotifier<AccountIdentity?> currentUser;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    container = MockCosmosContainer();
    auth = MockAuthService();
    tutor = MockTutorService();
    currentUser = ValueNotifier<AccountIdentity?>(null);

    when(() => auth.currentUser).thenReturn(currentUser);
    when(() => tutor.initializeSession(force: any<bool>(named: 'force')))
        .thenAnswer((_) async {});

    registerMock<AuthService>(auth);
    registerMock<TutorService>(tutor);
  });

  tearDown(() async {
    await resetLocator();
    currentUser.dispose();
  });

  AccountService build() => AccountService(container: container);

  group('getAccount', () {
    test('returns null when the doc is missing', () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => null);

      final svc = build();
      expect(await svc.getAccount('missing'), isNull);
      verify(() => container.read('missing', partitionKey: 'missing'))
          .called(1);
    });

    test('maps a doc to an Account on hit', () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {
            'id': _uid,
            'uid': _uid,
            'firstName': 'Yvan',
            'lastName': 'Vds',
            'email': 'yvan@example.com',
            'targetGoal': 'tg',
            'mayUseGlobalKey': true,
          });

      final acc = await build().getAccount(_uid);
      expect(acc, isNotNull);
      expect(acc!.uid, _uid);
      expect(acc.firstName, 'Yvan');
      expect(acc.mayUseGlobalKey, isTrue);
    });
  });

  group('upsertAccount', () {
    test('on first insert stamps createdAt + updatedAt and defaults '
        'mayUseGlobalKey/targetGoal to neutrals', () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => null);
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().upsertAccount(
        uid: _uid,
        firstName: 'Yvan',
        lastName: 'Vds',
        email: 'yvan@example.com',
      );

      final captured = verify(
        () => container.upsert(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as Map<String, Object?>;
      expect(captured['id'], _uid);
      expect(captured['uid'], _uid);
      expect(captured['firstName'], 'Yvan');
      expect(captured['email'], 'yvan@example.com');
      expect(captured['mayUseGlobalKey'], false);
      expect(captured['targetGoal'], '');
      expect(captured['createdAt'], isA<String>());
      expect(captured['updatedAt'], isA<String>());
    });

    test('preserves existing mayUseGlobalKey, targetGoal, createdAt on update',
        () async {
      const existingCreatedAt = '2024-01-01T00:00:00.000Z';
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {
            'id': _uid,
            'uid': _uid,
            'mayUseGlobalKey': true,
            'targetGoal': 'goal-x',
            'createdAt': existingCreatedAt,
          });
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().upsertAccount(
        uid: _uid,
        firstName: 'Y',
        lastName: 'V',
        email: 'y@example.com',
      );

      final captured = verify(
        () => container.upsert(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as Map<String, Object?>;
      expect(captured['mayUseGlobalKey'], true);
      expect(captured['targetGoal'], 'goal-x');
      expect(captured['createdAt'], existingCreatedAt);
      // updatedAt is fresh, distinct from createdAt.
      expect(captured['updatedAt'], isNot(existingCreatedAt));
    });
  });

  group('setTargetGoal', () {
    test('throws StateError when no user is signed in', () {
      currentUser.value = null;
      expect(
        () => build().setTargetGoal(targetGoal: 'g'),
        throwsA(isA<StateError>()),
      );
    });

    test('reads, patches targetGoal, refreshes updatedAt, replaces', () async {
      currentUser.value = _identity();
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {
            'id': _uid,
            'uid': _uid,
            'targetGoal': 'old',
          });
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      final svc = build();
      // Drain any microtasks the constructor's listener spawned (it queued
      // _ensureProfile but we don't care about that here).
      await Future<void>.delayed(Duration.zero);
      // Reset interaction counters so we measure only setTargetGoal's effects.
      clearInteractions(container);
      // Re-stub after clearInteractions wiped the stubs too.
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {
            'id': _uid,
            'uid': _uid,
            'targetGoal': 'old',
          });
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await svc.setTargetGoal(targetGoal: 'new-goal');

      final captured = verify(
        () => container.replace(
          captureAny<String>(),
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], _uid);
      final doc = captured[1] as Map<String, Object?>;
      expect(doc['targetGoal'], 'new-goal');
      expect(doc['updatedAt'], isA<String>());
    });
  });

  group('setMayUseGlobalKey', () {
    test('patches mayUseGlobalKey for the requested uid', () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {
            'id': _uid,
            'uid': _uid,
          });
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().setMayUseGlobalKey(uid: _uid, value: true);

      final captured = verify(
        () => container.replace(
          captureAny<String>(),
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], _uid);
      expect((captured[1] as Map)['mayUseGlobalKey'], true);
    });

    test('silently no-ops when the doc is missing (no replace fired)',
        () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => null);

      await build().setMayUseGlobalKey(uid: 'gone', value: true);
      verifyNever(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });
  });

  group('auth listener — _ensureProfile', () {
    test('does not call upsert when an account doc already exists', () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid});

      build();
      currentUser.value = _identity();
      // Let the unawaited(_ensureProfile(...)) run.
      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });

    test('calls upsert (creating the profile) when no account doc exists',
        () async {
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => null);
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      build();
      currentUser.value = _identity(firstName: 'Yvan');
      await Future<void>.delayed(Duration.zero);
      // _ensureProfile → getAccount (read) → upsertAccount (read again, then upsert).
      // We only care that ONE upsert with the right firstName landed.
      final upserts = verify(
        () => container.upsert(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      expect(upserts, hasLength(1));
      expect((upserts.single as Map)['firstName'], 'Yvan');
    });

    test('signing out (identity → null) clears currentAccount', () async {
      // Start with no user, then go non-null briefly, then back to null.
      when(
        () => container.read(any<String>(),
            partitionKey: any<Object>(named: 'partitionKey')),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid});

      final svc = build();
      currentUser.value = _identity();
      await Future<void>.delayed(Duration.zero);

      currentUser.value = null;
      expect(svc.currentAccount.value, isNull);
    });
  });
}
