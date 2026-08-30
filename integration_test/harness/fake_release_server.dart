// A loopback stand-in for GitHub's Releases API (#50), so an end-to-end flow
// can drive the real update check without reaching github.com.
//
// It answers the three requests the app makes, in the shapes GitHub actually
// uses — which is the part that matters:
//
//   - `/repos/<owner>/<repo>/releases/latest` with the release JSON,
//     `application/json; charset=utf-8`;
//   - the `.sha256` asset as `application/octet-stream`, the content type a
//     release asset really carries, optionally with the UTF-8 BOM that
//     `build_release.ps1` has put in front of a generated file before (#45);
//   - the installer itself with a 404 unless a flow opts in with
//     [FakeReleaseServer.start]'s `installerBytes` — and even then the bytes
//     are junk whose hash cannot match the published one, so the real
//     verify-then-run wiring stops before anything is spawned. A test run
//     must never start a setup binary on the machine it is running on.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A well-formed hash that no download will ever match.
///
/// Every flow here either stops at the offer or drives the download through
/// to its checksum failure; nothing served by this server is ever meant to
/// pass verification.
const String kFakeInstallerSha256 =
    '0000000000000000000000000000000000000000000000000000000000000000';

class FakeReleaseServer {
  FakeReleaseServer._(this._server, this.feedUrl);

  final HttpServer _server;

  /// What the harness's `updateFeedUrl` is pointed at.
  final Uri feedUrl;

  /// How often the app asked for the release / the checksum asset / the
  /// installer. A flow that has to prove the app did *not* act — nothing
  /// fetched on a debug build, nothing downloaded after **Later** — asserts
  /// on these.
  int releaseRequests = 0;
  int checksumRequests = 0;
  int installerRequests = 0;

  static const String _installerName = 'python_teacher_install.exe';
  static const String _feedPath =
      '/repos/yvanvds/AI-tutor-Python/releases/latest';

  /// Binds a server on the loopback interface and starts answering.
  ///
  /// [rawBody] replaces the generated release payload verbatim, for the
  /// malformed-payload flows; everything else describes a well-formed
  /// release.
  /// [installerBytes] opts into actually serving the installer asset, in
  /// [installerChunks] pieces spaced [chunkDelay] apart and with a declared
  /// `Content-Length`, so a flow can watch the progress bar fill. The bytes
  /// are junk: their hash is not [kFakeInstallerSha256], so the app's own
  /// verify step rejects them and never reaches `Process.start`. Left `null`
  /// the installer is a 404, as it was before (#50).
  static Future<FakeReleaseServer> start({
    int status = HttpStatus.ok,
    String? rawBody,
    String version = '99.0.0+1',
    bool withInstallerAsset = true,
    bool withChecksumAsset = true,
    bool checksumBom = false,
    Uint8List? installerBytes,
    int installerChunks = 5,
    Duration chunkDelay = const Duration(milliseconds: 120),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://${server.address.address}:${server.port}';
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
          'body': 'What changed in $version.',
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
          utf8.encode('$kFakeInstallerSha256  $_installerName\n'),
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
