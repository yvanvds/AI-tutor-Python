import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_info.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('isNewer', () {
    test(
      'higher patch is newer',
      () => expect(isNewer('1.0.1', '1.0.0'), isTrue),
    );
    test(
      'higher minor is newer',
      () => expect(isNewer('1.1.0', '1.0.0'), isTrue),
    );
    test(
      'higher major is newer',
      () => expect(isNewer('2.0.0', '1.9.9'), isTrue),
    );
    test(
      'same version without build is not newer',
      () => expect(isNewer('1.0.0', '1.0.0'), isFalse),
    );
    test(
      'lower version is not newer',
      () => expect(isNewer('0.9.0', '1.0.0'), isFalse),
    );

    test('same semver, higher build number is newer', () {
      expect(isNewer('1.0.0+2', '1.0.0+1'), isTrue);
    });

    test('same semver and same build is not newer', () {
      expect(isNewer('1.0.0+1', '1.0.0+1'), isFalse);
    });

    test('no build vs build is not newer', () {
      expect(isNewer('1.0.0', '1.0.0+1'), isFalse);
    });

    test('build vs no build is newer', () {
      expect(isNewer('1.0.0+1', '1.0.0'), isTrue);
    });
  });

  group('UpdateInfo.fromJson', () {
    test('parses all fields', () {
      final info = UpdateInfo.fromJson({
        'version': '2.0.0',
        'url': 'https://example.com/installer.exe',
        'sha256': 'abc123',
      });
      expect(info, isNotNull);
      expect(info!.version, '2.0.0');
      expect(info.url, Uri.parse('https://example.com/installer.exe'));
      expect(info.sha256, 'abc123');
    });

    // #46: every one of these used to throw a `TypeError` (or produce a
    // nonsense `Uri`) out of an unawaited future instead of being reported.
    test('returns null for a missing field', () {
      expect(
        UpdateInfo.fromJson({'version': '2.0.0', 'sha256': 'abc123'}),
        isNull,
      );
    });

    test('returns null for a field of the wrong type', () {
      expect(
        UpdateInfo.fromJson({
          'version': 2,
          'url': 'https://example.com/installer.exe',
          'sha256': 'abc123',
        }),
        isNull,
      );
    });

    test('returns null for an empty version or hash', () {
      expect(
        UpdateInfo.fromJson({
          'version': '',
          'url': 'https://example.com/installer.exe',
          'sha256': 'abc123',
        }),
        isNull,
      );
      expect(
        UpdateInfo.fromJson({
          'version': '2.0.0',
          'url': 'https://example.com/installer.exe',
          'sha256': '',
        }),
        isNull,
      );
    });

    test('returns null for a url that is not an absolute URI', () {
      expect(
        UpdateInfo.fromJson({
          'version': '2.0.0',
          'url': 'installer.exe',
          'sha256': 'abc123',
        }),
        isNull,
      );
    });

    test('returns null for a payload that is not an object', () {
      expect(UpdateInfo.fromJson('nope'), isNull);
      expect(UpdateInfo.fromJson(const []), isNull);
      expect(UpdateInfo.fromJson(null), isNull);
    });
  });

  group('parseUpdateManifest', () {
    const manifest =
        '{\n'
        '  "version": "2.0.0+18",\n'
        '  "url": "https://example.com/python_teacher_install.exe",\n'
        '  "sha256": "2D224ED88E427AB535399AEB35069"\n'
        '}\n';

    test('parses a plain manifest', () {
      final info = parseUpdateManifest(manifest);
      expect(info, isNotNull);
      expect(info!.version, '2.0.0+18');
      expect(
        info.url,
        Uri.parse('https://example.com/python_teacher_install.exe'),
      );
      expect(info.sha256, '2D224ED88E427AB535399AEB35069');
    });

    // #46: `jsonDecode` threw straight out of the unawaited check.
    test('returns null for a body that is not JSON', () {
      expect(parseUpdateManifest('<html>404</html>'), isNull);
      expect(parseUpdateManifest(''), isNull);
    });

    test('returns null for JSON that is not a release manifest', () {
      expect(parseUpdateManifest('{"message":"Not Found"}'), isNull);
    });

    // #45: the published version.json was served with a UTF-8 BOM, and
    // `jsonDecode` throws on the leading U+FEFF instead of skipping it, so
    // every update check died before comparing versions.
    test('parses a manifest with a leading UTF-8 BOM', () {
      expect(
        () => jsonDecode('\u{FEFF}$manifest'),
        throwsFormatException,
        reason: 'guards the premise: jsonDecode does not skip a BOM',
      );

      final info = parseUpdateManifest('\u{FEFF}$manifest');
      expect(info, isNotNull);
      expect(info!.version, '2.0.0+18');
      expect(
        info.url,
        Uri.parse('https://example.com/python_teacher_install.exe'),
      );
      expect(info.sha256, '2D224ED88E427AB535399AEB35069');
    });
  });

  // #46: the check had no try/catch, no timeout and no way to tell "nothing
  // published" from "the check blew up", so every failure looked exactly
  // like "you are up to date".
  group('fetchUpdateInfo', () {
    final url = Uri.parse('https://example.com/version.json');
    const manifest =
        '{"version":"2.0.0+18",'
        '"url":"https://example.com/python_teacher_install.exe",'
        '"sha256":"2D224ED88E427AB535399AEB35069"}';

    test('returns the manifest on 200', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(utf8.encode(manifest), 200),
      );
      final info = await fetchUpdateInfo(url, client: client);
      expect(info?.version, '2.0.0+18');
    });

    test('returns null on 404 — nothing published', () async {
      final client = MockClient((_) async => http.Response('', 404));
      expect(await fetchUpdateInfo(url, client: client), isNull);
    });

    test('throws on any other non-200', () async {
      for (final status in [301, 403, 500, 503]) {
        final client = MockClient((_) async => http.Response('', status));
        await expectLater(
          fetchUpdateInfo(url, client: client),
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

    test('throws on a malformed manifest instead of TypeError', () async {
      final client = MockClient(
        (_) async => http.Response('{"version":"2.0.0"}', 200),
      );
      await expectLater(
        fetchUpdateInfo(url, client: client),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('not a release manifest'),
          ),
        ),
      );
    });

    test('throws on a transport error', () async {
      final client = MockClient(
        (_) async => throw const SocketException('no route to host'),
      );
      await expectLater(
        fetchUpdateInfo(url, client: client),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('throws instead of hanging when the server never answers', () async {
      final client = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        fetchUpdateInfo(
          url,
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

  group('downloadToTemp', () {
    final url = Uri.parse('https://example.com/installer.exe');

    test('throws on a non-200 instead of returning null', () async {
      final client = MockClient((_) async => http.Response('', 404));
      await expectLater(
        downloadToTemp(url, client: client),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
    });

    test('throws instead of hanging when the server never answers', () async {
      final client = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        downloadToTemp(
          url,
          client: client,
          responseTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('throws when the body stalls mid-stream', () async {
      final client = MockClient.streaming((_, _) async {
        // One chunk, then silence: exactly the black-hole download that
        // used to keep the app waiting forever.
        final stalled = StreamController<List<int>>();
        stalled.add([1, 2, 3]);
        return http.StreamedResponse(stalled.stream, 200);
      });
      await expectLater(
        downloadToTemp(
          url,
          client: client,
          stallTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('stalled'),
          ),
        ),
      );
    });
  });

  group('verifySha256', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('update_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('returns true for matching hash', () async {
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      final file = File('${tmp.path}/bin')..writeAsBytesSync(content);
      final expected = sha256.convert(content).toString();
      expect(await verifySha256(file, expected), isTrue);
    });

    test('returns false for wrong hash', () async {
      final file = File('${tmp.path}/bin')..writeAsBytesSync([1, 2, 3]);
      expect(await verifySha256(file, 'deadbeef'), isFalse);
    });

    test('comparison is case-insensitive', () async {
      final content = Uint8List.fromList([10, 20, 30]);
      final file = File('${tmp.path}/bin')..writeAsBytesSync(content);
      final upper = sha256.convert(content).toString().toUpperCase();
      expect(await verifySha256(file, upper), isTrue);
    });
  });
}
