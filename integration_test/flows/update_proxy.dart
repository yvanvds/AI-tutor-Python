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
// the check. The fourth (#135) states the proxy the other way a school
// does — not in Internet Options' proxy box but as a PAC script the
// machine is told to fetch — and hands the app nothing resolved: the real
// WinHTTP fetches the script from a loopback `LoopbackPacServer`, evaluates
// it for the feed URL, and the proxy it names is the one the whole update
// then goes through. That test advertises the release server under a
// school hostname rather than at the hole: WinHTTP answers DIRECT for a
// loopback target before it consults any script (the same built-in bypass
// Edge has), and a name only the proxy knows the way to is what a school's
// filter looks like anyway — Dart never resolves it, since through a proxy
// it only ever sends `CONNECT host:port`. The fifth and sixth (#140) make
// the proxy *authenticate*, as an AD-joined filter does: it refuses every
// CONNECT that carries no `Proxy-Authorization` with a 407. Dart's client
// has no login to give — the student is logged in to Windows, not to the
// app — so the fifth shows the check failing on it and About saying, in
// plain words, that the proxy asks for a login; the sixth hands the app a
// fallback that answers the challenge, the way the shipped `curl.exe`
// answers a school proxy's through SSPI with the Windows login, and drives
// the whole update through it: the 407 engages the fallback, the checksum
// and the installer follow it without being challenged again, and the
// offer bar appears where it always does.
//
// Dart trusts the loopback certificate in the second, fifth and sixth tests
// only through `TrustLoopbackCertificate`, the test-side stand-in for a CA
// that sits in the Windows root store, which Dart honours on its own.
// Nothing in `lib/` is touched by it, and it is cleared again when the test
// ends. In the fifth and sixth it is what makes the login the *only* thing
// in Dart's way.
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

/// Where the PAC flow says the release server is: a name on the school
/// network, on a port that stays visible in the URL and the CONNECT alike.
const String _schoolAuthority = 'updates.school.test:8443';

/// What the fallback stand-in answers the proxy's challenge with (#140):
/// the Windows login, as far as this flow is concerned. The proxy accepts
/// any login and verifies none; what it records is that one was given.
const String _windowsLogin = 'student:hunter2';

/// The network: a hole the app is pointed at, a release server it cannot
/// reach, and a proxy that can. The server is advertised at the hole unless
/// [advertisedAuthority] says otherwise; either way the proxy alone routes
/// that authority to the server. With [requireLogin] the proxy refuses a
/// CONNECT that carries no login (#140).
Future<({BlackHole hole, FakeReleaseServer server, LoopbackProxy proxy})>
_proxiedNetwork({
  Uint8List? installerBytes,
  String? advertisedAuthority,
  bool requireLogin = false,
}) async {
  final hole = await BlackHole.start();
  final String authority = advertisedAuthority ?? hole.authority;
  final server = await FakeReleaseServer.start(
    version: '99.0.0+1',
    installerBytes: installerBytes,
    installerSha256: installerBytes == null
        ? kFakeInstallerSha256
        : sha256.convert(installerBytes).toString(),
    tls: true,
    advertisedAuthority: authority,
  );
  final proxy = await LoopbackProxy.start(
    routes: {authority: server.authority},
    requireLogin: requireLogin,
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

  testWidgets(
    'with only a PAC script naming the proxy, the update is found, verified '
    'and installed through the proxy WinHTTP resolves from it',
    (tester) async {
      final installerBytes = Uint8List.fromList(
        List<int>.generate(48 * 1024, (i) => (i * 7) % 256),
      );
      final net = await _proxiedNetwork(
        installerBytes: installerBytes,
        advertisedAuthority: _schoolAuthority,
      );
      // What the school publishes at its AutoConfigURL: every URL through
      // the proxy — the one route to the release server.
      final pac = await LoopbackPacServer.start(
        script: pacScript(proxy: '127.0.0.1:${net.proxy.port}'),
      );

      HttpOverrides.global = TrustLoopbackCertificate(
        hosts: <String>[Uri.parse('https://$_schoolAuthority').host],
      );
      addTearDown(() => HttpOverrides.global = null);

      // No `proxy`: the app is told where the script is, as Internet
      // Options would tell it, and resolves the rest itself.
      final harness = AppHarness(
        updateFeedUrl: net.server.feedUrl,
        pacUrl: pac.url,
      );
      await harness.boot(tester);

      await pumpUntilFound(tester, _offerBar);
      expect(find.textContaining('99.0.0+1'), findsOneWidget);
      expect(_notice, findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      // WinHTTP came for the script, and what it evaluated is what the
      // check went through: both requests tunnelled through the proxy to
      // the school name, which nothing else could have reached.
      expect(pac.fetches, greaterThanOrEqualTo(1));
      expect(net.server.releaseRequests, 1);
      expect(net.server.checksumRequests, 1);
      expect(net.proxy.connects, isNotEmpty);
      expect(net.proxy.connects, everyElement(_schoolAuthority));
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

      // The installer came the same way: the download awaited the same
      // resolution, and it too went through the proxy the script named.
      expect(net.server.installerRequests, 1);
      expect(net.proxy.connects, everyElement(_schoolAuthority));
      final launch = harness.installerLaunches.single;
      expect(File(launch.executable).readAsBytesSync(), installerBytes);
      expect(launch.arguments, containsAll(<String>['/SILENT', '/RELAUNCH=1']));

      await harness.dispose(tester);
      await pac.close();
      await net.proxy.close();
      await net.server.close();
      await net.hole.close();
      final downloaded = File(launch.executable);
      if (downloaded.existsSync()) downloaded.deleteSync();
    },
  );

  testWidgets(
    'behind a proxy that asks for a login, Dart\'s own transport cannot '
    'answer and About says so in plain words',
    (tester) async {
      final net = await _proxiedNetwork(requireLogin: true);
      // The certificate is trusted, so the login is the only thing in the
      // way — and it is enough.
      HttpOverrides.global = TrustLoopbackCertificate();
      addTearDown(() => HttpOverrides.global = null);

      // The proxy setting as the app resolved it, and no fallback: a
      // machine with nothing that can answer the challenge.
      final harness = AppHarness(
        updateFeedUrl: net.server.feedUrl,
        proxy: net.proxy.updateProxy,
      );
      await harness.boot(tester);

      await pumpUntil(
        tester,
        () =>
            harness.container.read(updateControllerProvider).phase ==
            UpdatePhase.failed,
        timeout: const Duration(seconds: 25),
        reason: 'the check did not fail against a proxy that wants a login',
      );
      // Not "ClientException: Proxy failed to establish tunnel (407 …)":
      // the reason About shows is one a student can pass on.
      expect(
        harness.container.read(updateControllerProvider).message,
        allOf(
          contains("the network's proxy asks for a login"),
          isNot(contains('ClientException')),
        ),
      );
      // The proxy was asked, refused, and never given a login; the server
      // never heard from the app, and nothing dialled out directly.
      expect(net.proxy.challenges, greaterThanOrEqualTo(1));
      expect(net.proxy.logins, isEmpty, reason: 'the app has no login');
      expect(net.server.releaseRequests, 0);
      expect(net.hole.connections, 0);
      expect(_offerBar, findsNothing);
      // ...and, per #124, the failure is announced rather than buried.
      await pumpUntilFound(tester, _notice);

      await harness.dispose(tester);
      await net.proxy.close();
      await net.server.close();
      await net.hole.close();
    },
  );

  testWidgets(
    'behind a proxy that asks for a login, the fallback answers it and '
    'carries the update through',
    (tester) async {
      final installerBytes = Uint8List.fromList(
        List<int>.generate(48 * 1024, (i) => (i * 13) % 256),
      );
      final net = await _proxiedNetwork(
        installerBytes: installerBytes,
        requireLogin: true,
      );
      // Same trust as above: what pushes the check to the fallback here is
      // the login alone, not a handshake.
      HttpOverrides.global = TrustLoopbackCertificate();
      addTearDown(() => HttpOverrides.global = null);
      // The stand-in for curl.exe: the same proxy, and a login to answer
      // its challenge with — what SSPI gives the real one.
      final trusting = TrustingLoopbackGet(
        proxy: net.proxy.updateProxy,
        proxyLogin: _windowsLogin,
      );

      final harness = AppHarness(
        updateFeedUrl: net.server.feedUrl,
        proxy: net.proxy.updateProxy,
        nativeGet: trusting.call,
      );
      await harness.boot(tester);

      // The offer arrives where it always does, and nothing announces a
      // failure: the 407 was a reason to fall back, not to give up.
      await pumpUntilFound(tester, _offerBar);
      expect(find.textContaining('99.0.0+1'), findsOneWidget);
      expect(_notice, findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        harness.container
            .read(updateControllerProvider)
            .release
            ?.viaNativeTransport,
        isTrue,
        reason: 'Dart got through a login challenge it cannot answer',
      );

      // Dart was challenged once, for the release, and never again: from
      // there the fallback carried the check, answering the proxy on every
      // CONNECT, and the checksum followed it without a second challenge.
      expect(
        trusting.calls.map((c) => c.url.path),
        containsAllInOrder(<String>[
          '/repos/yvanvds/AI-tutor-Python/releases/latest',
          '/download/python_teacher_install.exe.sha256',
        ]),
      );
      expect(net.proxy.challenges, 1);
      expect(net.proxy.logins, hasLength(2));
      expect(net.proxy.logins, everyElement(startsWith('Basic ')));
      expect(net.server.releaseRequests, 1);
      expect(net.server.checksumRequests, 1);
      expect(net.proxy.connects, everyElement(net.hole.authority));
      expect(net.hole.connections, 0, reason: 'something dialled out directly');

      await tester.tap(_applyButton);
      await pumpUntil(
        tester,
        () => harness.installerLaunches.isNotEmpty,
        timeout: const Duration(seconds: 30),
        reason: 'the verified installer was never handed over',
      );

      // The installer went straight to the fallback — the release remembers
      // which transport found it — so the proxy was answered a third time
      // and challenged no more.
      expect(
        trusting.calls.last.url.path,
        '/download/python_teacher_install.exe',
      );
      expect(net.server.installerRequests, 1);
      expect(net.proxy.challenges, 1);
      expect(net.proxy.logins, hasLength(3));
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
}
