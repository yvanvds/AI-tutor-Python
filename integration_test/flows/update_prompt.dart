// End-to-end (#50, rewritten for #48): the real app, booted against GitHub's
// Releases API, *offers* the release the API publishes — and waits.
//
// What #48 changed, and what these assert:
//
//   - The update used to be announced, not offered: a
//     `barrierDismissible: false` dialog with one OK button, and closing it
//     started a ~250 MB download and an unconditional install. There was no
//     way to say "not now". The first test taps **Later** and proves the
//     installer was never fetched — on the pre-#48 build there is no Later
//     to tap and the download starts by itself.
//   - There was no progress: `pipe` gave no per-chunk hook, so a student
//     watched nothing happen for the length of the download. The second test
//     accepts the offer against a server that dribbles the installer out in
//     chunks, and watches the bar fill.
//
// The second test also drives the production verify wiring to its conclusion:
// the bytes served are junk, their hash is not the published one, so the app
// refuses to start them and cleans the partial installer out of `%TEMP%`.
// Nothing here ever spawns a setup binary.
//
// #45's guarantee still rides along: the checksum asset is served as
// `application/octet-stream` with a leading UTF-8 BOM — the content type a
// real release asset carries, and the byte sequence the release script has
// emitted before. Read through `res.body` instead of `res.bodyBytes` those
// three bytes become three characters in front of the hash, and the update is
// never offered at all.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_prompt.dart -d windows

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

final _offerBar = find.byKey(const ValueKey('update-offer'));
final _offerMessage = find.byKey(const ValueKey('update-offer-message'));
final _applyButton = find.byKey(const ValueKey('update-offer-apply'));
final _laterButton = find.byKey(const ValueKey('update-offer-later'));
final _progressBar = find.byKey(const ValueKey('update-offer-progress'));

/// Whatever the bar is currently saying, or `null` when it is not on screen.
String? _barSays(WidgetTester tester) => _offerMessage.evaluate().isEmpty
    ? null
    : tester.widget<Text>(_offerMessage).data;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a release published on the API is offered, and Later declines '
      'it without downloading anything', (tester) async {
    final server = await FakeReleaseServer.start(
      version: '99.0.0+1',
      // The BOM the release script has written in front of a generated file
      // before, on an asset served as octet-stream (#45).
      checksumBom: true,
    );

    final harness = AppHarness(updateFeedUrl: server.feedUrl);
    await harness.boot(tester);

    await pumpUntilFound(tester, _offerBar);
    // A strip of chrome, not a modal: the rest of the app is still there and
    // still usable while the offer waits.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('99.0.0+1'), findsOneWidget);
    expect(_applyButton, findsOneWidget);
    expect(_laterButton, findsOneWidget);
    expect(
      server.checksumRequests,
      greaterThan(0),
      reason: 'the release was offered without fetching its checksum',
    );

    await tester.tap(_laterButton);
    await pumpUntilGone(tester, _offerBar);

    // The whole point of the button: nothing was downloaded, and nothing
    // starts downloading afterwards either.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      server.installerRequests,
      0,
      reason: 'Later downloaded the installer anyway',
    );
    expect(_offerBar, findsNothing);

    await harness.dispose(tester);
    await server.close();
  });

  testWidgets('accepting the offer shows progress and stops at the checksum', (
    tester,
  ) async {
    // Junk bytes: whatever they hash to, it is not the published
    // all-zeroes checksum, so `verifyAndCleanUp` rejects them.
    final installer = Uint8List.fromList(
      List<int>.generate(64 * 1024, (i) => i % 256),
    );
    final server = await FakeReleaseServer.start(
      version: '99.0.0+1',
      installerBytes: installer,
    );
    final downloaded = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'python_teacher_install.exe',
    );
    if (downloaded.existsSync()) downloaded.deleteSync();

    final harness = AppHarness(updateFeedUrl: server.feedUrl);
    await harness.boot(tester);

    await pumpUntilFound(tester, _offerBar);
    expect(_progressBar, findsNothing, reason: 'downloading before consent');

    await tester.tap(_applyButton);

    // The bar the old code had no way to render: `pipe` reported nothing.
    await pumpUntilFound(tester, _progressBar);
    expect(server.installerRequests, 1);
    // Both buttons are out of reach while it works, so a second tap cannot
    // start a second download.
    expect(tester.widget<FilledButton>(_applyButton).onPressed, isNull);
    expect(tester.widget<TextButton>(_laterButton).onPressed, isNull);

    // A download whose bytes do not match the published hash must never be
    // handed to `Process.start` — the bar says so and the app is still here.
    await pumpUntil(
      tester,
      () => _barSays(tester)?.contains('checksum') ?? false,
      timeout: const Duration(seconds: 30),
      reason: 'the failed checksum was never reported on the offer bar',
    );
    expect(
      downloaded.existsSync(),
      isFalse,
      reason: 'a rejected installer was left in %TEMP%',
    );

    await harness.dispose(tester);
    await server.close();
  });
}
