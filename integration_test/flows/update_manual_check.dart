// End-to-end (#48): a student can *ask* for an update, on a build that never
// asks by itself.
//
// Two things meet here that only a full-app run puts together:
//
//   - Before #48 there was no way to ask at all. Options → About printed the
//     version and nothing else, so an install that missed its launch check —
//     or one whose check failed silently (#46) — stayed on an old build with
//     no recourse and no explanation.
//   - The app only checks by itself in a release build (#47), and an
//     integration-test binary is never one. This flow therefore leaves the
//     app's own `kReleaseMode` gate in place (`forceUpdateCheck: false`), so
//     the *only* thing that can reach the network is the button — which is
//     exactly the situation a developer, or a student on a debug build, is
//     in. A manual check wired to the auto-check gate would pass a unit test
//     and do nothing here.
//
// The assertions run the whole way through the real app: the boot fetches
// nothing, the button in About fetches a release from a loopback stand-in for
// GitHub's Releases API, and the offer surfaces in the shell's own chrome —
// on the Options page the student is standing on.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_manual_check.dart -d windows

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Options -> About -> Check for updates finds a release a build '
      'that never auto-checks would have missed', (tester) async {
    final server = await FakeReleaseServer.start(version: '99.0.0+1');

    final harness = AppHarness(
      updateFeedUrl: server.feedUrl,
      // The app's own gate decides, and on a test binary it says no.
      forceUpdateCheck: false,
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    final status = find.byKey(const ValueKey('about-update-status'));
    final checkButton = find.byKey(const ValueKey('about-update-check'));
    await tester.scrollUntilVisible(
      checkButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(
      server.releaseRequests,
      0,
      reason: 'the boot reached out on a build that does not auto-check',
    );
    expect(
      tester.widget<Text>(status).data,
      'No update check has run yet.',
      reason: 'About claimed a check had happened',
    );
    expect(
      find.byKey(const ValueKey('about-update-apply')),
      findsNothing,
      reason: 'an apply button with nothing to apply',
    );

    await tester.tap(checkButton);
    await pumpUntil(
      tester,
      () => server.releaseRequests > 0,
      reason: 'the button never asked for the latest release',
    );

    // The answer lands in About...
    await pumpUntil(
      tester,
      () =>
          tester.widget<Text>(status).data == 'Version 99.0.0+1 is available.',
      reason: 'About never reported the release the button found',
    );
    expect(find.text('Update to 99.0.0+1'), findsOneWidget);

    // ...and in the shell's offer bar, which is the same state rendered
    // twice rather than two mechanisms.
    expect(find.byKey(const ValueKey('update-offer')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      server.installerRequests,
      0,
      reason: 'a check downloaded an installer without being asked',
    );

    await harness.dispose(tester);
    await server.close();
  });
}
