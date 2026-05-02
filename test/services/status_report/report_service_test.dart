// 5.1 — `ReportService.getStatusReportsForUser` is the teacher-side per-uid
// read introduced in step 5. Pins down the SQL/partition-key shape and the
// composite-doc-id behaviour. The signed-in-user reads were already covered
// implicitly by the conductor flow tests; this file pins down only the new
// surface plus the existing `getAll` (since they share the same fetch).

import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/locator.dart';
import '../../helpers/mocks.dart';

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
    currentUser = ValueNotifier<AccountIdentity?>(null);
    when(() => auth.currentUser).thenReturn(currentUser);
    registerMock<AuthService>(auth);
  });

  tearDown(() async {
    await resetLocator();
    currentUser.dispose();
  });

  ReportService build() => ReportService(container: container);

  test('getStatusReportsForUser scopes to the supplied uid as both partition '
      'key and parameter', () async {
    when(
      () => container.query(
        any<String>(),
        parameters: any<Map<String, Object?>>(named: 'parameters'),
        partitionKey: any<Object?>(named: 'partitionKey'),
      ),
    ).thenAnswer((_) async => <Map<String, dynamic>>[
          {'goalId': 'g1', 'statusReport': 'looking good'},
        ]);

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

  test('watchStatusReportsForUser exposes a stream backed by the same fetch',
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
  });
}
