// #50: the release feed no longer reads a hand-published `version.json`; it
// asks GitHub's `/releases/latest`. These pin the two halves that can go
// wrong on their own — reading a release payload, and reading the checksum
// asset that replaces the manifest's `sha256` field.
//
// #124 adds the third: what happens when Dart cannot complete the TLS
// handshake at all, which is what a school's TLS-inspecting filter does to
// it. The check has to retry through the Windows-native seam — for exactly
// that failure and no other.
//
// #133 the fourth: the client the check builds for itself has to go through
// the machine's proxy, which `package:http`'s default one never does.
//
// #130 the fifth: a second lookup on the same API, the release *by tag*
// behind About's "What's new" button. It reads one field and goes through
// the same transport, so the failures it reports are the check's failures.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/github_release.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/update_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/loopback_proxy.dart';
import '../helpers/loopback_tls.dart';

const String _installerUrl =
    'https://github.com/yvanvds/AI-tutor-Python/releases/download/'
    'v2.0.0+18/python_teacher_install.exe';
const String _checksumUrl = '$_installerUrl.sha256';
const String _hash =
    '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

Map<String, dynamic> _asset(String name, String url) => <String, dynamic>{
  'name': name,
  'browser_download_url': url,
};

Map<String, dynamic> _releaseJson({
  String tag = 'v2.0.0+18',
  List<Map<String, dynamic>>? assets,
  String body = 'Release notes here.',
}) => <String, dynamic>{
  'tag_name': tag,
  'body': body,
  'html_url': 'https://github.com/yvanvds/AI-tutor-Python/releases/tag/$tag',
  'assets':
      assets ??
      <Map<String, dynamic>>[
        _asset(kInstallerAssetName, _installerUrl),
        _asset(kChecksumAssetName, _checksumUrl),
      ],
};

/// Answers the release endpoint with [release] and the checksum asset with
/// [checksumBytes], the way GitHub does: JSON for the API, an
/// `application/octet-stream` blob for an asset.
MockClient _githubClient({
  required Map<String, dynamic> release,
  List<int>? checksumBytes,
  int releaseStatus = 200,
  int checksumStatus = 200,
}) => MockClient((request) async {
  if (request.url.path.endsWith('.sha256')) {
    return http.Response.bytes(
      checksumBytes ?? utf8.encode('$_hash  $kInstallerAssetName\n'),
      checksumStatus,
      headers: const {'content-type': 'application/octet-stream'},
    );
  }
  return http.Response.bytes(
    utf8.encode(jsonEncode(release)),
    releaseStatus,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
});

void main() {
  group('parseReleaseTag', () {
    test(
      'strips a leading v',
      () => expect(parseReleaseTag('v2.0.0+18'), '2.0.0+18'),
    );
    test(
      'accepts a bare version',
      () => expect(parseReleaseTag('2.0.0+18'), '2.0.0+18'),
    );
    test('accepts a version without a build', () {
      expect(parseReleaseTag('v2.1.0'), '2.1.0');
    });

    // A tag pushed by hand must not be able to crash a launch-time check.
    test('returns null for a tag that is not a version', () {
      expect(parseReleaseTag('nightly'), isNull);
      expect(parseReleaseTag('v'), isNull);
      expect(parseReleaseTag(''), isNull);
      expect(parseReleaseTag('v2.0'), isNull);
    });
  });

  group('releaseFromJson', () {
    test('reads version, installer, checksum and notes', () {
      final release = releaseFromJson(_releaseJson());
      expect(release, isNotNull);
      expect(release!.version, '2.0.0+18');
      expect(release.installerUrl, Uri.parse(_installerUrl));
      expect(release.checksumUrl, Uri.parse(_checksumUrl));
      expect(release.notes, 'Release notes here.');
      expect(release.pageUrl, contains('/releases/tag/'));
    });

    test('falls back to a lone .exe under another name', () {
      final release = releaseFromJson(
        _releaseJson(
          assets: [
            _asset('PythonTeacherSetup.exe', _installerUrl),
            _asset('PythonTeacherSetup.exe.sha256', _checksumUrl),
          ],
        ),
      );
      expect(release?.installerUrl, Uri.parse(_installerUrl));
      expect(release?.checksumUrl, Uri.parse(_checksumUrl));
    });

    // Two installers and no canonical name is not something to guess at.
    test('offers nothing when several .exe assets could be the one', () {
      expect(
        releaseFromJson(
          _releaseJson(
            assets: [
              _asset('one.exe', 'https://example.com/one.exe'),
              _asset('two.exe', 'https://example.com/two.exe'),
            ],
          ),
        ),
        isNull,
      );
    });

    // A source-only release is not something to offer a student.
    test('offers nothing for a release with no installer', () {
      expect(
        releaseFromJson(
          _releaseJson(
            assets: [_asset('notes.txt', 'https://example.com/notes.txt')],
          ),
        ),
        isNull,
      );
      expect(releaseFromJson(_releaseJson(assets: const [])), isNull);
    });

    test('offers nothing for a junk tag', () {
      expect(releaseFromJson(_releaseJson(tag: 'nightly')), isNull);
    });

    test('returns null for a payload that is not a release object', () {
      expect(releaseFromJson('nope'), isNull);
      expect(releaseFromJson(const []), isNull);
      expect(releaseFromJson(null), isNull);
      expect(
        releaseFromJson(<String, dynamic>{'message': 'Not Found'}),
        isNull,
      );
    });

    test('reports a missing checksum asset as null, not as a hash', () {
      final release = releaseFromJson(
        _releaseJson(assets: [_asset(kInstallerAssetName, _installerUrl)]),
      );
      expect(release, isNotNull);
      expect(release!.checksumUrl, isNull);
    });
  });

  group('parseSha256Document', () {
    test('reads a bare hash', () => expect(parseSha256Document(_hash), _hash));

    test('reads the sha256sum shape', () {
      expect(parseSha256Document('$_hash  $kInstallerAssetName\n'), _hash);
    });

    test('lower-cases what it returns', () {
      expect(parseSha256Document(_hash.toUpperCase()), _hash);
    });

    // #45: the release script writes this file, and a BOM in front of it is
    // exactly the mistake that killed the manifest for the life of the
    // feature. Here it would compare as a hash that never matches.
    test('tolerates a leading UTF-8 BOM', () {
      expect(parseSha256Document('\u{FEFF}$_hash\n'), _hash);
    });

    test('returns null for anything that is not a hash', () {
      expect(parseSha256Document(''), isNull);
      expect(parseSha256Document('<html>404</html>'), isNull);
      expect(parseSha256Document('deadbeef'), isNull);
      expect(parseSha256Document('${_hash}extra'), isNull);
    });
  });

  group('fetchLatestRelease', () {
    final endpoint = Uri.parse(
      'https://api.github.com/repos/yvanvds/AI-tutor-Python/releases/latest',
    );

    test('returns the release with its checksum', () async {
      final info = await fetchLatestRelease(
        endpoint,
        client: _githubClient(release: _releaseJson()),
      );
      expect(info, isNotNull);
      expect(info!.version, '2.0.0+18');
      expect(info.url, Uri.parse(_installerUrl));
      expect(info.sha256, _hash);
      expect(info.notes, 'Release notes here.');
    });

    test('asks the API the documented way', () async {
      final seen = <String, String>{};
      final client = MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) {
          return http.Response.bytes(utf8.encode(_hash), 200);
        }
        seen.addAll(request.headers);
        return http.Response.bytes(
          utf8.encode(jsonEncode(_releaseJson())),
          200,
        );
      });
      await fetchLatestRelease(endpoint, client: client);
      expect(seen['Accept'], 'application/vnd.github+json');
      expect(seen['X-GitHub-Api-Version'], '2022-11-28');
    });

    // #45, on the path that now matters: a release asset is served as
    // `application/octet-stream`, so `res.body` would latin1-decode it and a
    // BOM would turn into three characters in front of the hash.
    test('reads a checksum asset served as octet-stream with a BOM', () async {
      final bytes = <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('$_hash  $kInstallerAssetName\n'),
      ];
      expect(
        parseSha256Document(latin1.decode(bytes)),
        isNull,
        reason: 'guards the premise: the latin1 path res.body takes fails',
      );

      final info = await fetchLatestRelease(
        endpoint,
        client: _githubClient(release: _releaseJson(), checksumBytes: bytes),
      );
      expect(info?.sha256, _hash);
    });

    test('returns null on 404 — nothing published', () async {
      final client = MockClient((_) async => http.Response('', 404));
      expect(await fetchLatestRelease(endpoint, client: client), isNull);
    });

    test('returns null for a release with no installer', () async {
      final info = await fetchLatestRelease(
        endpoint,
        client: _githubClient(release: _releaseJson(assets: const [])),
      );
      expect(info, isNull);
    });

    // Silently declining to update is how #45 stayed invisible: a release
    // that publishes an installer nobody can verify is a broken release, and
    // has to reach a log.
    test('throws when the release publishes no checksum asset', () async {
      await expectLater(
        fetchLatestRelease(
          endpoint,
          client: _githubClient(
            release: _releaseJson(
              assets: [_asset(kInstallerAssetName, _installerUrl)],
            ),
          ),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains(kChecksumAssetName),
          ),
        ),
      );
    });

    test('throws when the checksum asset is not a hash', () async {
      await expectLater(
        fetchLatestRelease(
          endpoint,
          client: _githubClient(
            release: _releaseJson(),
            checksumBytes: utf8.encode('<html>404</html>'),
          ),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('not a sha256 checksum'),
          ),
        ),
      );
    });

    test('throws when the checksum asset is missing at its URL', () async {
      await expectLater(
        fetchLatestRelease(
          endpoint,
          client: _githubClient(release: _releaseJson(), checksumStatus: 404),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
    });

    test('throws on any other non-200', () async {
      for (final status in [301, 401, 500, 503]) {
        final client = MockClient((_) async => http.Response('', status));
        await expectLater(
          fetchLatestRelease(endpoint, client: client),
          throwsA(
            isA<UpdateCheckException>().having(
              (e) => e.message,
              'message',
              contains('HTTP $status'),
            ),
          ),
        );
      }
    });

    // The one failure here that fixes itself, so it says so.
    test('names the rate limit when GitHub has had enough', () async {
      final client = MockClient(
        (_) async => http.Response(
          '{"message":"API rate limit exceeded"}',
          403,
          headers: const {'x-ratelimit-remaining': '0'},
        ),
      );
      await expectLater(
        fetchLatestRelease(endpoint, client: client),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('rate limit'),
          ),
        ),
      );
    });

    test('throws when the endpoint does not answer with JSON', () async {
      final client = MockClient(
        (_) async => http.Response('<html>hello</html>', 200),
      );
      await expectLater(
        fetchLatestRelease(endpoint, client: client),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('did not answer with JSON'),
          ),
        ),
      );
    });

    test('throws on a transport error', () async {
      final client = MockClient(
        (_) async => throw const SocketException('no route to host'),
      );
      await expectLater(
        fetchLatestRelease(endpoint, client: client),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('throws instead of hanging when the server never answers', () async {
      final client = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        fetchLatestRelease(
          endpoint,
          client: client,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('times out a checksum request that never answers', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) {
          return Completer<http.Response>().future;
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(_releaseJson())),
          200,
        );
      });
      await expectLater(
        fetchLatestRelease(
          endpoint,
          client: client,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });
  });

  // #124: behind a TLS-inspecting filter Dart's BoringSSL cannot chain the
  // re-signed certificate and throws `HandshakeException` — which
  // `package:http` does not wrap, so it arrives as itself. The seam exists
  // for that failure only.
  group('fetchLatestRelease — native transport fallback', () {
    final endpoint = Uri.parse(
      'https://api.github.com/repos/yvanvds/AI-tutor-Python/releases/latest',
    );
    const handshake = HandshakeException(
      'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: '
      'unable to get local issuer certificate)',
    );

    /// Records every call the seam gets and answers like GitHub would.
    ({NativeGet get, List<({Uri url, Map<String, String> headers})> calls})
    recordingNative({Object? failWith}) {
      final calls = <({Uri url, Map<String, String> headers})>[];
      Future<http.Response> get(
        Uri url, {
        Map<String, String> headers = const {},
        Duration? timeout,
        File? to,
      }) async {
        calls.add((url: url, headers: headers));
        if (failWith != null) throw failWith;
        if (url.path.endsWith('.sha256')) {
          return http.Response.bytes(
            utf8.encode('$_hash  $kInstallerAssetName\n'),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode(_releaseJson())),
          200,
        );
      }

      return (get: get, calls: calls);
    }

    test('a handshake failure is retried through the seam, with the same '
        'URL and headers, and the checksum follows it', () async {
      var dartRequests = 0;
      final dart = MockClient((_) async {
        dartRequests++;
        throw handshake;
      });
      final native = recordingNative();
      final logs = <String>[];

      final info = await fetchLatestRelease(
        endpoint,
        client: dart,
        nativeGet: native.get,
        log: logs.add,
      );

      expect(info, isNotNull);
      expect(info!.version, '2.0.0+18');
      expect(info.sha256, _hash);
      expect(info.viaNativeTransport, isTrue);

      expect(native.calls, hasLength(2));
      expect(native.calls[0].url, endpoint);
      expect(native.calls[0].headers['Accept'], 'application/vnd.github+json');
      expect(native.calls[0].headers['X-GitHub-Api-Version'], '2022-11-28');
      expect(native.calls[1].url, Uri.parse(_checksumUrl));
      // Once Dart has failed the handshake to this host there is nothing to
      // learn from failing it again for the checksum.
      expect(dartRequests, 1, reason: 'the checksum was tried on Dart again');
      expect(logs.join('\n'), contains('TLS handshake'));
    });

    test('a check that never needed the seam does not say it did', () async {
      final native = recordingNative();
      final info = await fetchLatestRelease(
        endpoint,
        client: _githubClient(release: _releaseJson()),
        nativeGet: native.get,
      );
      expect(info?.viaNativeTransport, isFalse);
      expect(native.calls, isEmpty);
    });

    test('without a seam the handshake reason is reported as before', () async {
      final dart = MockClient((_) async => throw handshake);
      await expectLater(
        fetchLatestRelease(endpoint, client: dart),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('CERTIFICATE_VERIFY_FAILED'),
          ),
        ),
      );
    });

    // About has to keep telling the truth about the network: the handshake
    // is what went wrong first, the fallback is what went wrong after.
    test('when the seam fails too, both reasons are kept', () async {
      final dart = MockClient((_) async => throw handshake);
      final native = recordingNative(
        failWith: UpdateCheckException('curl.exe exited with 60'),
      );
      await expectLater(
        fetchLatestRelease(endpoint, client: dart, nativeGet: native.get),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('CERTIFICATE_VERIFY_FAILED'),
              contains('curl.exe exited with 60'),
            ),
          ),
        ),
      );
    });

    test('a non-200 through the seam is an ordinary non-200', () async {
      final dart = MockClient((_) async => throw handshake);
      Future<http.Response> native(
        Uri url, {
        Map<String, String> headers = const {},
        Duration? timeout,
        File? to,
      }) async => http.Response('', 404);
      // 404 still means "nothing published", whichever transport said so.
      expect(
        await fetchLatestRelease(endpoint, client: dart, nativeGet: native),
        isNull,
      );
    });

    // The fallback masks whatever it is used for, so it must only be used
    // for the certificate problem.
    test('a dead socket, a 404 or a timeout never reach the seam', () async {
      final native = recordingNative();

      await expectLater(
        fetchLatestRelease(
          endpoint,
          client: MockClient(
            (_) async => throw const SocketException('no route to host'),
          ),
          nativeGet: native.get,
        ),
        throwsA(isA<UpdateCheckException>()),
      );
      expect(
        await fetchLatestRelease(
          endpoint,
          client: MockClient((_) async => http.Response('', 404)),
          nativeGet: native.get,
        ),
        isNull,
      );
      await expectLater(
        fetchLatestRelease(
          endpoint,
          client: MockClient((_) => Completer<http.Response>().future),
          nativeGet: native.get,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<UpdateCheckException>()),
      );

      expect(
        native.calls,
        isEmpty,
        reason:
            'the seam was used for a failure '
            'that is not the certificate problem',
      );
    });
  });

  // #133: on a network where only the proxy has a route out, the client the
  // check builds for itself must go through it. The endpoint names a black
  // hole — a direct dial connects and hears nothing, the production symptom
  // — and the proxy routes that address to a loopback TLS server answering
  // like GitHub. Dart trusts that server's certificate only inside
  // `TrustLoopbackCertificate`, the test-side stand-in for a CA in the
  // Windows root store; nothing in `lib/` is touched by it.
  group('fetchLatestRelease — through the machine proxy', () {
    late BlackHole hole;
    late HttpServer github;
    late LoopbackProxy proxy;
    late Uri endpoint;

    setUp(() async {
      hole = await BlackHole.start();
      github = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChainBytes(utf8.encode(kLoopbackCertificatePem))
          ..usePrivateKeyBytes(utf8.encode(kLoopbackPrivateKeyPem)),
      );
      github.listen((HttpRequest req) {
        req.response.headers.contentType = ContentType.binary;
        if (req.uri.path.endsWith('.sha256')) {
          req.response.write('$_hash  $kInstallerAssetName\n');
        } else {
          req.response.write(
            jsonEncode(
              _releaseJson(
                assets: [
                  _asset(
                    kInstallerAssetName,
                    'https://${hole.authority}/$kInstallerAssetName',
                  ),
                  _asset(
                    kChecksumAssetName,
                    'https://${hole.authority}/$kChecksumAssetName',
                  ),
                ],
              ),
            ),
          );
        }
        req.response.close();
      });
      proxy = await LoopbackProxy.start(
        routes: {hole.authority: '${github.address.address}:${github.port}'},
      );
      endpoint = Uri.parse('https://${hole.authority}/releases/latest');
    });

    tearDown(() async {
      await proxy.close();
      await github.close(force: true);
      await hole.close();
    });

    test('the release and its checksum both arrive through it', () async {
      final info = await HttpOverrides.runWithHttpOverrides(
        () => fetchLatestRelease(endpoint, proxy: proxy.updateProxy),
        TrustLoopbackCertificate(),
      );
      expect(info?.version, '2.0.0+18');
      expect(info?.sha256, _hash);
      expect(info?.viaNativeTransport, isFalse, reason: 'Dart got through');
      expect(proxy.connects, everyElement(hole.authority));
      expect(
        proxy.connects.length,
        greaterThanOrEqualTo(1),
        reason: 'the check never went through the proxy',
      );
      expect(hole.connections, 0, reason: 'the check dialled out directly');
    });

    // The premise, and the symptom the issue was filed on: the same
    // endpoint with no proxy is a ten-second silence.
    test('without the proxy the same check times out', () async {
      await expectLater(
        HttpOverrides.runWithHttpOverrides(
          () => fetchLatestRelease(
            endpoint,
            timeout: const Duration(milliseconds: 300),
          ),
          TrustLoopbackCertificate(),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(proxy.connects, isEmpty);
      expect(hole.connections, 1);
    });

    // A host on the bypass list goes direct — here, into the hole.
    test('a bypassed host is dialled directly', () async {
      await expectLater(
        HttpOverrides.runWithHttpOverrides(
          () => fetchLatestRelease(
            endpoint,
            timeout: const Duration(milliseconds: 300),
            proxy: UpdateProxy(proxy.updateProxy.url, bypass: const ['*']),
          ),
          TrustLoopbackCertificate(),
        ),
        throwsA(isA<UpdateCheckException>()),
      );
      expect(proxy.connects, isEmpty);
      expect(hole.connections, 1);
    });
  });

  group('kLatestReleaseEndpoint', () {
    test('points at this repository', () {
      expect(kLatestReleaseEndpoint.host, 'api.github.com');
      expect(
        kLatestReleaseEndpoint.path,
        '/repos/$kReleaseOwner/$kReleaseRepo/releases/latest',
      );
      expect(kLatestReleaseEndpoint.scheme, 'https');
    });
  });

  // #130 — the by-tag lookup sits beside `/releases/latest` on the same
  // server, wherever that server is.
  group('releaseByTagEndpoint', () {
    test('is /releases/tags/v{version} next to the feed', () {
      expect(
        releaseByTagEndpoint(kLatestReleaseEndpoint, '2.3.0+20').toString(),
        'https://api.github.com/repos/$kReleaseOwner/$kReleaseRepo/'
        'releases/tags/v2.3.0+20',
      );
    });

    test('follows the feed to wherever it is pointed', () {
      // The integration harness serves the API from a loopback server; the
      // lookup has to land there too, or a flow would reach github.com.
      final feed = Uri.parse(
        'http://127.0.0.1:4321/repos/$kReleaseOwner/$kReleaseRepo/'
        'releases/latest',
      );
      expect(
        releaseByTagEndpoint(feed, '99.0.0+1').toString(),
        'http://127.0.0.1:4321/repos/$kReleaseOwner/$kReleaseRepo/'
        'releases/tags/v99.0.0+1',
      );
    });

    test('keeps the + of a build number as GitHub reads it', () {
      // `+` is a legal path character; percent-encoding it would ask for a
      // tag that does not exist.
      expect(
        releaseByTagEndpoint(kLatestReleaseEndpoint, '2.3.0+20').path,
        endsWith('/tags/v2.3.0+20'),
      );
    });
  });

  group('fetchReleaseNotesByTag', () {
    final endpoint = releaseByTagEndpoint(kLatestReleaseEndpoint, '2.0.0+18');

    MockClient answering(
      Object? json, {
      int status = 200,
      Map<String, String> headers = const {
        'content-type': 'application/json; charset=utf-8',
      },
    }) => MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(json is String ? json : jsonEncode(json)),
        status,
        headers: headers,
      ),
    );

    test('returns the release body', () async {
      expect(
        await fetchReleaseNotesByTag(
          endpoint,
          client: answering(_releaseJson(body: 'For students\n\n- Faster')),
        ),
        'For students\n\n- Faster',
      );
    });

    test('asks the API the documented way, at the tag URL', () async {
      Uri? asked;
      final seen = <String, String>{};
      final client = MockClient((request) async {
        asked = request.url;
        seen.addAll(request.headers);
        return http.Response.bytes(
          utf8.encode(jsonEncode(_releaseJson())),
          200,
        );
      });
      await fetchReleaseNotesByTag(endpoint, client: client);
      expect(asked, endpoint);
      expect(seen['Accept'], 'application/vnd.github+json');
      expect(seen['X-GitHub-Api-Version'], '2022-11-28');
    });

    test('does not need an installer asset — notes are notes', () async {
      // Unlike the update check, a release with nothing to install still has
      // something to say.
      expect(
        await fetchReleaseNotesByTag(
          endpoint,
          client: answering(_releaseJson(assets: [], body: 'Notes only')),
        ),
        'Notes only',
      );
    });

    test('returns an empty string for a release published with no '
        'body', () async {
      expect(
        await fetchReleaseNotesByTag(
          endpoint,
          client: answering({'tag_name': 'v2.0.0+18', 'body': null}),
        ),
        '',
      );
      expect(
        await fetchReleaseNotesByTag(
          endpoint,
          client: answering({'tag_name': 'v2.0.0+18'}),
        ),
        '',
      );
    });

    test('returns null on 404 — no release under that tag', () async {
      expect(
        await fetchReleaseNotesByTag(
          endpoint,
          client: answering('{"message":"Not Found"}', status: 404),
        ),
        isNull,
      );
    });

    test('throws on any other non-200', () async {
      for (final status in [400, 403, 429, 500, 503]) {
        await expectLater(
          fetchReleaseNotesByTag(
            endpoint,
            client: answering('', status: status),
          ),
          throwsA(
            isA<UpdateCheckException>().having(
              (e) => e.message,
              'message',
              contains('HTTP $status'),
            ),
          ),
          reason: 'HTTP $status',
        );
      }
    });

    test('names the rate limit when GitHub has had enough', () async {
      await expectLater(
        fetchReleaseNotesByTag(
          endpoint,
          client: answering(
            '',
            status: 403,
            headers: const {'x-ratelimit-remaining': '0'},
          ),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('rate limit'),
          ),
        ),
      );
    });

    test('throws when the endpoint does not answer with JSON', () async {
      await expectLater(
        fetchReleaseNotesByTag(
          endpoint,
          client: answering(
            '<html>maintenance</html>',
            headers: const {'content-type': 'text/html'},
          ),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('JSON'),
          ),
        ),
      );
    });

    test('throws when the JSON is not a release object', () async {
      await expectLater(
        fetchReleaseNotesByTag(endpoint, client: answering(['not', 'it'])),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('throws on a transport error', () async {
      await expectLater(
        fetchReleaseNotesByTag(
          endpoint,
          client: MockClient(
            (_) async => throw const SocketException('no route to host'),
          ),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('no route to host'),
          ),
        ),
      );
    });

    test('throws instead of hanging when the server never answers', () async {
      await expectLater(
        fetchReleaseNotesByTag(
          endpoint,
          client: MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    // The same transport as the check (#124): a handshake Dart cannot
    // complete is retried through the native seam, with the same URL and
    // headers.
    test('a handshake failure is retried through the native seam', () async {
      const handshake = HandshakeException(
        'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)',
      );
      final calls = <({Uri url, Map<String, String> headers})>[];
      Future<http.Response> native(
        Uri url, {
        Map<String, String> headers = const {},
        Duration? timeout,
        File? to,
      }) async {
        calls.add((url: url, headers: headers));
        return http.Response.bytes(
          utf8.encode(jsonEncode(_releaseJson(body: 'Via curl'))),
          200,
        );
      }

      expect(
        await fetchReleaseNotesByTag(
          endpoint,
          client: MockClient((_) async => throw handshake),
          nativeGet: native,
        ),
        'Via curl',
      );
      expect(calls.single.url, endpoint);
      expect(calls.single.headers['Accept'], 'application/vnd.github+json');
    });
  });
}
