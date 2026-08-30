import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_info.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(info.version, '2.0.0');
      expect(info.url, Uri.parse('https://example.com/installer.exe'));
      expect(info.sha256, 'abc123');
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
      expect(info.version, '2.0.0+18');
      expect(
        info.url,
        Uri.parse('https://example.com/python_teacher_install.exe'),
      );
      expect(info.sha256, '2D224ED88E427AB535399AEB35069');
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
      expect(info.version, '2.0.0+18');
      expect(
        info.url,
        Uri.parse('https://example.com/python_teacher_install.exe'),
      );
      expect(info.sha256, '2D224ED88E427AB535399AEB35069');
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
