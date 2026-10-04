// 2.4 — Tests `AccountService`. Container is injected; auth is wired via
// a controlled AuthService subclass registered in a ProviderContainer.
// The Notifier immediately attaches a listener to authServiceProvider and
// (re)subscribes a polling stream when the user becomes non-null. To keep
// these tests pure-Dart and fast we keep the user null in setUp; tests that
// exercise the listener flip it explicitly and await the microtask queue so
// `_ensureProfile` has a chance to run.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

/// Controlled AuthService that allows tests to set the auth state directly.
class _ControlledAuth extends AuthService {
  @override
  AccountIdentity? build() => null;
  void set(AccountIdentity? v) => state = v;
}

void main() {
  late MockCosmosContainer container;
  late ProviderContainer pc;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    container = MockCosmosContainer();
    pc = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith(_ControlledAuth.new),
        accountServiceProvider.overrideWith(
          () => AccountService(container: container),
        ),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
  });

  AccountService build() => pc.read(accountServiceProvider.notifier);

  group('getAccount', () {
    test('returns null when the doc is missing', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => null);

      final svc = build();
      expect(await svc.getAccount('missing'), isNull);
      verify(() => container.read('missing', partitionKey: 'missing'))
          .called(1);
    });

    test('maps a doc to an Account on hit', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer(
        (_) async => {
          'id': _uid,
          'uid': _uid,
          'firstName': 'Yvan',
          'lastName': 'Vds',
          'email': 'yvan@example.com',
          'targetGoal': 'tg',
          'mayUseGlobalKey': true,
        },
      );

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

      await build().upsertAccount(
        uid: _uid,
        firstName: 'Yvan',
        lastName: 'Vds',
        email: 'yvan@example.com',
      );

      final captured =
          verify(
                () => container.upsert(
                  captureAny<Map<String, Object?>>(),
                  partitionKey: any<Object>(named: 'partitionKey'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(captured['id'], _uid);
      expect(captured['uid'], _uid);
      expect(captured['firstName'], 'Yvan');
      expect(captured['email'], 'yvan@example.com');
      expect(captured['mayUseGlobalKey'], false);
      expect(captured['targetGoal'], '');
      expect(captured['className'], '');
      expect(captured['createdAt'], isA<String>());
      expect(captured['updatedAt'], isA<String>());
    });

    test('preserves existing mayUseGlobalKey, targetGoal, className, createdAt '
        'on update', () async {
      const existingCreatedAt = '2024-01-01T00:00:00.000Z';
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer(
        (_) async => {
          'id': _uid,
          'uid': _uid,
          'mayUseGlobalKey': true,
          'targetGoal': 'goal-x',
          'className': '5A',
          'createdAt': existingCreatedAt,
        },
      );
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

      final captured =
          verify(
                () => container.upsert(
                  captureAny<Map<String, Object?>>(),
                  partitionKey: any<Object>(named: 'partitionKey'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(captured['mayUseGlobalKey'], true);
      expect(captured['targetGoal'], 'goal-x');
      expect(captured['className'], '5A');
      expect(captured['createdAt'], existingCreatedAt);
      // updatedAt is fresh, distinct from createdAt.
      expect(captured['updatedAt'], isNot(existingCreatedAt));
    });
  });

  group('upsertAccount keeps what it does not set (#217)', () {
    test('the oefening counter, the calibration, the streak and any field '
        'it does not know survive a profile rewrite', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer(
        (_) async => {
          'id': _uid,
          'uid': _uid,
          'oefeningCount': 140,
          'calibration': {'difficulty': 'hard'},
          'streakDays': 4,
          'somethingNewer': 'kept',
        },
      );
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

      final doc =
          verify(
                () => container.upsert(
                  captureAny<Map<String, Object?>>(),
                  partitionKey: any<Object>(named: 'partitionKey'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(doc['oefeningCount'], 140);
      expect(doc['calibration'], {'difficulty': 'hard'});
      expect(doc['streakDays'], 4);
      expect(doc['somethingNewer'], 'kept');
      expect(doc['firstName'], 'Y');
    });
  });

  group('setCalibration — the oefening counter (#217)', () {
    late Map<String, dynamic> stored;

    setUp(() {
      stored = {
        'id': _uid,
        'uid': _uid,
        'oefeningCount': 24,
        'streakDays': 3,
        'somethingNewer': 'kept',
      };
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => Map<String, dynamic>.of(stored));
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((inv) async {
        stored = Map<String, dynamic>.of(
          inv.positionalArguments[1] as Map<String, Object?>,
        );
        return stored;
      });
    });

    Future<AccountService> signedIn() async {
      final svc = build();
      (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
        _identity(),
      );
      await Future<void>.delayed(Duration.zero);
      return svc;
    }

    test('counting adds one to what is stored, in the calibration write, '
        'and keeps every other field', () async {
      final svc = await signedIn();

      await svc.setCalibration(StudentCalibration.fresh(), countOefening: true);

      expect(stored['oefeningCount'], 25);
      expect(stored['calibration'], StudentCalibration.fresh().toJson());
      expect(stored['streakDays'], 3);
      expect(stored['somethingNewer'], 'kept');
    });

    test('counts from the doc as read, not from the last poll: two answers '
        'before the poll comes back are two', () async {
      final svc = await signedIn();
      final polled = pc.read(accountServiceProvider)?.oefeningCount;

      await svc.setCalibration(StudentCalibration.fresh(), countOefening: true);
      await svc.setCalibration(StudentCalibration.fresh(), countOefening: true);

      expect(stored['oefeningCount'], 26);
      expect(pc.read(accountServiceProvider)?.oefeningCount, polled);
    });

    test('a doc from before the counter starts it at 1', () async {
      stored.remove('oefeningCount');
      final svc = await signedIn();
      await svc.setCalibration(StudentCalibration.fresh(), countOefening: true);
      expect(stored['oefeningCount'], 1);
    });

    test('without countOefening — a reset, an archive import, a follow-up — '
        'the counter stays as it is', () async {
      final svc = await signedIn();
      await svc.setCalibration(StudentCalibration.fresh());
      expect(stored['oefeningCount'], 24);
    });
  });

  group('awardBadges (#220)', () {
    late Map<String, dynamic> stored;
    var replaces = 0;

    setUp(() {
      replaces = 0;
      stored = {
        'id': _uid,
        'uid': _uid,
        'oefeningCount': 24,
        'somethingNewer': 'kept',
      };
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async {
        // A real round trip: the doc as it was when the read went out, back
        // a little later — so two writes in flight could interleave.
        final snapshot = Map<String, dynamic>.of(stored);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return snapshot;
      });
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((inv) async {
        replaces++;
        stored = Map<String, dynamic>.of(
          inv.positionalArguments[1] as Map<String, Object?>,
        );
        return stored;
      });
    });

    Future<AccountService> signedIn() async {
      final svc = build();
      (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
        _identity(),
      );
      await Future<void>.delayed(Duration.zero);
      return svc;
    }

    test('the first look writes the map and says so; every other field '
        'stays', () async {
      final svc = await signedIn();
      final award = await svc.awardBadges({
        'effort': 1,
        'helloWorld': 1,
      }, now: DateTime.utc(2026, 10, 5));
      expect(award!.first, isTrue);
      expect(award.raised, {'effort': 1, 'helloWorld': 1});
      expect(stored['badges'], {
        'effort': {'tier': 1, 'earnedAt': '2026-10-05T00:00:00.000Z'},
        'helloWorld': {'tier': 1, 'earnedAt': '2026-10-05T00:00:00.000Z'},
      });
      expect(stored['oefeningCount'], 24);
      expect(stored['somethingNewer'], 'kept');
    });

    test('raises against the doc as stored — what another laptop already '
        'wrote is not raised again — and writes nothing when nothing goes '
        'up', () async {
      stored['badges'] = {
        'effort': {'tier': 1, 'earnedAt': '2026-10-01T00:00:00.000Z'},
      };
      final svc = await signedIn();

      final same = await svc.awardBadges({'effort': 1});
      expect(same!.raised, isEmpty);
      expect(replaces, 0);

      final higher = await svc.awardBadges({'effort': 2, 'streak': 1});
      expect(higher!.first, isFalse);
      expect(higher.raised, {'effort': 2, 'streak': 1});
      expect(replaces, 1);
      expect((stored['badges'] as Map)['effort']['tier'], 2);
    });

    test(
      'a badge write right behind the calibration write of the same '
      'answer waits for it: the oefening counted is not written back',
      () async {
        final svc = await signedIn();
        // Not awaited one by one: the tutor fires the badge write while the
        // calibration write may still be on its way.
        await Future.wait([
          svc.setCalibration(StudentCalibration.fresh(), countOefening: true),
          svc.awardBadges({'effort': 3}),
        ]);
        expect(stored['oefeningCount'], 25);
        expect((stored['badges'] as Map)['effort']['tier'], 3);
      },
    );

    test('a write that fails does not hold up the next', () async {
      final svc = await signedIn();
      var fail = true;
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((inv) async {
        if (fail) {
          fail = false;
          throw CosmosException(503, 'unavailable');
        }
        stored = Map<String, dynamic>.of(
          inv.positionalArguments[1] as Map<String, Object?>,
        );
        return stored;
      });
      await expectLater(
        svc.awardBadges({'effort': 1}),
        throwsA(isA<CosmosException>()),
      );
      await svc.awardBadges({'effort': 1});
      expect((stored['badges'] as Map)['effort']['tier'], 1);
    });
  });

  group('setTargetGoal', () {
    test('throws StateError when no user is signed in', () {
      // No auth set → currentUid is null → throws StateError.
      expect(
        () => build().setTargetGoal(targetGoal: 'g'),
        throwsA(isA<StateError>()),
      );
    });

    test('reads, patches targetGoal, refreshes updatedAt, replaces', () async {
      (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
        _identity(),
      );
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid, 'targetGoal': 'old'});
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
      // Drain any microtasks the Notifier's listener spawned (it queued
      // _ensureProfile but we don't care about that here).
      await Future<void>.delayed(Duration.zero);
      // Reset interaction counters so we measure only setTargetGoal's effects.
      clearInteractions(container);
      // Re-stub after clearInteractions wiped the stubs too.
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid, 'targetGoal': 'old'});
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
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid});
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

    test(
      'silently no-ops when the doc is missing (no replace fired)',
      () async {
        when(
          () => container.read(
            any<String>(),
            partitionKey: any<Object>(named: 'partitionKey'),
          ),
        ).thenAnswer((_) async => null);

        await build().setMayUseGlobalKey(uid: 'gone', value: true);
        verifyNever(
          () => container.replace(
            any<String>(),
            any<Map<String, Object?>>(),
            partitionKey: any<Object>(named: 'partitionKey'),
          ),
        );
      },
    );
  });

  group('setClassName', () {
    test('patches a trimmed className for the requested uid (#86)', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid, 'className': 'old'});
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().setClassName(uid: _uid, className: '  5A ');

      final captured = verify(
        () => container.replace(
          captureAny<String>(),
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], _uid);
      final doc = captured[1] as Map<String, Object?>;
      expect(doc['className'], '5A');
      expect(doc['updatedAt'], isA<String>());
    });

    test('an empty name clears the assignment', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid, 'className': '5A'});
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().setClassName(uid: _uid, className: '');

      final captured = verify(
        () => container.replace(
          any<String>(),
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      expect((captured.single as Map)['className'], '');
    });

    test('silently no-ops when the doc is missing', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => null);

      await build().setClassName(uid: 'gone', className: '5A');
      verifyNever(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });
  });

  group('getMyAccount', () {
    test('returns null immediately when no user is signed in', () async {
      expect(await build().getMyAccount(), isNull);
    });

    test('delegates to getAccount using the current uid', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer(
        (_) async => {
          'id': _uid,
          'uid': _uid,
          'firstName': 'Yvan',
          'lastName': 'V',
          'email': 'y@example.com',
          'targetGoal': '',
          'mayUseGlobalKey': false,
        },
      );

      (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
        _identity(),
      );
      final acc = await build().getMyAccount();
      expect(acc, isNotNull);
      expect(acc!.uid, _uid);
    });
  });

  group('watchMyAccount', () {
    test('returns a single-null stream when no user is signed in', () async {
      final first = await build().watchMyAccount().first;
      expect(first, isNull);
    });
  });

  group('watchMyMayUseGlobalKey', () {
    test('returns a false stream when no user is signed in', () async {
      final first = await build().watchMyMayUseGlobalKey().first;
      expect(first, isFalse);
    });
  });

  group('watchMayUseGlobalKey', () {
    test('emits false when doc is missing', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => null);

      final first = await build().watchMayUseGlobalKey(_uid).first;
      expect(first, isFalse);
    });

    test('emits the stored boolean value', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'mayUseGlobalKey': true});

      final first = await build().watchMayUseGlobalKey(_uid).first;
      expect(first, isTrue);
    });
  });

  group('getAllAccounts', () {
    test('queries cross-partition, sorts by createdAt descending', () async {
      when(
        () => container.query(
          any<String>(),
          crossPartition: any<bool>(named: 'crossPartition'),
        ),
      ).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          {
            'id': 'u1',
            'uid': 'u1',
            'firstName': 'A',
            'lastName': 'A',
            'email': 'a@example.com',
            'targetGoal': '',
            'mayUseGlobalKey': false,
            'createdAt': '2024-01-01T00:00:00.000Z',
          },
          {
            'id': 'u2',
            'uid': 'u2',
            'firstName': 'B',
            'lastName': 'B',
            'email': 'b@example.com',
            'targetGoal': '',
            'mayUseGlobalKey': false,
            'createdAt': '2025-01-01T00:00:00.000Z',
          },
        ],
      );

      final accounts = await build().getAllAccounts();
      // Sorted newest-first: u2 before u1.
      expect(accounts, hasLength(2));
      expect(accounts.first.uid, 'u2');
      expect(accounts.last.uid, 'u1');

      final captured = verify(
        () => container.query(
          captureAny<String>(),
          crossPartition: captureAny<bool>(named: 'crossPartition'),
        ),
      ).captured;
      expect(captured[0], contains('SELECT * FROM c'));
      expect(captured[1], isTrue);
    });
  });

  group('deleteAccountDoc', () {
    test('deletes by uid with uid as partition key', () async {
      when(
        () => container.delete(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async {});

      await build().deleteAccountDoc(_uid);
      verify(() => container.delete(_uid, partitionKey: _uid)).called(1);
    });
  });

  group('auth listener — _ensureProfile', () {
    test('does not call upsert when an account doc already exists', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid});

      build();
      (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
        _identity(),
      );
      // Let the unawaited(_ensureProfile(...)) run.
      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });

    test(
      'calls upsert (creating the profile) when no account doc exists',
      () async {
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

        build();
        (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
          _identity(firstName: 'Yvan'),
        );
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
      },
    );

    test(
      'a transient Cosmos failure during profile creation is retried on '
      'the next poll instead of escaping as an uncaught error (#7)',
      () async {
        var reads = 0;
        when(
          () => container.read(
            any<String>(),
            partitionKey: any<Object>(named: 'partitionKey'),
          ),
        ).thenAnswer((_) async {
          reads++;
          // First read (the ensureProfile lookup) fails; the account watch
          // and the retried lookup then see "no doc yet".
          if (reads == 1) throw CosmosException(503, 'unavailable');
          return null;
        });
        when(
          () => container.upsert(
            any<Map<String, Object?>>(),
            partitionKey: any<Object>(named: 'partitionKey'),
          ),
        ).thenAnswer((_) async => <String, dynamic>{});

        build();
        (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
          _identity(firstName: 'Retry'),
        );
        // Failed ensureProfile → first poll (null) → retried ensureProfile.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final upserts = verify(
          () => container.upsert(
            captureAny<Map<String, Object?>>(),
            partitionKey: any<Object>(named: 'partitionKey'),
          ),
        ).captured;
        expect(upserts, hasLength(1));
        expect((upserts.single as Map)['firstName'], 'Retry');
      },
    );

    test('signing out (identity → null) clears currentAccount', () async {
      // Start with no user, then go non-null briefly, then back to null.
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'id': _uid, 'uid': _uid});

      final svc = build();
      (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(
        _identity(),
      );
      await Future<void>.delayed(Duration.zero);

      (pc.read(authServiceProvider.notifier) as _ControlledAuth).set(null);
      expect(pc.read(accountServiceProvider), isNull);
      // Also verify via the notifier's state alias for clarity.
      expect(svc.state, isNull);
    });
  });
}
