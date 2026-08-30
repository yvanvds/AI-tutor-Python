// End-to-end (#46, extended for #50): a failing update check must not take
// the app down.
//
// The check runs unawaited from a post-frame callback, so before #46
// anything it threw — a malformed payload, a 500, a DNS failure — became an
// unhandled async error: no dialog, no log, and in a test run an error the
// framework reports against whatever test happens to be running. These flows
// serve exactly those answers from a loopback server standing in for the
// Releases API and assert the real app boots through them: no crash, no
// update dialog, the shell still there.
//
// #50 adds the third one: a release that publishes an installer but no
// `.sha256` beside it. That is a broken release rather than "nothing
// published", so the check fails loudly into the log and the state — and
// still must not put anything on screen or install anything.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just these flows:
//   flutter test integration_test/flows/update_failure.dart -d windows

import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

/// Boots the app against [server], waits for the check to land, and asserts
/// the app survived it without an update dialog.
Future<void> _expectSurvivesCheck(
  WidgetTester tester,
  FakeReleaseServer server,
) async {
  final harness = AppHarness(updateFeedUrl: server.feedUrl);
  await harness.boot(tester);

  await pumpUntil(
    tester,
    () => server.releaseRequests > 0,
    reason: 'the app never asked for the latest release',
  );
  // Frames for the failure to propagate through the async check; an
  // unhandled error surfaces here and fails the test.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  // Nothing pushed at the student, in either shape: the modal #48 removed or
  // the offer bar that replaced it. A check that failed has no release to
  // offer, so its reason waits in About instead (#48).
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byKey(const ValueKey('update-offer')), findsNothing);
  expect(find.byType(AppShell), findsOneWidget);

  await harness.dispose(tester);
  await server.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a payload that is not a release does not crash the app', (
    tester,
  ) async {
    // No `tag_name`, no `assets`: every field the parser reads is missing.
    final server = await FakeReleaseServer.start(
      rawBody: '{"message":"Not Found"}',
    );
    await _expectSurvivesCheck(tester, server);
  });

  testWidgets('a server error does not crash the app', (tester) async {
    final server = await FakeReleaseServer.start(
      status: 500,
      rawBody: 'upstream is having a day',
    );
    await _expectSurvivesCheck(tester, server);
  });

  testWidgets('a release with no checksum asset does not crash the app', (
    tester,
  ) async {
    final server = await FakeReleaseServer.start(withChecksumAsset: false);
    await _expectSurvivesCheck(tester, server);
  });
}
