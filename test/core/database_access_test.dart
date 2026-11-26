// #336: how the app reaches a school's database follows from the school file
// and from the build. A file that asks for `"signIn"` gets the sign-in; any
// other file works as before in a build with school data, and uses the
// sign-in in a build without. The school file that step 1 of #308 wrote for
// every install has no `databaseAccess`, so it must work in both builds,
// without being rewritten.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/app_start.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/services/auth/cosmos_token_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/memory_school_file_store.dart';
import '../helpers/test_app_mode.dart';

/// The dummy `.env` CI writes before code generation, read from the
/// workflow itself so this test follows it if it ever changes.
Map<String, String> _ciDummyEnv() {
  final workflow = File('.github/workflows/build.yml').readAsStringSync();
  final start = workflow.indexOf('Create dummy .env');
  expect(start, isNot(-1), reason: 'build.yml no longer writes a dummy .env');
  final block = workflow.substring(start, workflow.indexOf('"@', start));
  final env = <String, String>{};
  for (final line in block.split('\n')) {
    final m = RegExp(r'^\s*([A-Z_]+)=(.*)$').firstMatch(line.trimRight());
    if (m != null) env[m.group(1)!] = m.group(2)!;
  }
  return env;
}

/// Any valid base64: what a build with school data would hand over.
final String _key = base64Encode(List<int>.filled(32, 7));

void main() {
  // The file step 1 of #308 wrote: the build's school under its name, and
  // nothing about the access.
  final stepOneText = encodeSchoolFile(kTestSchool.named(kBuildSchoolName));
  final stepOne = parseSchoolFile(stepOneText);
  final signIn = parseSchoolFile(
    exampleSchoolFile(extra: {'databaseAccess': 'signIn'}),
  );

  test('the file of step 1 says nothing about the access', () {
    expect(jsonDecode(stepOneText), isNot(contains('databaseAccess')));
    expect(stepOne.databaseAccess, DatabaseAccess.masterKey);
  });

  group('which builds have school data', () {
    const school = (
      tenantId: '3f2a8c1e-5b7d-4e9f-a1c2-0d4e6f8a9b1c',
      clientId: '7c9e1a3b-2d4f-4a6b-8c0d-1e3f5a7b9c2d',
      redirectUri: 'http://localhost',
      databaseEndpoint: 'https://school.documents.azure.com:443/',
    );

    bool hasSchoolData({String? tenantId, String? databaseKey}) =>
        SchoolConfig.hasSchoolData(
          tenantId: tenantId ?? school.tenantId,
          clientId: school.clientId,
          redirectUri: school.redirectUri,
          databaseEndpoint: school.databaseEndpoint,
          databaseKey: databaseKey ?? _key,
        );

    test("a school's values, with a database key: school data", () {
      expect(hasSchoolData(), isTrue);
    });

    test("CI's dummy .env: none", () {
      final env = _ciDummyEnv();
      expect(
        SchoolConfig.hasSchoolData(
          tenantId: env['ENTRA_TENANT_ID']!,
          clientId: env['ENTRA_CLIENT_ID']!,
          redirectUri: env['ENTRA_REDIRECT_URI']!,
          databaseEndpoint: env['COSMOS_ENDPOINT']!,
          databaseKey: env['COSMOS_KEY']!,
        ),
        isFalse,
      );
    });

    for (final (label, tenantId, databaseKey) in [
      ('no school configuration', '', null),
      ('an empty database key', null, ''),
      ('a placeholder database key', null, 'dummy'),
    ]) {
      test('$label: none', () {
        expect(
          hasSchoolData(tenantId: tenantId, databaseKey: databaseKey),
          isFalse,
        );
      });
    }
  });

  group('the access, from the file and the build', () {
    test('a build with school data and a file without the field: as now, '
        'on the database key', () {
      expect(
        stepOne.databaseAccessIn(buildHasSchoolData: true),
        DatabaseAccess.masterKey,
      );
    });

    test('a build without school data and a file without the field: the '
        'sign-in', () {
      expect(
        stepOne.databaseAccessIn(buildHasSchoolData: false),
        DatabaseAccess.signIn,
      );
    });

    test('a file with "signIn": the sign-in in both builds', () {
      for (final hasSchoolData in [true, false]) {
        expect(
          signIn.databaseAccessIn(buildHasSchoolData: hasSchoolData),
          DatabaseAccess.signIn,
          reason: 'school data: $hasSchoolData',
        );
      }
    });

    test('a file with "masterKey" in a build without school data: the '
        'sign-in too', () {
      final masterKey = parseSchoolFile(
        exampleSchoolFile(extra: {'databaseAccess': 'masterKey'}),
      );
      expect(
        masterKey.databaseAccessIn(buildHasSchoolData: false),
        DatabaseAccess.signIn,
      );
    });
  });

  group("the client's access", () {
    CosmosAuth auth(
      SchoolConfig school, {
      required bool hasSchoolData,
      required void Function() onKey,
    }) => CosmosClient.schoolAuth(
      SchoolMode(school),
      databaseKey: () {
        onKey();
        return hasSchoolData ? _key : 'dummy';
      },
      schoolDataInBuild: () => hasSchoolData,
      tokenSource: CosmosTokenSource(school: school, tokensPrefsKey: 'unused'),
    );

    test('a build with school data and the file of step 1: the database '
        'key, as now', () {
      var keyAsked = false;
      expect(
        auth(stepOne, hasSchoolData: true, onKey: () => keyAsked = true),
        isA<MasterKeyAuth>(),
      );
      expect(keyAsked, isTrue);
    });

    test('a build without school data and the file of step 1: the sign-in, '
        'and the key is never asked for', () {
      var keyAsked = false;
      expect(
        auth(stepOne, hasSchoolData: false, onKey: () => keyAsked = true),
        isA<AadTokenAuth>(),
      );
      expect(keyAsked, isFalse);
    });

    test('a file with "signIn": the sign-in in both builds', () {
      for (final hasSchoolData in [true, false]) {
        var keyAsked = false;
        expect(
          auth(
            signIn,
            hasSchoolData: hasSchoolData,
            onKey: () => keyAsked = true,
          ),
          isA<AadTokenAuth>(),
          reason: 'school data: $hasSchoolData',
        );
        expect(keyAsked, isFalse, reason: 'school data: $hasSchoolData');
      }
    });

    test('forMode gives the school the same access', () {
      var keyAsked = false;
      final client = CosmosClient.forMode(
        SchoolMode(stepOne),
        databaseKey: () {
          keyAsked = true;
          return 'dummy';
        },
        schoolDataInBuild: () => false,
        tokenSource: CosmosTokenSource(
          school: stepOne,
          tokensPrefsKey: 'unused',
        ),
      );
      expect(client, isA<CosmosClient>());
      expect(keyAsked, isFalse);
    });
  });

  group('the file is never rewritten for it', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a build without school data starts in the school of the file, as '
        'the file says it, and writes nothing', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = _CountingStore(stepOne);
      final stored = await keepBuildSchoolAsFile(
        stored: await store.read(),
        build: null,
        prefs: prefs,
        store: store,
      );
      expect(
        decideStartMode(stored: stored, build: null, prefs: prefs),
        SchoolMode(stepOne),
      );
      expect(store.writes, 0);
    });
  });
}

class _CountingStore extends MemorySchoolFileStore {
  _CountingStore(SchoolConfig super.stored);

  int writes = 0;

  @override
  Future<void> write(SchoolConfig config) {
    writes++;
    return super.write(config);
  }
}
