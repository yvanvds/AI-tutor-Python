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
      addTearDown(() => dir.deleteSync(recursive: true));
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

  // A build without a school has no usable database key; a school from a
  // file must still start, and reach its sign-in screen.
  test('a school from a file starts on a build without a usable key', () {
    expect(
      () => CosmosClient.forMode(
        SchoolMode(fromFile),
        databaseKey: () => 'dummy',
      ),
      returnsNormally,
    );
  });
}
