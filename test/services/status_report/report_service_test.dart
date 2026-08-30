// Tests for `ReportService`. Covers the signed-in-user read/write surface
// (getAll, getByGoalId, upsert, delete, updateForCurrentChildGoal,
// updateForGoal) plus the teacher-scoped reads introduced in step 5.
// Container is injected; uid comes from a ValueNotifier closure.

import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/status_report/status_report.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

const _uid = 'oid-report-user';

AccountIdentity _identity() => const AccountIdentity(
  oid: _uid,
  displayName: 'Test',
  email: 'test@example.com',
  firstName: 'Test',
  lastName: 'User',
  isTeacher: false,
);

void main() {
  late MockCosmosContainer container;
  late ValueNotifier<AccountIdentity?> currentUser;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    container = MockCosmosContainer();
    currentUser = ValueNotifier<AccountIdentity?>(null);
  });

  tearDown(() {
    currentUser.dispose();
  });

  ReportService build({String? Function()? getCurrentChildGoalId}) =>
      ReportService(
        container: container,
        getUid: () => currentUser.value?.oid,
        getCurrentChildGoalId: getCurrentChildGoalId,
      );

  group('uid resolution', () {
    test('throws StateError when no user is signed in', () {
      final svc = build();
      expect(() => svc.getAll(), throwsA(isA<StateError>()));
      expect(() => svc.getByGoalId('g'), throwsA(isA<StateError>()));
      expect(
        () => svc.upsert(StatusReport(goalID: 'g', statusReport: 'x')),
        throwsA(isA<StateError>()),
      );
      expect(() => svc.delete('g'), throwsA(isA<StateError>()));
    });
  });

  group('getAll', () {
    setUp(() => currentUser.value = _identity());

    test(
      'queries uid as partition key and parameter, maps rows to reports',
      () async {
        when(
          () => container.query(
            any<String>(),
            parameters: any<Map<String, Object?>>(named: 'parameters'),
            partitionKey: any<Object?>(named: 'partitionKey'),
          ),
        ).thenAnswer(
          (_) async => <Map<String, dynamic>>[
            {'goalId': 'g1', 'statusReport': 'good'},
            {'goalId': 'g2', 'statusReport': 'needs work'},
          ],
        );

        final out = await build().getAll();
        expect(out.map((r) => r.goalID).toList(), ['g1', 'g2']);
        expect(out.first.statusReport, 'good');

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
      },
    );
  });

  group('watchAll', () {
    setUp(() => currentUser.value = _identity());

    test('exposes a stream backed by the same fetch as getAll', () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <Map<String, dynamic>>[]);

      final first = await build().watchAll().first;
      expect(first, isEmpty);
      verify(
        () => container.query(
          any<String>(),
          parameters: {'@uid': _uid},
          partitionKey: _uid,
        ),
      ).called(greaterThanOrEqualTo(1));
    });
  });

  group('getByGoalId', () {
    setUp(() => currentUser.value = _identity());

    test('returns null when the doc is missing', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => null);

      expect(await build().getByGoalId('g1'), isNull);
      verify(() => container.read('${_uid}_g1', partitionKey: _uid)).called(1);
    });

    test('maps a doc to a StatusReport on hit', () async {
      when(
        () => container.read(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => {'goalId': 'g1', 'statusReport': 'on track'});

      final report = await build().getByGoalId('g1');
      expect(report, isNotNull);
      expect(report!.goalID, 'g1');
      expect(report.statusReport, 'on track');
    });
  });

  group('upsert', () {
    setUp(() => currentUser.value = _identity());

    test('builds composite id and partitions on uid', () async {
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().upsert(
        StatusReport(goalID: 'g1', statusReport: 'did well'),
      );

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
      expect(doc['statusReport'], 'did well');
      expect(captured[1], _uid);
    });
  });

  group('delete', () {
    setUp(() => currentUser.value = _identity());

    test('deletes by composite id, partitions on uid', () async {
      when(
        () => container.delete(
          any<String>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async {});

      await build().delete('g1');
      verify(
        () => container.delete('${_uid}_g1', partitionKey: _uid),
      ).called(1);
    });
  });

  group('updateForCurrentChildGoal', () {
    setUp(() => currentUser.value = _identity());

    test('no-op when getCurrentChildGoalId returns null', () async {
      await build(
        getCurrentChildGoalId: () => null,
      ).updateForCurrentChildGoal('report text');
      verifyNever(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });

    test('upserts a report for the current child goal id', () async {
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build(
        getCurrentChildGoalId: () => 'goal-child-1',
      ).updateForCurrentChildGoal('passed the quiz');

      final captured =
          verify(
                () => container.upsert(
                  captureAny<Map<String, Object?>>(),
                  partitionKey: any<Object>(named: 'partitionKey'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(captured['goalId'], 'goal-child-1');
      expect(captured['statusReport'], 'passed the quiz');
    });
  });

  group('updateForGoal', () {
    setUp(() => currentUser.value = _identity());

    test('upserts a report against the explicit goalID', () async {
      when(
        () => container.upsert(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().updateForGoal('explicit-goal', 'mastered loops');

      final captured =
          verify(
                () => container.upsert(
                  captureAny<Map<String, Object?>>(),
                  partitionKey: any<Object>(named: 'partitionKey'),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(captured['goalId'], 'explicit-goal');
      expect(captured['statusReport'], 'mastered loops');
    });
  });

  group('teacher-scoped reads (getStatusReportsForUser / watch)', () {
    test('getStatusReportsForUser scopes to the supplied uid as both partition '
        'key and parameter', () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer(
        (_) async => <Map<String, dynamic>>[
          {'goalId': 'g1', 'statusReport': 'looking good'},
        ],
      );

      final out = await build().getStatusReportsForUser('teacher-target-uid');
      expect(out, hasLength(1));
      expect(out.first.goalID, 'g1');
      expect(out.first.statusReport, 'looking good');

      final captured = verify(
        () => container.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: captureAny<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], contains('c.uid = @uid'));
      expect(captured[1], {'@uid': 'teacher-target-uid'});
      expect(captured[2], 'teacher-target-uid');
    });

    test(
      'watchStatusReportsForUser exposes a stream backed by the same fetch',
      () async {
        when(
          () => container.query(
            any<String>(),
            parameters: any<Map<String, Object?>>(named: 'parameters'),
            partitionKey: any<Object?>(named: 'partitionKey'),
          ),
        ).thenAnswer((_) async => const <Map<String, dynamic>>[]);

        final stream = build().watchStatusReportsForUser('teacher-target-uid');
        final first = await stream.first;
        expect(first, isEmpty);

        verify(
          () => container.query(
            any<String>(),
            parameters: {'@uid': 'teacher-target-uid'},
            partitionKey: 'teacher-target-uid',
          ),
        ).called(greaterThanOrEqualTo(1));
      },
    );
  });
}
