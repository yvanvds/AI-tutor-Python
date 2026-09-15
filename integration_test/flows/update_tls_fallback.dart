// End-to-end (#124): the real app, booted against a Releases API whose
// certificate Dart cannot verify, still finds the release, downloads it,
// verifies it and hands it to the installer — through the fallback transport.
//
// The production symptom: on a school network that inspects TLS, or a
// laptop whose antivirus does, every certificate the app sees is re-signed
// by a CA that sits in the Windows store. Edge and `curl.exe` trust it
// through Schannel; Dart's BoringSSL does not, and `fetchLatestRelease` died
// with `HandshakeException: CERTIFICATE_VERIFY_FAILED`. Students on 2.1.0
// were two releases behind, and the only trace was a line in About.
//
// `FakeReleaseServer` with `tls: true` reproduces exactly that: a
// self-signed certificate (`loopback_tls.dart`) that is in no store at all.
// The first test proves the premise before relying on it — with no fallback
// transport the app fails the check with the real handshake error, which is
// also what a Windows 10 install without `curl.exe` sees. The second gives
// the harness a transport that trusts that one certificate, the way the
// shipped `curl.exe` trusts the school's CA, and drives the whole update
// through it: release, checksum and installer all arrive on the fallback,
// none of them on Dart, and the sha256 check still stands between the
// download and the handover.
//
// Why a stand-in and not the real `curl.exe`: Schannel refuses the loopback
// certificate for the same reason Dart does, and installing a test CA into
// the machine's store is not something a test may do. The binary's own
// command line is pinned against a fake runner and one real loopback round
// trip in `test/core/update_bootstrap_test.dart`.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_tls_fallback.dart -d windows

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

final _offerBar = find.byKey(const ValueKey('update-offer'));
final _offerMessage = find.byKey(const ValueKey('update-offer-message'));
final _applyButton = find.byKey(const ValueKey('update-offer-apply'));
final _notice = find.byKey(const ValueKey('update-check-failed'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without a fallback transport, a certificate Dart cannot verify '
      'fails the check with the handshake reason', (tester) async {
    final server = await FakeReleaseServer.start(
      version: '99.0.0+1',
      tls: true,
    );

    // No `nativeGet`: a machine with nothing to fall back to.
    final harness = AppHarness(updateFeedUrl: server.feedUrl);
    await harness.boot(tester);

    // The premise of the whole flow: Dart never gets past the handshake, so
    // the server never sees a request and the app reports the failure.
    await pumpUntil(
      tester,
      () =>
          harness.container.read(updateControllerProvider).phase ==
          UpdatePhase.failed,
      reason: 'the check did not fail against an unverifiable certificate',
    );
    expect(
      server.releaseRequests,
      0,
      reason: 'Dart got through the TLS handshake',
    );
    expect(_offerBar, findsNothing);
    expect(
      harness.container.read(updateControllerProvider).message,
      contains('CERTIFICATE_VERIFY_FAILED'),
      reason: 'the reason About shows is not the handshake failure',
    );
    // ...and, per Part 2, the failure is announced rather than buried.
    await pumpUntilFound(tester, _notice);

    await harness.dispose(tester);
    await server.close();
  });

  testWidgets('with the fallback, the update is found, verified and installed '
      'entirely through it', (tester) async {
    final installerBytes = Uint8List.fromList(
      List<int>.generate(48 * 1024, (i) => (i * 11) % 256),
    );
    final server = await FakeReleaseServer.start(
      version: '99.0.0+1',
      installerBytes: installerBytes,
      installerSha256: sha256.convert(installerBytes).toString(),
      tls: true,
    );
    final trusting = TrustingLoopbackGet();

    final harness = AppHarness(
      updateFeedUrl: server.feedUrl,
      nativeGet: trusting.call,
    );
    await harness.boot(tester);

    // The offer arrives where it always does — the shell's own strip — and
    // nothing announces a failure, because there was none to announce.
    await pumpUntilFound(tester, _offerBar);
    expect(find.textContaining('99.0.0+1'), findsOneWidget);
    expect(_notice, findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    // Both requests of the check went through the fallback: the release
    // because Dart failed its handshake, the checksum because there was
    // nothing to learn from failing it again.
    expect(
      trusting.calls.map((c) => c.url.path),
      containsAllInOrder(<String>[
        '/repos/yvanvds/AI-tutor-Python/releases/latest',
        '/download/python_teacher_install.exe.sha256',
      ]),
    );
    expect(
      trusting.calls.first.headers['Accept'],
      'application/vnd.github+json',
      reason: 'the fallback did not ask the API the documented way',
    );
    expect(server.releaseRequests, 1);
    expect(server.checksumRequests, 1);
    expect(
      harness.container
          .read(updateControllerProvider)
          .release
          ?.viaNativeTransport,
      isTrue,
      reason: 'the release does not remember which transport found it',
    );

    await tester.tap(_applyButton);
    await pumpUntil(
      tester,
      () => harness.installerLaunches.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the verified installer was never handed over',
    );

    // The installer came the same way — straight to the fallback, not via a
    // second failed handshake — and only once.
    expect(
      trusting.calls.last.url.path,
      '/download/python_teacher_install.exe',
    );
    expect(trusting.calls, hasLength(3));
    expect(server.installerRequests, 1);

    // The handover is the ordinary one (#49): the file the fallback wrote,
    // verified against the published hash, with the silent + relaunch
    // switches. Nothing about the transport changed what runs.
    final launch = harness.installerLaunches.single;
    expect(
      launch.executable,
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'python_teacher_install.exe',
    );
    expect(File(launch.executable).readAsBytesSync(), installerBytes);
    expect(launch.arguments, containsAll(<String>['/SILENT', '/RELAUNCH=1']));
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
