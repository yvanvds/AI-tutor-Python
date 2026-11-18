// The content the stand-alone mode ships with (#266): loaded at start when
// it is new, never over the student's own data, never twice.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/curriculum_bundle.dart';
import 'package:ai_tutor_python/core/local_cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  tearDown(() {
    for (final d in [data, bundleDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  LocalCosmosClient open() => LocalCosmosClient.open(data);

  Future<CurriculumInstall> install(LocalCosmosClient client) =>
      installCurriculumBundle(
        source: DirectoryCurriculumBundleSource(bundleDir),
        client: client,
        versionFile: curriculumVersionFile(data),
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
    addTearDown(() => empty.deleteSync(recursive: true));
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

  test('the assets of this build hold no bundle yet: the start loads '
      'nothing', () async {
    final client = open();
    expect(
      await installCurriculumBundleAtStart(client: client, localDataRoot: data),
      CurriculumInstall.noBundle,
    );
    expect(await ids(client, 'goals'), isEmpty);
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
