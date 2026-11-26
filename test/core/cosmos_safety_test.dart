// Issue #7 — `safeCosmosStream` absorbs a failed poll so the consumer keeps
// the last good value and picks up the next successful fetch; the polling
// source itself must keep ticking through the failure.
//
// Issue #345 — `safeCosmos` pushes the recovery screen for a database that
// refuses the access, and not for nobody being signed in: with the database
// on the sign-in, a read after the sign-out has no token, and the sign-in
// screen is where the user belongs then.

import 'dart:convert';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/auth/cosmos_token_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app_mode.dart';

void main() {
  test('a failing poll is absorbed and polling continues', () async {
    var calls = 0;
    final stream = safeCosmosStream(
      pollingStream<int>(() async {
        calls++;
        if (calls == 2) throw CosmosException(503, 'blip');
        return calls;
      }, interval: const Duration(milliseconds: 10)),
    );

    final values = <int>[];
    final errors = <Object>[];
    final sub = stream.listen(values.add, onError: errors.add);

    // Wait until the poll after the failing one has landed.
    while (values.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await sub.cancel();

    expect(values.first, 1);
    expect(values[1], 3, reason: 'the 503 tick (2) is skipped, not fatal');
    expect(errors, isEmpty);
  });

  test(
    'pollingStream itself still reports the error to a raw listener',
    () async {
      var calls = 0;
      final stream = pollingStream<int>(() async {
        calls++;
        if (calls == 1) throw StateError('first fetch failed');
        return calls;
      }, interval: const Duration(milliseconds: 10));

      final errors = <Object>[];
      final values = <int>[];
      final sub = stream.listen(values.add, onError: errors.add);
      while (values.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await sub.cancel();

      expect(errors.single, isA<StateError>());
      expect(values.first, 2);
    },
  );

  group('safeCosmos and the recovery screen (#345)', () {
    final school = kTestSchool;
    late List<http.Request> database;

    /// The app's database client with the sign-in on the database, as
    /// `CosmosClient.schoolAuth` makes it: the token from the stored
    /// sign-in, through a token endpoint that hands one out, to a database
    /// that answers [status].
    CosmosContainer config({required int status}) {
      database = [];
      final tokens = CosmosTokenSource(
        school: school,
        tokensPrefsKey: AuthService.tokensPrefsKey,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'access_token': 'database-token', 'expires_in': 3600}),
            200,
          ),
        ),
      );
      return CosmosClient.withHttpClient(
        endpoint: school.databaseEndpoint,
        auth: AadTokenAuth(tokens.token),
        httpClient: MockClient((request) async {
          database.add(request);
          return http.Response(
            jsonEncode({'code': 'Forbidden', 'message': 'no role'}),
            status,
          );
        }),
        transientRetryBaseDelay: Duration.zero,
      ).container('config');
    }

    /// The sign-in screen, on the navigator `safeCosmos` pushes on.
    Future<void> mountSignInScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: appNavigatorKey,
            home: const Scaffold(body: Text('Sign in')),
          ),
        ),
      );
    }

    testWidgets('nobody signed in: the read fails without a request, and '
        'no recovery screen', (tester) async {
      // Signed out: the stored sign-in is gone.
      SharedPreferences.setMockInitialValues({});
      await mountSignInScreen(tester);
      final container = config(status: 200);

      final error = await tester.runAsync(
        () =>
            safeCosmos(() => container.read('global', partitionKey: 'config'))
                .then<Object?>((_) => null, onError: (Object e) => e),
      );
      await tester.pumpAndSettle();

      expect(
        error,
        isA<CosmosException>()
            .having((e) => e.isNotSignedIn, 'isNotSignedIn', isTrue)
            .having((e) => e.isAuthError, 'isAuthError', isFalse),
      );
      expect(database, isEmpty);
      expect(find.byType(CrashRecoveryScreen), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('signed in, and the database answers 403: the recovery '
        'screen, as before', (tester) async {
      SharedPreferences.setMockInitialValues({
        AuthService.tokensPrefsKey: jsonEncode({
          'access_token': 'sign-in-access',
          'refresh_token': 'stored-refresh',
          'id_token': null,
          'access_token_expiry': null,
        }),
      });
      await mountSignInScreen(tester);
      final container = config(status: 403);

      final error = await tester.runAsync(
        () =>
            safeCosmos(() => container.read('global', partitionKey: 'config'))
                .then<Object?>((_) => null, onError: (Object e) => e),
      );
      await tester.pumpAndSettle();

      expect(
        error,
        isA<CosmosException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.isAuthError, 'isAuthError', isTrue),
      );
      expect(database, hasLength(1));
      expect(
        database.single.headers['Authorization'],
        Uri.encodeComponent('type=aad&ver=1.0&sig=database-token'),
      );
      expect(find.byType(CrashRecoveryScreen), findsOneWidget);
      expect(
        find.text('Permission denied while reading data.'),
        findsOneWidget,
      );
    });
  });
}
