// End-to-end (#345): signing out with the database on the sign-in.
//
// A school whose school file says `"databaseAccess": "signIn"` (#306)
// reaches its database with a token from the user's own sign-in. Signing out
// clears that sign-in. Before, the app went on polling the database after
// it — `config/global` every 5 s, and every other provider that lives as long
// as the app — and the first poll without a token pushed "Permission denied
// while reading data." over the sign-in screen, about a second after the
// sign-out. A student who wanted to sign in with another account, on a
// shared pc in the classroom, had to get past that screen first.
//
// Now the polls stop at the sign-out. The student reads a lesson first, so
// the providers behind it are alive too; then signs out. The sign-in screen
// stays, through two polls' worth of waiting, and the app does not even try
// a request. Signing in again goes through the real sign-in: the flow plays
// the browser — it takes the authorize URL the app opened, and comes back on
// the app's loopback address with a code and the state — and Entra's token
// endpoint is faked. The app is back, the polls start again, with a fresh
// database token from the new sign-in.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/sign_out_sign_in.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/features/auth/sign_in_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/services/auth/cosmos_token_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/memory_school_file_store.dart';
import '../../test/helpers/test_app_mode.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// An unsigned id token with [claims], as Entra's token endpoint returns it.
String _jwt(Map<String, Object?> claims) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signing out with the sign-in on the database: the sign-in '
      'screen stays, also after a few polls, and signing in again works', (
    tester,
  ) async {
    final appData = Directory.systemTemp.createTempSync('ai_tutor_appdata_');
    addTearDown(() {
      if (appData.existsSync()) appData.deleteSync(recursive: true);
    });
    final schoolFile = exampleSchoolFile(extra: {'databaseAccess': 'signIn'});
    File('${appData.path}/school.json').writeAsStringSync(schoolFile);
    final school = parseSchoolFile(schoolFile);
    expect(school.databaseAccess, DatabaseAccess.signIn);

    // Entra's token endpoint: the stored sign-in's refresh at start, the
    // code of the second sign-in, and the database's tokens, numbered.
    final databaseScope =
        '${CosmosTokenSource.scopeFor(school.databaseEndpoint)} '
        'offline_access';
    bool forDatabase(http.Request r) => r.bodyFields['scope'] == databaseScope;
    final tokenRequests = <http.Request>[];
    var databaseTokens = 0;
    final entra = MockClient((request) async {
      tokenRequests.add(request);
      if (forDatabase(request)) {
        databaseTokens++;
        return http.Response(
          jsonEncode({
            'access_token': 'database-token-$databaseTokens',
            'expires_in': 3600,
          }),
          200,
        );
      }
      final code = request.bodyFields['grant_type'] == 'authorization_code';
      return http.Response(
        jsonEncode({
          'access_token': 'sign-in-access',
          'refresh_token': code ? 'refresh-after-sign-in' : 'stored-refresh',
          'id_token': _jwt({
            'oid': studentIdentity.oid,
            'name': studentIdentity.displayName,
            'email': studentIdentity.email,
          }),
          'expires_in': 3600,
        }),
        200,
      );
    });

    // A build with school data, so it is the school file that puts the
    // database on the sign-in; and a student signed in, as on any morning.
    final harness = AppHarness(
      decideMode: true,
      buildSchool: kTestSchool,
      schoolData: appData,
      entra: entra,
      prefs: {
        'azure_auth_tokens_v1': jsonEncode({
          'access_token': 'old-access',
          'refresh_token': 'stored-refresh',
          'id_token': null,
          'access_token_expiry': null,
        }),
      },
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(AppShell));
    expect(harness.startedMode, SchoolMode(school));
    expect(harness.cosmos.authorizations, isNotEmpty);
    expect(harness.cosmos.authorizations.toSet(), {
      Uri.encodeComponent('type=aad&ver=1.0&sig=database-token-1'),
    });

    // A lesson, so the lessons, their translations and the curriculum the
    // tutor watches are polled too, not only what the shell needs.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.pump(const Duration(seconds: 1));

    // Sign out.
    await tester.tap(find.byTooltip('Sign out'));
    await pumpUntilFound(tester, find.byType(SignInPage));
    expect(find.byType(AppShell), findsNothing);
    // A poll already on its way when the student clicked may land; nothing
    // after it.
    await tester.pump(const Duration(milliseconds: 500));
    final triedAtSignOut = harness.cosmos.requests.length;

    // Two polls' worth of waiting, every frame looked at: the recovery
    // screen came about a second after the sign-out.
    var crashFrames = 0;
    final deadline = DateTime.now().add(
      kCosmosPollInterval * 2 + const Duration(seconds: 1),
    );
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CrashRecoveryScreen).evaluate().isNotEmpty) {
        crashFrames++;
      }
    }
    expect(
      crashFrames,
      0,
      reason: 'the recovery screen was up for $crashFrames frame(s)',
    );
    expect(find.text('Permission denied while reading data.'), findsNothing);
    expect(find.byType(SignInPage), findsOneWidget);
    expect(
      harness.cosmos.requests.sublist(triedAtSignOut),
      isEmpty,
      reason: 'the app tried the database with nobody signed in',
    );
    expect(tester.takeException(), isNull);

    // Sign in again. The button opens the browser at Entra's authorize page;
    // the token request that follows goes to the faked endpoint.
    final launchesBefore = harness.browserLaunches.length;
    await http.runWithClient(
      () => tester.tap(find.text('Sign in with school account')),
      () => entra,
    );
    await pumpUntil(
      tester,
      () => harness.browserLaunches.length > launchesBefore,
      reason: 'the sign-in never opened the browser',
    );
    final authorize = harness.browserLaunches.last;
    expect(authorize.host, 'login.microsoftonline.com');
    expect(authorize.path, contains(school.tenantId));
    expect(authorize.queryParameters['client_id'], school.clientId);

    // The browser, back from Entra with a code: on the app's own loopback
    // address, with the state the app sent.
    final redirect = Uri.parse(authorize.queryParameters['redirect_uri']!);
    final browser = HttpClient();
    final back = await browser.getUrl(
      Uri.http('127.0.0.1:${redirect.port}', '/', {
        'code': 'second-sign-in-code',
        'state': authorize.queryParameters['state']!,
      }),
    );
    final page = await back.close();
    await page.drain<void>();
    browser.close();
    expect(page.statusCode, 200);

    await pumpUntilFound(tester, find.byType(AppShell));
    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(CrashRecoveryScreen), findsNothing);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    final exchange = tokenRequests
        .where((r) => r.bodyFields['grant_type'] == 'authorization_code')
        .toList();
    expect(exchange, hasLength(1));
    expect(exchange.single.bodyFields['code'], 'second-sign-in-code');
    expect(exchange.single.bodyFields['client_id'], school.clientId);

    // The polls are back, on a database token of the new sign-in.
    await pumpUntil(
      tester,
      () => harness.cosmos.requests.length > triedAtSignOut,
      reason: 'no request to the database after signing in again',
    );
    expect(
      tokenRequests.where(forDatabase).last.bodyFields['refresh_token'],
      'refresh-after-sign-in',
    );
    expect(
      harness.cosmos.authorizations.last,
      Uri.encodeComponent('type=aad&ver=1.0&sig=database-token-2'),
    );
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
}
