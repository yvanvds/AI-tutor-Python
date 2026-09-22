// End-to-end (#124): a launch check that fails is *announced* — a small,
// dismissible strip in the shell's own chrome — instead of being a
// `debugPrint` and a line in a panel nobody opens.
//
// Why this needed a full-app run: the failure that motivated it was invisible
// precisely because every piece worked as designed. `check()` parked the
// reason on the state, About rendered it, the offer bar correctly stayed
// away because there was no release — and a student behind a school's TLS
// filter sat two releases behind with nothing on screen. What these flows
// pin is the composition: the real shell, the real launch check against a
// loopback server that fails it, the notice in the strip where the offer
// bar goes, its close button, and About still holding the reason afterwards.
//
// The second flow pins the boundary: a check the student *asked for* from
// About fails in front of them, inline, and must not also raise the strip.
// A notice wired to `UpdatePhase.failed` alone would pass every unit test
// and nag on every manual retry.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_check_failed_notice.dart -d windows

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

final _notice = find.byKey(const ValueKey('update-check-failed'));
final _noticeMessage = find.byKey(
  const ValueKey('update-check-failed-message'),
);
final _noticeClose = find.byKey(const ValueKey('update-check-failed-dismiss'));
final _offerBar = find.byKey(const ValueKey('update-offer'));
final _aboutStatus = find.byKey(const ValueKey('about-update-status'));
final _aboutCheck = find.byKey(const ValueKey('about-update-check'));

/// Scrolls About's update controls into view on the Options page.
Future<void> _openAbout(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Options'));
  await pumpUntilFound(tester, find.byType(OptionsPage));
  await tester.scrollUntilVisible(
    _aboutCheck,
    200,
    scrollable: optionsScrollable(),
  );
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed launch check is announced in the shell, can be closed, '
      'and leaves its reason in About', (tester) async {
    final server = await FakeReleaseServer.start(
      status: 500,
      rawBody: 'upstream is having a day',
    );

    final harness = AppHarness(updateFeedUrl: server.feedUrl);
    await harness.boot(tester);

    // The strip goes up where the offer bar would, and only the strip: no
    // dialog, no offer, the shell usable underneath.
    await pumpUntilFound(tester, _notice);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_offerBar, findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    expect(
      tester.widget<Text>(_noticeMessage).data,
      'Checking for updates did not succeed — see Options → About.',
    );
    // The server's words are for About, not for the strip.
    expect(find.textContaining('HTTP 500'), findsNothing);

    await tester.tap(_noticeClose);
    await pumpUntilGone(tester, _notice);

    // It stays closed: frames later it has not come back...
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_notice, findsNothing);
    expect(
      server.releaseRequests,
      1,
      reason: 'closing the notice re-ran the check',
    );

    // ...and About still says what went wrong, as the notice promised.
    await _openAbout(tester);
    expect(
      tester.widget<Text>(_aboutStatus).data,
      allOf(startsWith('The update did not succeed'), contains('HTTP 500')),
    );

    await harness.dispose(tester);
    await server.close();
  });

  testWidgets('a failed manual check from About is not announced', (
    tester,
  ) async {
    final server = await FakeReleaseServer.start(
      status: 500,
      rawBody: 'upstream is having a day',
    );

    final harness = AppHarness(
      updateFeedUrl: server.feedUrl,
      // The app's own gate: a test binary never checks by itself, so the
      // only check here is the one the button starts.
      forceUpdateCheck: false,
    );
    await harness.boot(tester);
    await _openAbout(tester);
    expect(server.releaseRequests, 0);

    await tester.tap(_aboutCheck);
    await pumpUntil(
      tester,
      () => server.releaseRequests > 0,
      reason: 'the button never asked for the latest release',
    );
    await pumpUntil(
      tester,
      () =>
          tester.widget<Text>(_aboutStatus).data?.contains('HTTP 500') ?? false,
      reason: 'About never reported the failure inline',
    );

    // The person who pressed the button is looking at the answer already.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_notice, findsNothing, reason: 'a manual check raised the strip');
    expect(_offerBar, findsNothing);

    await harness.dispose(tester);
    await server.close();
  });
}
