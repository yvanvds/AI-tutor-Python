// A loopback stand-in for GitHub's Releases API (#50), so an end-to-end flow
// can drive the real update check without reaching github.com.
//
// It answers the four requests the app makes, in the shapes GitHub actually
// uses — which is the part that matters:
//
//   - `/repos/<owner>/<repo>/releases/latest` with the release JSON,
//     `application/json; charset=utf-8`;
//   - `/repos/<owner>/<repo>/releases/tags/v<version>` — the by-tag lookup
//     behind About's **What's new** button (#130) — with the same JSON for
//     the one version it publishes and a 404 for any other tag, as GitHub
//     answers a tag that was never released;
//   - the `.sha256` asset as `application/octet-stream`, the content type a
//     release asset really carries, optionally with the UTF-8 BOM that
//     `build_release.ps1` has put in front of a generated file before (#45);
//   - the installer itself with a 404 unless a flow opts in with
//     [FakeReleaseServer.start]'s `installerBytes` — junk bytes whose hash
//     cannot match the published one unless the flow also publishes their
//     real hash with `installerSha256`. Nothing here ever spawns a setup
//     binary either way: the harness always replaces the installer launcher
//     (#49), because a test run must never start a real setup on the machine
//     it is running on.
//
// With `tls: true` (#124) it serves all of that over HTTPS with a self-signed
// certificate (`loopback_tls.dart`), which Dart's own TLS stack refuses with
// `CERTIFICATE_VERIFY_FAILED` — the production symptom on a school network
// that inspects TLS. [TrustingLoopbackGet] is the stand-in for the `curl.exe`
// the app falls back to on such a network: it trusts exactly this
// certificate, the way Schannel trusts the filter's CA from the Windows
// store, and (#140) answers a loopback proxy's login challenge the way SSPI
// answers the school's. The real binary cannot be used here — it would
// refuse the loopback certificate for the same reason Dart does, and putting
// a test CA in the machine's store is not something a test may do.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/update_proxy.dart';
import 'package:http/http.dart' as http;

import '../../test/helpers/loopback_tls.dart';

/// A well-formed hash that no download will ever match.
///
/// Every flow here either stops at the offer or drives the download through
/// to its checksum failure; nothing served by this server is ever meant to
/// pass verification.
const String kFakeInstallerSha256 =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// A [NativeGet] that trusts the loopback certificate — and only that one —
/// standing in for the Windows-native `curl.exe` transport in a flow that
/// drives the fallback end-to-end (#124). Records every request it makes on
/// [calls], so a flow can prove the fallback carried the check, the checksum
/// and the installer rather than any of them getting through on Dart.
///
/// Built with the machine's [proxy], as the real one is (#133): the
/// production wiring hands `curlNativeGet` the same `UpdateProxy` it hands
/// Dart's client, and this stand-in honours it the same way. With a
/// [proxyLogin] it also answers that proxy's login challenge (#140), the
/// way the real `curl.exe` answers a school proxy's through SSPI with the
/// Windows login: `user:pass`, sent as a Basic `Proxy-Authorization` on the
/// CONNECT. The app's own client is never given one — it has none — which
/// is the whole difference the flow drives.
class TrustingLoopbackGet {
  TrustingLoopbackGet({this.proxy, this.proxyLogin});

  final UpdateProxy? proxy;

  /// The login the stand-in answers [proxy]'s challenge with, or `null` to
  /// answer none — in which case it fails on a 407 exactly as Dart does.
  final String? proxyLogin;

  final List<({Uri url, Map<String, String> headers, File? to})> calls = [];

  Future<http.Response> call(
    Uri url, {
    Map<String, String> headers = const <String, String>{},
    Duration? timeout,
    File? to,
  }) async {
    calls.add((url: url, headers: headers, to: to));
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          host == InternetAddress.loopbackIPv4.address &&
          isLoopbackCertificate(cert);
    final UpdateProxy? via = proxy;
    final String? login = proxyLogin;
    if (via != null) {
      client.findProxy = login == null
          ? via.findProxy
          : UpdateProxy(
              via.url.replace(userInfo: login),
              bypass: via.bypass,
            ).findProxy;
    }
    try {
      final HttpClientRequest request = await client.getUrl(url);
      headers.forEach(request.headers.set);
      final HttpClientResponse response = await request.close();
      if (to != null) {
        final IOSink sink = to.openWrite();
        await response.pipe(sink);
        return http.Response.bytes(Uint8List(0), response.statusCode);
      }
      final BytesBuilder body = BytesBuilder(copy: false);
      await for (final List<int> chunk in response) {
        body.add(chunk);
      }
      return http.Response.bytes(body.takeBytes(), response.statusCode);
    } on HandshakeException catch (e) {
      // The stand-in refused something: not this flow's certificate, so not
      // this flow's server. Say so rather than look like a network error.
      throw UpdateCheckException('loopback stand-in refused $url: $e');
    } finally {
      client.close(force: true);
    }
  }
}

class FakeReleaseServer {
  FakeReleaseServer._(this._server, this.feedUrl);

  final HttpServer _server;

  /// What the harness's `updateFeedUrl` is pointed at.
  final Uri feedUrl;

  /// Where the server actually listens, as `host:port` — the same as the
  /// feed URL's authority unless [start] was given an `advertisedAuthority`,
  /// in which case this is what a proxy's route has to point at (#133).
  String get authority => '${_server.address.address}:${_server.port}';

  /// How often the app asked for the release / the checksum asset / the
  /// installer / a release by its tag (#130). A flow that has to prove the
  /// app did *not* act — nothing fetched on a debug build, nothing
  /// downloaded after **Later**, notes shown from the stash without a
  /// lookup — asserts on these.
  int releaseRequests = 0;
  int checksumRequests = 0;
  int installerRequests = 0;
  int tagRequests = 0;

  static const String _installerName = 'python_teacher_install.exe';
  static const String _releasesPath = '/repos/yvanvds/AI-tutor-Python/releases';
  static const String _feedPath = '$_releasesPath/latest';

  /// Binds a server on the loopback interface and starts answering.
  ///
  /// [rawBody] replaces the generated release payload verbatim, for the
  /// malformed-payload flows; everything else describes a well-formed
  /// release.
  /// [installerBytes] opts into actually serving the installer asset, in
  /// [installerChunks] pieces spaced [chunkDelay] apart and with a declared
  /// `Content-Length`, so a flow can watch the progress bar fill. By default
  /// the published hash is [kFakeInstallerSha256], which nothing matches, so
  /// the app's own verify step rejects the download. A flow that needs the
  /// app to get past verification — the install handover (#49) — passes
  /// [installerSha256] as the real hash of the bytes it serves. Left `null`
  /// the installer is a 404, as it was before (#50).
  /// [tls] serves everything over HTTPS with the self-signed loopback
  /// certificate, which Dart cannot verify (#124) — see the file comment.
  /// [advertisedAuthority] is the `host:port` the feed URL and the asset
  /// links name instead of the server's own — for a flow that puts a proxy
  /// between the app and this server (#133), it is the address only the
  /// proxy has a route to.
  /// [notes] is the release body — what GitHub returns as `body`, Markdown
  /// by origin. A flow that shows the notes (#119, #130, #137) publishes a
  /// body with some Markdown in it; the default is one plain sentence.
  static Future<FakeReleaseServer> start({
    int status = HttpStatus.ok,
    String? rawBody,
    String version = '99.0.0+1',
    String? notes,
    bool withInstallerAsset = true,
    bool withChecksumAsset = true,
    bool checksumBom = false,
    Uint8List? installerBytes,
    String installerSha256 = kFakeInstallerSha256,
    int installerChunks = 5,
    Duration chunkDelay = const Duration(milliseconds: 120),
    bool tls = false,
    String? advertisedAuthority,
  }) async {
    final HttpServer server;
    if (tls) {
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(kLoopbackCertificatePem))
        ..usePrivateKeyBytes(utf8.encode(kLoopbackPrivateKeyPem));
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
    } else {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    final scheme = tls ? 'https' : 'http';
    final authority =
        advertisedAuthority ?? '${server.address.address}:${server.port}';
    final base = '$scheme://$authority';
    final fake = FakeReleaseServer._(server, Uri.parse('$base$_feedPath'));

    final assets = <Map<String, Object?>>[
      if (withInstallerAsset)
        {
          'name': _installerName,
          'browser_download_url': '$base/download/$_installerName',
        },
      if (withChecksumAsset)
        {
          'name': '$_installerName.sha256',
          'browser_download_url': '$base/download/$_installerName.sha256',
        },
    ];
    final body =
        rawBody ??
        jsonEncode(<String, Object?>{
          'tag_name': 'v$version',
          'body': notes ?? 'What changed in $version.',
          'html_url': '$base/releases/tag/v$version',
          'assets': assets,
        });

    server.listen((request) async {
      final path = request.uri.path;
      if (path == _feedPath) {
        fake.releaseRequests++;
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.response.add(utf8.encode(body));
      } else if (path.startsWith('$_releasesPath/tags/')) {
        fake.tagRequests++;
        if (path == '$_releasesPath/tags/v$version') {
          request.response.statusCode = status;
          request.response.headers.contentType = ContentType(
            'application',
            'json',
            charset: 'utf-8',
          );
          request.response.add(utf8.encode(body));
        } else {
          // No release under that tag — what a dev build's version gets.
          request.response.statusCode = HttpStatus.notFound;
        }
      } else if (path.endsWith('.sha256')) {
        fake.checksumRequests++;
        // No charset: `package:http` falls back to latin1 for this type, so
        // reading `res.body` instead of `res.bodyBytes` turns a BOM into
        // three characters in front of the hash (#45).
        request.response.headers.contentType = ContentType(
          'application',
          'octet-stream',
        );
        if (checksumBom) request.response.add(const [0xEF, 0xBB, 0xBF]);
        request.response.add(
          utf8.encode('$installerSha256  $_installerName\n'),
        );
      } else if (path.endsWith(_installerName) && installerBytes != null) {
        fake.installerRequests++;
        request.response.headers.contentType = ContentType(
          'application',
          'octet-stream',
        );
        // Declared, because a download with no length has no denominator and
        // the bar stays indeterminate — the opposite of what this serves.
        request.response.contentLength = installerBytes.length;
        final step = math.max(
          1,
          (installerBytes.length / installerChunks).ceil(),
        );
        for (var i = 0; i < installerBytes.length; i += step) {
          request.response.add(
            installerBytes.sublist(
              i,
              math.min(i + step, installerBytes.length),
            ),
          );
          await request.response.flush();
          await Future<void>.delayed(chunkDelay);
        }
      } else {
        // Including the installer, unless a flow opted in above.
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    return fake;
  }

  Future<void> close() => _server.close(force: true);
}
