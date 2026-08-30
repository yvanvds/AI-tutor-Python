// End-to-end (#46): a failing update check must not take the app down.
//
// `_checkForUpdate` runs unawaited from a post-frame callback, so before
// #46 anything it threw — a malformed manifest, a 500, a DNS failure —
// became an unhandled async error: no dialog, no log, and in a test run an
// error the framework reports against whatever test happens to be running.
// These flows serve exactly those two payloads from a loopback server and
// assert the real app boots through them: no crash, no update dialog, the
// shell still there.
//
// Both fail on the unpatched code — the malformed manifest with a
// `TypeError` out of `Uri.parse(null)`, the 500 by *silently* being treated
// as "nothing published", which is the indistinguishability this issue is
// about (that one is pinned by the unit tests on `fetchUpdateInfo`).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just these flows:
//   flutter test integration_test/flows/update_failure.dart -d windows

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

/// Serves [body] with [status] at `/version.json`, and 404 everywhere else.
/// Completes [served] the first time the manifest is asked for, so a flow
/// can wait for the check to have actually happened instead of guessing a
/// number of frames.
Future<HttpServer> _manifestServer({
  required int status,
  required String body,
  required Completer<void> served,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/version.json') {
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      );
      request.response.add(utf8.encode(body));
      if (!served.isCompleted) served.complete();
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

/// Boots the app against [server], waits for the check to land, and asserts
/// the app survived it without an update dialog.
Future<void> _expectSurvivesCheck(
  WidgetTester tester,
  HttpServer server,
  Completer<void> served,
) async {
  final harness = AppHarness(
    updateManifestUrl: Uri.parse(
      'http://${server.address.address}:${server.port}/version.json',
    ),
  );
  await harness.boot(tester);

  await pumpUntil(
    tester,
    () => served.isCompleted,
    reason: 'the app never requested the manifest',
  );
  // Frames for the failure to propagate through the async check; an
  // unhandled error surfaces here and fails the test.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byType(AppShell), findsOneWidget);

  await harness.dispose(tester);
  await server.close(force: true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a manifest missing a field does not crash the app', (
    tester,
  ) async {
    final served = Completer<void>();
    final server = await _manifestServer(
      status: HttpStatus.ok,
      // No `url`: `UpdateInfo.fromJson` used to do `Uri.parse(null)`.
      body: '{"version":"99.0.0+1","sha256":"not-a-real-hash"}',
      served: served,
    );
    await _expectSurvivesCheck(tester, server, served);
  });

  testWidgets('a server error does not crash the app', (tester) async {
    final served = Completer<void>();
    final server = await _manifestServer(
      status: HttpStatus.internalServerError,
      body: 'upstream is having a day',
      served: served,
    );
    await _expectSurvivesCheck(tester, server, served);
  });
}
