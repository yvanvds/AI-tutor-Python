// #50: the release feed no longer reads a hand-published `version.json`; it
// asks GitHub's `/releases/latest`. These pin the two halves that can go
// wrong on their own — reading a release payload, and reading the checksum
// asset that replaces the manifest's `sha256` field.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/github_release.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
}
