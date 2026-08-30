// End-to-end (#47): a build that is not a release must not check, download
// or install anything by itself.
//
// Before #47 the check ran from `AppShell.initState` with no gate on the
// build type, so a `flutter run` checkout — and every integration-test boot —
// reached out to the published release, and would have downloaded and
// silently installed a release build over the developer's own machine the
// moment that release went ahead of the working tree.
//
// This flow points the app at a loopback server that offers a wildly newer
// release and then leaves the app's own `kReleaseMode` default in place
// (`forceUpdateCheck: false` — the other update flows override it, because a
// test binary is never a release build). The assertion is a negative one,
// and it is the only kind that can prove this: the server is never asked. It
// fails on the unpatched code, where the boot fetches.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_dev_build.dart -d windows

import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a non-release build never asks for the latest release', (
    tester,
  ) async {
    final server = await FakeReleaseServer.start(version: '99.0.0+1');

    final harness = AppHarness(
      updateFeedUrl: server.feedUrl,
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
      server.releaseRequests,
      0,
      reason: 'a debug build reached out to the Releases API',
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);

    await harness.dispose(tester);
    await server.close();
  });
}
