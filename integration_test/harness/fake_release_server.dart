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
//   - the installer itself with a 404, deliberately: a test run must never
//     spawn a setup binary on the machine it is running on.

import 'dart:convert';
import 'dart:io';

/// A well-formed hash that no download will ever match. The flows here stop
/// at the offer; the installer request is answered with a 404.
const String kFakeInstallerSha256 =
    '0000000000000000000000000000000000000000000000000000000000000000';

class FakeReleaseServer {
  FakeReleaseServer._(this._server, this.feedUrl);

  final HttpServer _server;

  /// What the harness's `updateFeedUrl` is pointed at.
  final Uri feedUrl;

  /// How often the app asked for the release / the checksum asset. A flow
  /// that has to prove the app stayed off the network asserts on these.
  int releaseRequests = 0;
  int checksumRequests = 0;

  static const String _installerName = 'python_teacher_install.exe';
  static const String _feedPath =
      '/repos/yvanvds/AI-tutor-Python/releases/latest';

  /// Binds a server on the loopback interface and starts answering.
  ///
  /// [rawBody] replaces the generated release payload verbatim, for the
  /// malformed-payload flows; everything else describes a well-formed
  /// release.
  static Future<FakeReleaseServer> start({
    int status = HttpStatus.ok,
    String? rawBody,
    String version = '99.0.0+1',
    bool withInstallerAsset = true,
    bool withChecksumAsset = true,
    bool checksumBom = false,
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
      } else {
        // Including the installer: this must never be served.
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    return fake;
  }

  Future<void> close() => _server.close(force: true);
}
