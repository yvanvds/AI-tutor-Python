// End-to-end (#45): the real app, booted against a release manifest that
// carries a UTF-8 BOM and is served without a charset, still offers the
// update.
//
// The BOM is what `tooling/build_release.ps1` wrote into the published
// `public/version.json`. It survives today only because GitHub Pages sends
// `application/json; charset=utf-8`, so `package:http` decodes with
// `Utf8Decoder`, which happens to drop a leading U+FEFF. Serve the very
// same bytes as `application/octet-stream` — what a GitHub *release asset*
// returns, which is where #50 wants to read the manifest from — and
// `package:http` falls back to latin1, the BOM becomes three characters,
// and `jsonDecode` throws inside an unawaited post-frame callback: no
// dialog, no error, no update, ever. That is the shape asserted here.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_prompt.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a BOM-prefixed version.json still offers the update', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://${server.address.address}:${server.port}';
    final manifest =
        '{\n'
        '  "version": "99.0.0+1",\n'
        '  "url": "$base/python_teacher_install.exe",\n'
        '  "sha256": "not-a-real-hash"\n'
        '}\n';

    server.listen((request) async {
      if (request.uri.path == '/version.json') {
        // No charset: `package:http` falls back to latin1 for this type.
        request.response.headers.contentType = ContentType(
          'application',
          'octet-stream',
        );
        // The three BOM bytes, exactly as the published file carried them.
        request.response.add(const [0xEF, 0xBB, 0xBF]);
        request.response.add(utf8.encode(manifest));
      } else {
        // The installer download is deliberately unavailable: this flow
        // proves the check reaches the user, and must never spawn a setup
        // binary on the machine running the tests.
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final harness = AppHarness(
      updateManifestUrl: Uri.parse('$base/version.json'),
    );
    await harness.boot(tester);

    await pumpUntilFound(tester, find.byType(AlertDialog));
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('99.0.0+1'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('OK')),
    );
    await pumpUntilGone(tester, find.byType(AlertDialog));

    await harness.dispose(tester);
    await server.close(force: true);
  });
}
