// The content the stand-alone mode ships with (#266): loaded at start when
// it is new, never over the student's own data, never twice.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/curriculum_bundle.dart';
import 'package:ai_tutor_python/core/local_cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/delete_dir.dart';
import '../helpers/in_memory_cosmos.dart';

final Directory _fixture = Directory('test/fixtures/curriculum_bundle');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory data;
  late Directory bundleDir;

  setUp(() {
    data = Directory.systemTemp.createTempSync('bundle_data_');
    bundleDir = Directory.systemTemp.createTempSync('bundle_src_');
    for (final f in _fixture.listSync().whereType<File>()) {
      f.copySync(p.join(bundleDir.path, p.basename(f.path)));
    }
  });

  tearDown(() async {
    for (final d in [data, bundleDir]) {
      await deleteDirRetrying(d);
    }
  });

  LocalCosmosClient open() => LocalCosmosClient.open(data);

  Future<CurriculumInstall> install(
    LocalCosmosClient client, {
    CurriculumProgress? onProgress,
  }) => installCurriculumBundle(
    source: DirectoryCurriculumBundleSource(bundleDir),
    client: client,
    versionFile: curriculumVersionFile(data),
    onProgress: onProgress,
  );

  Future<List<Map<String, dynamic>>> all(
    LocalCosmosClient client,
    String container,
  ) => client
      .container(container)
      .query('SELECT * FROM c', crossPartition: true);

  Future<Set<String>> ids(LocalCosmosClient client, String container) async => {
    for (final d in await all(client, container)) d['id'] as String,
  };

  Map<String, dynamic> readJson(String name) =>
      jsonDecode(File(p.join(bundleDir.path, name)).readAsStringSync())
          as Map<String, dynamic>;

  void writeJson(String name, Map<String, dynamic> json) =>
      File(p.join(bundleDir.path, name)).writeAsStringSync(jsonEncode(json));

  /// The fixture as a newer export: "toekennen" gone, the root renamed, one
  /// question gone, a new version.
  void makeNewerBundle() {
    final goals = readJson('goals.json');
    final docs = (goals['docs'] as List).cast<Map<String, dynamic>>();
    docs.removeWhere((d) => d['id'] == 'toekennen');
    docs.single['title'] = 'Variabelen (nieuw)';
    writeJson('goals.json', goals);
    final questions = readJson('questions.json');
    (questions['docs'] as List).removeWhere(
      (d) => (d as Map)['id'] == 'toekennen_bbbb',
    );
    writeJson('questions.json', questions);
    final manifest = readJson('manifest.json');
    manifest['contentVersion'] = 'newer';
    writeJson('manifest.json', manifest);
  }

  test('first start: every content container is loaded, the bundle\'s '
      'questions are marked, the version is kept', () async {
    final client = open();
    expect(await install(client), CurriculumInstall.installed);

    expect(await ids(client, 'goals'), {'variabelen', 'toekennen'});
    expect(await ids(client, 'content'), {'toekennen'});
    expect(await ids(client, 'modules'), {'python-basics'});
    expect(await ids(client, 'instructions'), {'tutor'});
    expect(await ids(client, 'translations'), {
      'goal_toekennen',
      'content_toekennen',
    });
    final global = await client
        .container('config')
        .read('global', partitionKey: 'config');
    expect(global!['Model'], 'gpt-test');
    final questions = await all(client, 'questions');
    expect(questions.map((q) => q['id']).toSet(), {
      'toekennen_aaaa',
      'toekennen_bbbb',
    });
    expect(questions.every((q) => q[kFromBundleField] == true), isTrue);
    expect(jsonDecode(curriculumVersionFile(data).readAsStringSync()), {
      'contentVersion': readJson('manifest.json')['contentVersion'],
    });

    // Still there on the next start: it is on disk.
    expect(await ids(open(), 'goals'), {'variabelen', 'toekennen'});
  });

  test('the same bundle again writes nothing', () async {
    await install(open());
    final client = open();
    final before = (await client
        .container('goals')
        .read('variabelen', partitionKey: 'goal'))!['_etag'];
    // A local edit the bundle must not undo while its version is the same.
    final q = (await client
        .container('questions')
        .read('toekennen_aaaa', partitionKey: 'toekennen'))!;
    await client.container('questions').upsert({
      ...q,
      'difficulty': 'hard',
    }, partitionKey: 'toekennen');

    expect(await install(client), CurriculumInstall.upToDate);

    final after = (await client
        .container('goals')
        .read('variabelen', partitionKey: 'goal'))!['_etag'];
    expect(after, before);
    final q2 = await client
        .container('questions')
        .read('toekennen_aaaa', partitionKey: 'toekennen');
    expect(q2!['difficulty'], 'hard');
  });

  test('a newer bundle replaces the content and leaves the student\'s data '
      'and the tutor\'s own questions', () async {
    await install(open());
    final client = open();
    // What a student leaves behind on this pc.
    await client.container('accounts').upsert({
      'id': 'local',
      'uid': 'local',
      'firstName': 'Alex',
    }, partitionKey: 'local');
    await client.container('lo_beliefs').upsert({
      'id': 'b1',
      'uid': 'local',
      'loId': 'lo_toekennen',
      'mu': 0.8,
    }, partitionKey: 'local');
    await client.container('progress').upsert({
      'id': 'p1',
      'uid': 'local',
      'subgoalId': 'toekennen',
    }, partitionKey: 'local');
    await client.container('questions').upsert({
      'id': 'toekennen_own',
      'subgoalId': 'toekennen',
      'status': 'active',
    }, partitionKey: 'toekennen');
    await client.container('config').upsert({
      'id': 'classes',
      'type': 'config',
    }, partitionKey: 'config');

    makeNewerBundle();
    expect(await install(client), CurriculumInstall.installed);

    expect(await ids(client, 'goals'), {'variabelen'});
    final root = await client
        .container('goals')
        .read('variabelen', partitionKey: 'goal');
    expect(root!['title'], 'Variabelen (nieuw)');
    expect(await ids(client, 'questions'), {'toekennen_aaaa', 'toekennen_own'});
    expect(await ids(client, 'config'), {'global', 'classes'});
    expect(await ids(client, 'accounts'), {'local'});
    expect((await all(client, 'lo_beliefs')).single['mu'], 0.8);
    expect(await ids(client, 'progress'), {'p1'});
    expect(jsonDecode(curriculumVersionFile(data).readAsStringSync()), {
      'contentVersion': 'newer',
    });
  });

  test(
    'a newer bundle with one doc changed writes only that doc (#346)',
    () async {
      final first = <(int, int)>[];
      await install(open(), onProgress: (w, t) => first.add((w, t)));
      // Every doc of the fixture, counted up to the end.
      final total = first.first.$2;
      expect(total, greaterThan(1));
      expect(first.first, (0, total));
      expect(first.last, (total, total));
      expect(first, hasLength(total + 1));

      final client = open();
      Future<Map<String, Object?>> etags() async => {
        for (final container in [
          ...kBundleOwnedContainers,
          'config',
          'questions',
        ])
          for (final d in await all(client, container))
            '$container/${d['id']}': d['_etag'],
      };
      final before = await etags();
      expect(before, hasLength(total));
      final goals = readJson('goals.json');
      final toekennen = (goals['docs'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => d['id'] == 'toekennen');
      toekennen['title'] = 'Toekennen (nieuw)';
      writeJson('goals.json', goals);
      final manifest = readJson('manifest.json');
      manifest['contentVersion'] = 'one-changed';
      writeJson('manifest.json', manifest);

      final progress = <(int, int)>[];
      expect(
        await install(client, onProgress: (w, t) => progress.add((w, t))),
        CurriculumInstall.installed,
      );

      expect(progress, [(0, 1), (1, 1)]);
      final after = await etags();
      expect(after.keys, unorderedEquals(before.keys));
      for (final key in before.keys) {
        if (key == 'goals/toekennen') {
          expect(after[key], isNot(before[key]), reason: key);
        } else {
          expect(after[key], before[key], reason: key);
        }
      }
      final changed = await open()
          .container('goals')
          .read('toekennen', partitionKey: 'goal');
      expect(changed!['title'], 'Toekennen (nieuw)');
      expect(jsonDecode(curriculumVersionFile(data).readAsStringSync()), {
        'contentVersion': 'one-changed',
      });
    },
  );

  test('another storage than the local one gets the same docs, one at a '
      'time, and the same count', () async {
    final client = InMemoryCosmosClient();
    final progress = <(int, int)>[];
    expect(
      await installCurriculumBundle(
        source: DirectoryCurriculumBundleSource(bundleDir),
        client: client,
        versionFile: curriculumVersionFile(data),
        onProgress: (w, t) => progress.add((w, t)),
      ),
      CurriculumInstall.installed,
    );
    final goals = await client
        .container('goals')
        .query('SELECT * FROM c', crossPartition: true);
    expect(goals.map((g) => g['id']).toSet(), {'variabelen', 'toekennen'});
    final total = progress.first.$2;
    expect(progress.last, (total, total));
    expect(progress, hasLength(total + 1));
  });

  test('a newer bundle writes again what was changed on the pc', () async {
    await install(open());
    final client = open();
    final q = (await client
        .container('questions')
        .read('toekennen_aaaa', partitionKey: 'toekennen'))!;
    await client.container('questions').upsert({
      ...q,
      'difficulty': 'hard',
    }, partitionKey: 'toekennen');
    final manifest = readJson('manifest.json');
    manifest['contentVersion'] = 'newer';
    writeJson('manifest.json', manifest);

    final progress = <(int, int)>[];
    await install(client, onProgress: (w, t) => progress.add((w, t)));

    expect(progress, [(0, 1), (1, 1)]);
    final back = await open()
        .container('questions')
        .read('toekennen_aaaa', partitionKey: 'toekennen');
    expect(back!['difficulty'], isNot('hard'));
    expect(back[kFromBundleField], isTrue);
  });

  test('a bundle never writes a student container', () async {
    writeJson('accounts.json', {
      'container': 'accounts',
      'partitionKeyField': 'uid',
      'docs': [
        {'id': 'x', 'uid': 'x'},
      ],
    });
    final manifest = readJson('manifest.json');
    (manifest['containers'] as Map)['accounts'] = {
      'file': 'accounts.json',
      'count': 1,
    };
    writeJson('manifest.json', manifest);

    final client = open();
    expect(await install(client), CurriculumInstall.installed);
    expect(await ids(client, 'accounts'), isEmpty);
    expect(Directory(p.join(data.path, 'accounts')).existsSync(), isFalse);
  });

  test('no bundle: nothing is written and the app starts empty', () async {
    final empty = Directory.systemTemp.createTempSync('bundle_empty_');
    addTearDown(() => deleteDirRetrying(empty));
    File(p.join(empty.path, 'README.md')).writeAsStringSync('placeholder');
    final client = open();
    expect(
      await installCurriculumBundle(
        source: DirectoryCurriculumBundleSource(empty),
        client: client,
        versionFile: curriculumVersionFile(data),
      ),
      CurriculumInstall.noBundle,
    );
    expect(await ids(client, 'goals'), isEmpty);
    expect(curriculumVersionFile(data).existsSync(), isFalse);
  });

  test('no bundle after one was loaded leaves the loaded content', () async {
    await install(open());
    bundleDir.deleteSync(recursive: true);
    final client = open();
    expect(await install(client), CurriculumInstall.noBundle);
    expect(await ids(client, 'goals'), {'variabelen', 'toekennen'});
  });

  group('the bundle in the assets of this build (#265)', () {
    final shipped = Directory(kCurriculumAssetDir);
    Map<String, dynamic> shippedJson(String name) =>
        jsonDecode(File(p.join(shipped.path, name)).readAsStringSync())
            as Map<String, dynamic>;

    // On disk, as a user's first start: every doc to its own file (#263).
    // That takes a while, so it is written asynchronously, several files at
    // a time (#346): the isolate stays free to paint the loading page, and
    // the count reaches the end.
    test('the first start loads all of it into the local storage without '
        'holding up the isolate; the next start loads nothing', () async {
      final manifest = shippedJson('manifest.json');
      final counts = {
        for (final MapEntry(:key, :value)
            in (manifest['containers'] as Map).entries)
          key as String: (value as Map)['count'] as int,
      };
      expect(counts.keys, containsAll(['goals', 'content', 'instructions']));
      expect(counts['goals'], greaterThan(0));
      final total = counts.values.fold(0, (a, b) => a + b);

      // The longest the isolate went without running a timer.
      var last = DateTime.now();
      var longestPause = Duration.zero;
      final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final now = DateTime.now();
        final pause = now.difference(last);
        if (pause > longestPause) longestPause = pause;
        last = now;
      });
      addTearDown(ticker.cancel);
      final progress = <(int, int)>[];
      final watch = Stopwatch()..start();
      final result = await installCurriculumBundleAtStart(
        client: open(),
        localDataRoot: data,
        onProgress: (w, t) => progress.add((w, t)),
      );
      watch.stop();
      ticker.cancel();
      // ignore: avoid_print
      print(
        'Real bundle, first start: $total docs in '
        '${watch.elapsedMilliseconds} ms, longest pause '
        '${longestPause.inMilliseconds} ms',
      );

      expect(result, CurriculumInstall.installed);
      // Writing them one after the other, synchronously, held it up for the
      // whole install (some 14 s on a desktop).
      expect(longestPause, lessThan(const Duration(seconds: 3)));
      expect(progress.first, (0, total));
      expect(progress.last, (total, total));
      expect(progress, hasLength(total + 1));

      // On disk: the next start finds it all.
      final client = open();
      Future<List<Map<String, dynamic>>> stored(String container) => client
          .container(container)
          .query('SELECT * FROM c', crossPartition: true);
      for (final MapEntry(:key, :value) in counts.entries) {
        expect((await stored(key)).length, value, reason: key);
      }
      final questions = await stored('questions');
      expect(questions.every((q) => q[kFromBundleField] == true), isTrue);
      expect(jsonDecode(curriculumVersionFile(data).readAsStringSync()), {
        'contentVersion': manifest['contentVersion'],
      });

      // The next start.
      final again = <(int, int)>[];
      expect(
        await installCurriculumBundleAtStart(
          client: client,
          localDataRoot: data,
          onProgress: (w, t) => again.add((w, t)),
        ),
        CurriculumInstall.upToDate,
      );
      expect(again, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('holds only content: no student container, no school setting, no '
        'Cosmos field', () {
      final manifest = shippedJson('manifest.json');
      final containers = (manifest['containers'] as Map).cast<String, Map>();
      expect(containers.keys.toSet(), {
        ...kBundleOwnedContainers,
        'config',
        'questions',
      });
      final config = shippedJson('config.json')['docs'] as List;
      for (final doc in config.cast<Map<String, dynamic>>()) {
        expect(doc['id'], 'global');
        // Built from a list in the exporter: the model and the question
        // bank's mix, never the school's key or its other settings.
        expect(
          {
            'id',
            'type',
            'Model',
            'QuestionBankMinimum',
            'QuestionBankShare',
          }.containsAll(doc.keys),
          isTrue,
          reason: '${doc.keys}',
        );
      }
      final keyLike = RegExp(
        r'apikey|api_key|secret|password|token|accountkey|connectionstring',
        caseSensitive: false,
      );
      for (final MapEntry(:key, :value) in containers.entries) {
        final docs = shippedJson(value['file'] as String)['docs'] as List;
        expect(docs.length, value['count'], reason: key);
        for (final doc in docs.cast<Map<String, dynamic>>()) {
          final where = '$key/${doc['id']}';
          expect(
            doc.keys.where((k) => k.startsWith('_')),
            isEmpty,
            reason: where,
          );
          expect(doc.keys.where(keyLike.hasMatch), isEmpty, reason: where);
          if (key == 'questions') {
            expect(doc.containsKey('createdByUid'), isFalse, reason: where);
            expect(doc['status'], 'active', reason: where);
          }
        }
      }
    });
  });

  test('a broken bundle does not stop the start', () async {
    File(p.join(bundleDir.path, 'goals.json'))
        .deleteSync(); // listed, but missing
    final client = open();
    expect(
      await installCurriculumBundleAtStart(
        client: client,
        localDataRoot: data,
        source: DirectoryCurriculumBundleSource(bundleDir),
      ),
      isNull,
    );
    expect(curriculumVersionFile(data).existsSync(), isFalse);
  });
}
