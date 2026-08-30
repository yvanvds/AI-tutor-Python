// End-to-end (#47): a build that is not a release must not check, download
// or install anything by itself.
//
// Before #47 the check ran from `AppShell.initState` with no gate on the
// build type, so a `flutter run` checkout — and every integration-test boot —
// reached out to the published manifest, and would have downloaded and
// silently installed a release build over the developer's own machine the
// moment that manifest went ahead of the working tree.
//
// This flow points the app at a loopback manifest server that offers a
// wildly newer version and then leaves the app's own `kReleaseMode` default
// in place (`forceUpdateCheck: false` — the other update flows override it,
// because a test binary is never a release build). The assertion is a
// negative one, and it is the only kind that can prove this: the server is
// never asked. It fails on the unpatched code, where the boot fetches.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_dev_build.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a non-release build never asks for the manifest', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://${server.address.address}:${server.port}';
    var manifestRequests = 0;

    server.listen((request) async {
      if (request.uri.path == '/version.json') {
        manifestRequests++;
        request.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.response.add(
          utf8.encode(
            '{"version":"99.0.0+1",'
            '"url":"$base/python_teacher_install.exe",'
            '"sha256":"not-a-real-hash"}',
          ),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final harness = AppHarness(
      updateManifestUrl: Uri.parse('$base/version.json'),
      // The app's own gate decides — which is the whole point here.
      forceUpdateCheck: false,
    );
    await harness.boot(tester);

    // Well past the point where the patched build's sibling flow
    // (update_prompt.dart) already has its dialog on screen.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      manifestRequests,
      0,
      reason: 'a debug build reached out for the release manifest',
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);

    await harness.dispose(tester);
    await server.close(force: true);
  });
}
