// #307: which mode the app starts in — a stored school file, an earlier
// "without a school", the build's own school, or else the first-start
// choice — and that switching never touches the other mode's data.

import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/app_start.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/delete_dir.dart';
import '../helpers/memory_school_file_store.dart';
import '../helpers/test_app_mode.dart';

void main() {
  late SharedPreferences prefs;
  final fromFile = parseSchoolFile(exampleSchoolFile());

  Future<void> withPrefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
  }

  setUp(() => withPrefs({}));

  group('deciding at start', () {
    test('nothing at all: the choice asks', () {
      expect(decideStartMode(stored: null, build: null, prefs: prefs), isNull);
    });

    test("the build's school: school mode exactly as before, no choice", () {
      expect(
        decideStartMode(stored: null, build: kTestSchool, prefs: prefs),
        kTestSchoolMode,
      );
    });

    test('a stored school file wins over the build', () {
      expect(
        decideStartMode(stored: fromFile, build: kTestSchool, prefs: prefs),
        SchoolMode(fromFile),
      );
    });

    test('"without a school" is remembered', () async {
      await chooseWithoutSchool(prefs);
      expect(prefs.getBool('standalone.start_without_school_v1'), isTrue);
      expect(
        decideStartMode(stored: null, build: null, prefs: prefs),
        const StandaloneMode(),
      );
    });

    test("after leaving, the build's school no longer applies", () async {
      await leaveSchool(store: MemorySchoolFileStore(), prefs: prefs);
      expect(
        decideStartMode(stored: null, build: kTestSchool, prefs: prefs),
        isNull,
      );
    });
  });

  group('switching mode', () {
    test(
      'importing a file stores it, and the next start is that school',
      () async {
        await chooseWithoutSchool(prefs);
        final store = MemorySchoolFileStore();

        final school = await importSchoolFile(
          exampleSchoolFile(),
          store: store,
          prefs: prefs,
        );

        expect(school, fromFile);
        expect(store.stored, fromFile);
        expect(
          decideStartMode(stored: store.stored, build: null, prefs: prefs),
          SchoolMode(fromFile),
        );
      },
    );

    test('a refused file changes nothing', () async {
      await chooseWithoutSchool(prefs);
      final store = MemorySchoolFileStore(kTestSchool.named('Old School'));

      for (final text in [
        'nonsense',
        exampleSchoolFile(formatVersion: 2),
        exampleSchoolFile(extra: {'cosmosKey': 'x'}),
      ]) {
        await expectLater(
          importSchoolFile(text, store: store, prefs: prefs),
          throwsA(isA<SchoolFileException>()),
        );
      }

      expect(store.stored, kTestSchool.named('Old School'));
      expect(prefs.getBool('standalone.start_without_school_v1'), isTrue);
    });

    test(
      'leaving forgets the school and the choice; the next start asks',
      () async {
        await chooseWithoutSchool(prefs);
        final store = MemorySchoolFileStore(fromFile);

        await leaveSchool(store: store, prefs: prefs);

        expect(store.stored, isNull);
        expect(
          decideStartMode(stored: null, build: null, prefs: prefs),
          isNull,
        );
      },
    );

    test("neither leaves the other mode's data", () async {
      final dir = Directory.systemTemp.createTempSync('app_start_');
      addTearDown(() => deleteDirRetrying(dir));
      final store = SchoolFileStore(() async => dir);
      final standaloneData = const StandaloneMode().localDataDir(dir);
      File('${standaloneData.path}/data/accounts/local-1.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"id": "local-1"}');
      final kept = <String, Object>{
        // The school's sign-in and the stand-alone profile and key.
        'azure_auth_tokens_v1': '{"refreshToken": "r"}',
        'standalone.local_profile_v1': '{"uid": "local-1"}',
        'standalone.local_api_key': 'sk-own',
        'app_locale': 'nl',
      };
      await withPrefs(kept);

      await importSchoolFile(exampleSchoolFile(), store: store, prefs: prefs);
      await leaveSchool(store: store, prefs: prefs);
      await chooseWithoutSchool(prefs);
      await importSchoolFile(exampleSchoolFile(), store: store, prefs: prefs);

      for (final e in kept.entries) {
        expect(prefs.get(e.key), e.value, reason: e.key);
      }
      expect(
        File('${standaloneData.path}/data/accounts/local-1.json')
            .readAsStringSync(),
        '{"id": "local-1"}',
      );
      expect(await store.read(), fromFile);
    });
  });

  // #308, step 1: the transitional release keeps the build's school as the
  // school file, so a later build without one still finds the school.
  group("the build's school becomes the school file", () {
    final build = kTestSchool.named(kBuildSchoolName);

    Future<SchoolConfig?> keep(SchoolFileStore store, {SchoolConfig? stored}) =>
        keepBuildSchoolAsFile(
          stored: stored,
          build: build,
          prefs: prefs,
          store: store,
        );

    test('a signed-in install without a file gets one, as the very same '
        'school, and keeps its sign-in', () async {
      final dir = Directory.systemTemp.createTempSync('app_start_');
      addTearDown(() => deleteDirRetrying(dir));
      final store = SchoolFileStore(() async => dir);
      final kept = <String, Object>{
        'azure_auth_tokens_v1': '{"refresh_token": "r"}',
        'app_locale': 'nl',
      };
      await withPrefs(kept);

      final written = await keep(store);

      expect(written, build);
      expect(File('${dir.path}/school.json').existsSync(), isTrue);
      final stored = await store.read();
      expect(stored, build);
      expect(stored!.schoolName, 'SMA Arcadia');
      // This start and the next decide the same school mode as the build.
      expect(
        decideStartMode(stored: written, build: build, prefs: prefs),
        SchoolMode(build),
      );
      expect(
        decideStartMode(stored: stored, build: null, prefs: prefs),
        SchoolMode(build),
      );
      for (final e in kept.entries) {
        expect(prefs.get(e.key), e.value, reason: e.key);
      }
    });

    test('a build school without a name is kept as SMA Arcadia', () async {
      final store = MemorySchoolFileStore();
      final written = await keepBuildSchoolAsFile(
        stored: null,
        build: kTestSchool,
        prefs: prefs,
        store: store,
      );
      expect(written, kTestSchool.named('SMA Arcadia'));
      expect(store.stored, kTestSchool.named('SMA Arcadia'));
    });

    test('a second start writes nothing', () async {
      final store = _CountingStore(build);
      expect(await keep(store, stored: await store.read()), build);
      expect(store.writes, 0);
    });

    test(
      'an existing file is never overwritten, even one it cannot read',
      () async {
        final dir = Directory.systemTemp.createTempSync('app_start_');
        addTearDown(() => deleteDirRetrying(dir));
        final file = File('${dir.path}/school.json')..writeAsStringSync('{}');
        final store = SchoolFileStore(() async => dir);

        expect(await keep(store, stored: await store.read()), isNull);
        expect(file.readAsStringSync(), '{}');
        // The start then goes on with the build's school, as before.
        expect(
          decideStartMode(stored: null, build: build, prefs: prefs),
          SchoolMode(build),
        );
      },
    );

    test('"school left" writes nothing', () async {
      final store = _CountingStore();
      await leaveSchool(store: store, prefs: prefs);
      expect(await keep(store), isNull);
      expect(store.writes, 0);
      expect(store.stored, isNull);
    });

    test('stand-alone writes nothing', () async {
      final store = _CountingStore();
      await chooseWithoutSchool(prefs);
      expect(await keep(store), isNull);
      // A build without a school: stand-alone or the choice.
      expect(
        await keepBuildSchoolAsFile(
          stored: null,
          build: null,
          prefs: prefs,
          store: store,
        ),
        isNull,
      );
      expect(store.writes, 0);
    });

    test('a failing write does not stop the start', () async {
      final store = _FailingStore();
      expect(await keep(store), isNull);
      expect(
        decideStartMode(stored: null, build: build, prefs: prefs),
        SchoolMode(build),
      );
    });

    test(
      'a build school that would not read back the same is not written',
      () async {
        final store = _CountingStore();
        final http = SchoolConfig(
          tenantId: build.tenantId,
          clientId: build.clientId,
          redirectUri: build.redirectUri,
          databaseEndpoint: Uri.parse('http://localhost:8081/'),
          schoolName: kBuildSchoolName,
        );
        expect(
          await keepBuildSchoolAsFile(
            stored: null,
            build: http,
            prefs: prefs,
            store: store,
          ),
          isNull,
        );
        expect(store.writes, 0);
      },
    );
  });

  // A build without a school has no usable database key; a school from a
  // file must still start, and reach its sign-in screen. It reaches its
  // database with the sign-in (#336).
  test('a school from a file starts on a build without a usable key', () {
    expect(
      () => CosmosClient.forMode(
        SchoolMode(fromFile),
        databaseKey: () => 'dummy',
        schoolDataInBuild: () => false,
      ),
      returnsNormally,
    );
  });
}

class _CountingStore extends MemorySchoolFileStore {
  _CountingStore([super.stored]);

  int writes = 0;

  @override
  Future<void> write(SchoolConfig config) {
    writes++;
    return super.write(config);
  }
}

class _FailingStore extends MemorySchoolFileStore {
  @override
  Future<void> write(SchoolConfig config) async =>
      throw const FileSystemException('disk full');
}
