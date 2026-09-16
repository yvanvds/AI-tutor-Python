// End-to-end (#133): the real app, on a network where only the proxy has a
// route out, finds its release, downloads it, verifies it and hands it to
// the installer — through the proxy.
//
// The production symptom: on a school network with an explicit proxy, Dart's
// `HttpClient` ignores the Windows proxy setting and dials `api.github.com`
// directly. The firewall drops that, the check reports "request … timed out
// after 10s", and a student is stuck on an old build. The `curl.exe`
// fallback #124 added does not help by itself — it engages only on a
// handshake failure, and was told nothing about the proxy either.
//
// `BlackHole` and `LoopbackProxy` (test/helpers/loopback_proxy.dart)
// reproduce that network on the loopback interface: the release server is
// addressed at the hole, which accepts every connection and answers none,
// and the proxy is the one thing that routes that address to the real
// `FakeReleaseServer`. The first test proves the premise — with no proxy
// configured the app times out, the server never hears from it, and the
// failure is announced. The second hands the app the proxy the way
// `update_bootstrap.dart` would have read it from Internet Options, and
// drives the whole update through it on Dart's own transport: release,
// checksum and installer all tunnel through the proxy, none of them reach
// the hole, and the sha256 check still stands before the handover. The
// third is the combination a managed school network actually presents —
// an explicit proxy *and* TLS inspection — where Dart fails the handshake
// inside the tunnel and the fallback, built with the same proxy, carries
// the check.
//
// Dart trusts the loopback certificate in the second test only through
// `TrustLoopbackCertificate`, the test-side stand-in for a CA that sits in
// the Windows root store, which Dart honours on its own. Nothing in `lib/`
// is touched by it, and it is cleared again when the test ends.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/update_proxy.dart -d windows

import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/loopback_proxy.dart';
import '../../test/helpers/loopback_tls.dart';
import '../harness/app_harness.dart';
import '../harness/fake_release_server.dart';

final _offerBar = find.byKey(const ValueKey('update-offer'));
final _applyButton = find.byKey(const ValueKey('update-offer-apply'));
final _notice = find.byKey(const ValueKey('update-check-failed'));

/// The network: a hole the app is pointed at, a release server it cannot
/// reach, and a proxy that can.
Future<({BlackHole hole, FakeReleaseServer server, LoopbackProxy proxy})>
_proxiedNetwork({Uint8List? installerBytes}) async {
  final hole = await BlackHole.start();
  final server = await FakeReleaseServer.start(
    version: '99.0.0+1',
    installerBytes: installerBytes,
    installerSha256: installerBytes == null
        ? kFakeInstallerSha256
        : sha256.convert(installerBytes).toString(),
    tls: true,
    advertisedAuthority: hole.authority,
  );
  final proxy = await LoopbackProxy.start(
    routes: {hole.authority: server.authority},
  );
  return (hole: hole, server: server, proxy: proxy);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without the proxy setting, the check times out and says so', (
    tester,
  ) async {
    final net = await _proxiedNetwork();

    // No `proxy`: the app as it was, dialling out directly.
    final harness = AppHarness(updateFeedUrl: net.server.feedUrl);
    await harness.boot(tester);

    // The premise of the whole flow: the direct dial is swallowed, and the
    // request deadline is what ends the check.
    await pumpUntil(
      tester,
      () =>
          harness.container.read(updateControllerProvider).phase ==
          UpdatePhase.failed,
      timeout: const Duration(seconds: 25),
      reason: 'the check did not fail against a black-holed route',
    );
    expect(
      harness.container.read(updateControllerProvider).message,
      contains('timed out'),
      reason: 'the reason About shows is not the timeout',
    );
    expect(net.hole.connections, greaterThanOrEqualTo(1));
    expect(net.proxy.connects, isEmpty);
    expect(net.server.releaseRequests, 0);
    expect(_offerBar, findsNothing);
    // ...and, per #124, the failure is announced rather than buried.
    await pumpUntilFound(tester, _notice);

    await harness.dispose(tester);
    await net.proxy.close();
    await net.server.close();
    await net.hole.close();
  });

  testWidgets(
    'with the proxy setting, the update is found, verified and installed '
    'through the proxy on Dart\'s own transport',
    (tester) async {
      final installerBytes = Uint8List.fromList(
        List<int>.generate(48 * 1024, (i) => (i * 11) % 256),
      );
      final net = await _proxiedNetwork(installerBytes: installerBytes);

      // A CA in the root store, as far as Dart is concerned — for this test
      // and this certificate only.
      HttpOverrides.global = TrustLoopbackCertificate();
      addTearDown(() => HttpOverrides.global = null);

      final harness = AppHarness(
        updateFeedUrl: net.server.feedUrl,
        proxy: net.proxy.updateProxy,
      );
      await harness.boot(tester);

      // The offer arrives where it always does, and nothing announces a
      // failure, because there was none.
      await pumpUntilFound(tester, _offerBar);
      expect(find.textContaining('99.0.0+1'), findsOneWidget);
      expect(_notice, findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      // Both requests of the check tunnelled through the proxy to the hole's
      // address, and the hole itself heard nothing: Dart went where the
      // setting said, not where the URL said.
      expect(net.server.releaseRequests, 1);
      expect(net.server.checksumRequests, 1);
      expect(net.proxy.connects, isNotEmpty);
      expect(net.proxy.connects, everyElement(net.hole.authority));
      expect(net.hole.connections, 0, reason: 'the app dialled out directly');
      expect(
        harness.container
            .read(updateControllerProvider)
            .release
            ?.viaNativeTransport,
        isFalse,
        reason: 'the fallback was engaged on a network that did not need it',
      );

      await tester.tap(_applyButton);
      await pumpUntil(
        tester,
        () => harness.installerLaunches.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'the verified installer was never handed over',
      );

      // The installer came the same way — the download builds a client of
      // its own, and it too honoured the setting.
      expect(net.server.installerRequests, 1);
      expect(net.hole.connections, 0);

      // The handover is the ordinary one (#49): the file, verified against
      // the published hash, with the silent + relaunch switches.
      final launch = harness.installerLaunches.single;
      expect(File(launch.executable).readAsBytesSync(), installerBytes);
      expect(launch.arguments, containsAll(<String>['/SILENT', '/RELAUNCH=1']));

      await harness.dispose(tester);
      await net.proxy.close();
      await net.server.close();
      await net.hole.close();
      final downloaded = File(launch.executable);
      if (downloaded.existsSync()) downloaded.deleteSync();
    },
  );

  testWidgets(
    'behind a proxy that also inspects TLS, the fallback carries the check '
    'through the same proxy',
    (tester) async {
      final net = await _proxiedNetwork();
      // No `HttpOverrides` this time: Dart cannot verify the certificate it
      // meets inside the tunnel, exactly as it cannot verify a filter's.
      final trusting = TrustingLoopbackGet(proxy: net.proxy.updateProxy);

      final harness = AppHarness(
        updateFeedUrl: net.server.feedUrl,
        proxy: net.proxy.updateProxy,
        nativeGet: trusting.call,
      );
      await harness.boot(tester);

      await pumpUntilFound(tester, _offerBar);
      expect(_notice, findsNothing);
      expect(
        harness.container
            .read(updateControllerProvider)
            .release
            ?.viaNativeTransport,
        isTrue,
        reason: 'Dart got through a handshake it should have failed',
      );

      // Dart's attempt and the fallback's requests all went through the
      // proxy — the hole heard nothing — and the fallback, built with the
      // same proxy, is what brought the release and the checksum back.
      expect(
        trusting.calls.map((c) => c.url.path),
        containsAllInOrder(<String>[
          '/repos/yvanvds/AI-tutor-Python/releases/latest',
          '/download/python_teacher_install.exe.sha256',
        ]),
      );
      expect(net.server.releaseRequests, 1);
      expect(net.server.checksumRequests, 1);
      expect(net.proxy.connects.length, greaterThanOrEqualTo(3));
      expect(net.proxy.connects, everyElement(net.hole.authority));
      expect(net.hole.connections, 0, reason: 'something dialled out directly');

      await harness.dispose(tester);
      await net.proxy.close();
      await net.server.close();
      await net.hole.close();
    },
  );
}
