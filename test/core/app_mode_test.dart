// #262: the mode follows from whether there is a school configuration.

import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

const _endpoint = 'https://school.documents.azure.com:443/';

void main() {
  group('the school configuration from the build', () {
    test("CI's dummy .env is no school, so that build is stand-alone", () {
      final env = _ciDummyEnv();
      expect(env.keys, contains('ENTRA_TENANT_ID'));
      final school = SchoolConfig.fromBuildValues(
        tenantId: env['ENTRA_TENANT_ID']!,
        clientId: env['ENTRA_CLIENT_ID']!,
        redirectUri: env['ENTRA_REDIRECT_URI']!,
        databaseEndpoint: env['COSMOS_ENDPOINT']!,
      );
      expect(school, isNull);
      expect(AppMode.fromSchoolConfig(school), const StandaloneMode());
    });

    test("a school's values make school mode, on the default database", () {
      final school = SchoolConfig.fromBuildValues(
        tenantId: ' 3f2a8c1e-5b7d-4e9f-a1c2-0d4e6f8a9b1c ',
        clientId: '7c9e1a3b-2d4f-4a6b-8c0d-1e3f5a7b9c2d',
        redirectUri: 'http://localhost',
        databaseEndpoint: _endpoint,
      );
      expect(school, isNotNull);
      expect(school!.tenantId, '3f2a8c1e-5b7d-4e9f-a1c2-0d4e6f8a9b1c');
      expect(school.databaseEndpoint.host, 'school.documents.azure.com');
      expect(school.databaseName, kDefaultSchoolDatabaseName);
      expect(school.schoolName, isNull);
      expect(AppMode.fromSchoolConfig(school), SchoolMode(school));
    });

    // #308: the build's school carries its name, so the school file written
    // from it is the very same configuration.
    test("the build's school is named, and a school file of it is equal", () {
      final school = SchoolConfig.fromBuildValues(
        tenantId: 't',
        clientId: 'c',
        redirectUri: 'http://localhost',
        databaseEndpoint: _endpoint,
        schoolName: kBuildSchoolName,
      )!;
      expect(school.schoolName, 'SMA Arcadia');
      expect(parseSchoolFile(encodeSchoolFile(school)), school);
      final build = SchoolConfig.fromBuild;
      if (build != null) {
        expect(build.schoolName, kBuildSchoolName);
        expect(parseSchoolFile(encodeSchoolFile(build)), build);
      }
    });

    const nilGuid = '00000000-0000-0000-0000-000000000000';
    for (final (label, tenant, client, endpoint) in [
      ('an empty tenant', '', 'c', _endpoint),
      ('an all-zero client id', 't', nilGuid, _endpoint),
      ('an empty endpoint', 't', 'c', '  '),
      (
        'a placeholder endpoint',
        't',
        'c',
        _endpoint.replaceFirst('school', 'dummy'),
      ),
      ('an endpoint that is no address', 't', 'c', 'not a url'),
    ]) {
      test('$label is no school', () {
        expect(
          SchoolConfig.fromBuildValues(
            tenantId: tenant,
            clientId: client,
            redirectUri: 'http://localhost',
            databaseEndpoint: endpoint,
          ),
          isNull,
        );
      });
    }
  });

  group('local data per mode', () {
    final base = Directory(p.join('C:', 'data'));

    test('school mode keeps every key and folder as it was', () {
      expect(
        kTestSchoolMode.scopedPrefsKey('azure_auth_tokens_v1'),
        'azure_auth_tokens_v1',
      );
      expect(kTestSchoolMode.localDataDir(base).path, base.path);
    });

    test("stand-alone mode keeps its own, apart from the school's", () {
      const mode = StandaloneMode();
      expect(
        mode.scopedPrefsKey('azure_auth_tokens_v1'),
        isNot('azure_auth_tokens_v1'),
      );
      expect(p.isWithin(base.path, mode.localDataDir(base).path), isTrue);
    });
  });

  group('the school database', () {
    test('stand-alone mode has none: without its local folder, no '
        'client', () {
      expect(
        () => CosmosClient.forMode(const StandaloneMode()),
        throwsStateError,
      );
    });

    test("school mode gets a client for the school's database", () {
      // Any base64 key: the build's own is not the test's business.
      final client = CosmosClient.forMode(
        kTestSchoolMode,
        databaseKey: () => 'dGVzdC1rZXk=',
      );
      expect(client, isA<CosmosClient>());
    });
  });
}
