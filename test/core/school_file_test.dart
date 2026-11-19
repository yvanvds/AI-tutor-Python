// #307: the school file — what a school hands its students instead of a
// build of its own. Read, refused, written back, kept.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_school_file_store.dart';

Matcher _refused(SchoolFileProblem problem, {String? field, int? version}) =>
    isA<SchoolFileException>()
        .having((e) => e.problem, 'problem', problem)
        .having((e) => e.field, 'field', field)
        .having((e) => e.version, 'version', version);

void main() {
  group('reading a school file', () {
    test('a file as a teacher makes it', () {
      final school = parseSchoolFile(exampleSchoolFile());
      expect(
        school,
        SchoolConfig(
          tenantId: '33333333-3333-3333-3333-333333333333',
          clientId: '44444444-4444-4444-4444-444444444444',
          redirectUri: 'http://localhost',
          databaseEndpoint: Uri.parse(
            'https://example-school.documents.azure.com:443/',
          ),
          databaseName: 'python-tutor',
          schoolName: 'Example School',
        ),
      );
    });

    test('databaseName and redirectUri are taken when given', () {
      final school = parseSchoolFile(
        exampleSchoolFile(
          extra: {
            'databaseName': 'tutor-db',
            'redirectUri': 'http://localhost:1234',
          },
        ),
      );
      expect(school.databaseName, 'tutor-db');
      expect(school.redirectUri, 'http://localhost:1234');
    });

    test('a field this version does not know is left alone', () {
      final school = parseSchoolFile(
        exampleSchoolFile(extra: {'contact': 'ict@example.org'}),
      );
      expect(school.schoolName, 'Example School');
    });

    test('not JSON, or not an object, is not a school file', () {
      expect(
        () => parseSchoolFile('not json'),
        throwsA(_refused(SchoolFileProblem.notASchoolFile)),
      );
      expect(
        () => parseSchoolFile('[1, 2]'),
        throwsA(_refused(SchoolFileProblem.notASchoolFile)),
      );
      // A progress archive, say: JSON, but no formatVersion.
      expect(
        () => parseSchoolFile('{"account": {}}'),
        throwsA(_refused(SchoolFileProblem.notASchoolFile)),
      );
    });

    test('a newer format is refused with its version', () {
      expect(
        () => parseSchoolFile(exampleSchoolFile(formatVersion: 2)),
        throwsA(_refused(SchoolFileProblem.newerFormat, version: 2)),
      );
    });

    test('a missing or unusable field is named', () {
      final full = jsonDecode(exampleSchoolFile()) as Map<String, dynamic>;
      for (final field in [
        'schoolName',
        'tenantId',
        'clientId',
        'databaseEndpoint',
      ]) {
        final without = Map<String, dynamic>.of(full)..remove(field);
        expect(
          () => parseSchoolFile(jsonEncode(without)),
          throwsA(_refused(SchoolFileProblem.invalidField, field: field)),
          reason: field,
        );
      }
      final zeroTenant = Map<String, dynamic>.of(full)
        ..['tenantId'] = '00000000-0000-0000-0000-000000000000';
      expect(
        () => parseSchoolFile(jsonEncode(zeroTenant)),
        throwsA(_refused(SchoolFileProblem.invalidField, field: 'tenantId')),
      );
      final plainHttp = Map<String, dynamic>.of(full)
        ..['databaseEndpoint'] = 'http://example.documents.azure.com/';
      expect(
        () => parseSchoolFile(jsonEncode(plainHttp)),
        throwsA(
          _refused(SchoolFileProblem.invalidField, field: 'databaseEndpoint'),
        ),
      );
      final emptyDb = Map<String, dynamic>.of(full)..['databaseName'] = ' ';
      expect(
        () => parseSchoolFile(jsonEncode(emptyDb)),
        throwsA(
          _refused(SchoolFileProblem.invalidField, field: 'databaseName'),
        ),
      );
    });

    test('a field that looks secret is refused, wherever it is', () {
      expect(
        () => parseSchoolFile(exampleSchoolFile(extra: {'databaseKey': 'x'})),
        throwsA(
          _refused(SchoolFileProblem.containsSecret, field: 'databaseKey'),
        ),
      );
      expect(
        () => parseSchoolFile(
          exampleSchoolFile(extra: {'note': 'no password or key in here'}),
        ),
        // Only a field name counts; a value is never looked into.
        returnsNormally,
      );
      final nested = jsonDecode(exampleSchoolFile()) as Map<String, dynamic>
        ..['auth'] = {'password': 'x'};
      expect(
        () => parseSchoolFile(jsonEncode(nested)),
        throwsA(_refused(SchoolFileProblem.containsSecret, field: 'password')),
      );
      // Before the version: a newer file with a key is still refused for it.
      expect(
        () => parseSchoolFile(
          exampleSchoolFile(formatVersion: 9, extra: {'apiToken': 'x'}),
        ),
        throwsA(_refused(SchoolFileProblem.containsSecret, field: 'apiToken')),
      );
    });
  });

  test('encode and parse give the same school back', () {
    final school = parseSchoolFile(
      exampleSchoolFile(extra: {'databaseName': 'tutor-db'}),
    );
    final text = encodeSchoolFile(school);
    expect(parseSchoolFile(text), school);
    expect(jsonDecode(text)['formatVersion'], kSchoolFileFormatVersion);
    expect(text.toLowerCase(), isNot(contains('key')));
  });

  test("the build's school needs a name to become a file (#308)", () {
    final build = SchoolConfig(
      tenantId: '33333333-3333-3333-3333-333333333333',
      clientId: '44444444-4444-4444-4444-444444444444',
      redirectUri: 'http://localhost',
      databaseEndpoint: Uri.parse('https://school.documents.azure.com:443/'),
    );
    expect(() => encodeSchoolFile(build), throwsArgumentError);
    final named = build.named('Example School');
    expect(parseSchoolFile(encodeSchoolFile(named)), named);
  });

  group('the stored school file', () {
    late Directory dir;
    late SchoolFileStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('school_file_');
      store = SchoolFileStore(() async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'none until one is written; then that one; gone after delete',
      () async {
        expect(await store.read(), isNull);
        final school = parseSchoolFile(exampleSchoolFile());
        await store.write(school);
        expect(await store.read(), school);
        expect(File('${dir.path}/school.json').existsSync(), isTrue);
        expect(File('${dir.path}/school.json.tmp').existsSync(), isFalse);

        final other = parseSchoolFile(exampleSchoolFile(schoolName: 'Other'));
        await store.write(other);
        expect(await store.read(), other);

        await store.delete();
        expect(await store.read(), isNull);
        await store.delete();
      },
    );

    test('a stored file it cannot read counts as none', () async {
      File('${dir.path}/school.json').writeAsStringSync('{broken');
      expect(await store.read(), isNull);
    });

    test('only school.json is touched', () async {
      final standalone = Directory('${dir.path}/standalone/data')
        ..createSync(recursive: true);
      File('${standalone.path}/x.json').writeAsStringSync('{}');
      await store.write(parseSchoolFile(exampleSchoolFile()));
      await store.delete();
      expect(File('${standalone.path}/x.json').existsSync(), isTrue);
    });
  });
}
