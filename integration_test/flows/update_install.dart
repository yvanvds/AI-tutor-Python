// End-to-end (#49): the real app accepts a release, downloads and verifies it
// for real, and hands the installer the switches that make a student's update
// actually work.
//
// What #49 fixed lives in two places, and only one of them is Dart:
//
//   - `windows/packaging/exe/installer.iss` now installs per-user under
//     %LOCALAPPDATA%, so a silent install needs no administrator. That half
//     cannot be exercised from the app at all — running a real setup binary is
//     exactly what a test must never do.
//   - The app's half is the command line it passes: `/SILENT /NOCANCEL
//     /NORESTART /RELAUNCH=1`. `/RELAUNCH=1` is the custom switch the
//     installer's `WantsRelaunch` check reads, and it is the whole reason the
//     app comes back afterwards — the installer's ordinary `[Run]` entry is
//     `skipifsilent` and so is skipped in precisely the silent case. Before
//     this the app passed `/VERYSILENT /NORESTART` and simply never returned.
//
// So this flow drives the production wiring — the Releases API shape, the
// streamed download, the real sha256 over the bytes that arrived — to the one
// step it stops short of: the launcher, which the harness replaces because the
// real one spawns a setup and calls `exit(0)`. What it asserts is the handover
// itself: which file, which switches, and that the bar tells the student the
// app is coming back.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_install.dart -d windows

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

final _offerBar = find.byKey(const ValueKey('update-offer'));
final _offerMessage = find.byKey(const ValueKey('update-offer-message'));
final _applyButton = find.byKey(const ValueKey('update-offer-apply'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an accepted update reaches the installer with the silent + '
      'relaunch switches', (tester) async {
    // Not a real setup binary — nothing runs it. It only has to hash to the
    // value the release publishes, so the app's own verify step passes and
    // the flow reaches the handover.
    final installerBytes = Uint8List.fromList(
      List<int>.generate(48 * 1024, (i) => (i * 7) % 256),
    );
    final server = await FakeReleaseServer.start(
      version: '99.0.0+1',
      installerBytes: installerBytes,
      installerSha256: sha256.convert(installerBytes).toString(),
    );

    final harness = AppHarness(updateFeedUrl: server.feedUrl);
    await harness.boot(tester);

    await pumpUntilFound(tester, _offerBar);
    expect(harness.installerLaunches, isEmpty, reason: 'installed unasked');

    await tester.tap(_applyButton);
    await pumpUntil(
      tester,
      () => harness.installerLaunches.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the verified installer was never handed over',
    );

    final launch = harness.installerLaunches.single;
    expect(
      launch.executable,
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'python_teacher_install.exe',
      reason: 'a file other than the verified download was started',
    );
    expect(
      launch.arguments,
      // Order is not the contract, but every one of these is: /SILENT so the
      // student sees something happening, /NOCANCEL because there is no safe
      // point to abandon a half-replaced install, /NORESTART so the machine
      // is never rebooted underneath a lesson, and /RELAUNCH=1 so the app
      // comes back.
      containsAll(<String>[
        '/SILENT',
        '/NOCANCEL',
        '/NORESTART',
        '/RELAUNCH=1',
      ]),
    );
    expect(
      launch.arguments,
      isNot(contains('/VERYSILENT')),
      reason: '/VERYSILENT hides the install entirely and skips [Run]',
    );

    // And the student is told what is about to happen, rather than the window
    // just disappearing.
    expect(
      tester.widget<Text>(_offerMessage).data,
      allOf(contains('99.0.0+1'), contains('comes back')),
    );

    await harness.dispose(tester);
    await server.close();
    final downloaded = File(launch.executable);
    if (downloaded.existsSync()) downloaded.deleteSync();
  });
}
