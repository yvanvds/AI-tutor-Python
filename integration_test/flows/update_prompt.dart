// End-to-end (#50): the real app, booted against GitHub's Releases API,
// offers the release the API publishes.
//
// The app used to read a `version.json` manifest written by
// `build_release.ps1` and served from GitHub Pages — a second artifact that
// had to stay in lockstep with the release, and once did not (#45). Now the
// release *is* the manifest: the tag carries the version, the assets carry
// the installer and the `.sha256` that replaces the manifest's hash field.
// This flow serves exactly that from a loopback server and asserts a student
// is offered the update. It fails on the pre-#50 code, which asks the same
// URL for a manifest, gets a release payload, and offers nothing.
//
// It also keeps #45's guarantee on the path where it now bites: the checksum
// asset is served as `application/octet-stream` with a leading UTF-8 BOM —
// the content type a real release asset carries, and the byte sequence the
// release script has emitted before. Read through `res.body` instead of
// `res.bodyBytes` those three bytes become three characters in front of the
// hash, and the update is never offered.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_prompt.dart -d windows

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a release published on the API is offered to the student', (
    tester,
  ) async {
    final server = await FakeReleaseServer.start(
      version: '99.0.0+1',
      // The BOM the release script has written in front of a generated file
      // before, on an asset served as octet-stream (#45).
      checksumBom: true,
    );

    final harness = AppHarness(updateFeedUrl: server.feedUrl);
    await harness.boot(tester);

    await pumpUntilFound(tester, find.byType(AlertDialog));
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('99.0.0+1'), findsOneWidget);
    expect(
      server.checksumRequests,
      greaterThan(0),
      reason: 'the release was offered without fetching its checksum',
    );

    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('OK')),
    );
    await pumpUntilGone(tester, find.byType(AlertDialog));

    await harness.dispose(tester);
    await server.close();
  });
}
