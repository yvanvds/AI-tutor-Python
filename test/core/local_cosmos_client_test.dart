// The stand-alone storage (#263): Cosmos' interface over JSON files, with
// the behaviour the app relies on (409, 412, atomic batch, ttl) and data
// that is still there when the app starts again.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/local_cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/delete_dir.dart';

Matcher _status(int code) => throwsA(
  isA<CosmosException>().having((e) => e.statusCode, 'statusCode', code),
);

void main() {
  late Directory root;
  late DateTime now;

  LocalCosmosClient open() => LocalCosmosClient.open(root, clock: () => now);

  setUp(() {
    root = Directory.systemTemp.createTempSync('local_cosmos_test_');
    now = DateTime.utc(2026, 11, 18, 12);
  });

  tearDown(() => deleteDirRetrying(root));

  Map<String, Object?> belief(String id, {String uid = 'u1', int n = 0}) => {
    'id': id,
    'uid': uid,
    'subgoalId': 's1',
    'n': n,
  };

  group('as Cosmos behaves', () {
    test('create on an existing id is a 409, and writes nothing', () async {
      final c = open().container('lo_beliefs');
      await c.create(belief('b1'), partitionKey: 'u1');
      await expectLater(
        c.create(belief('b1', n: 9), partitionKey: 'u1'),
        _status(409),
      );
      expect((await c.read('b1', partitionKey: 'u1'))!['n'], 0);
    });

    test('the same id in another partition is another doc', () async {
      final c = open().container('lo_beliefs');
      await c.create(belief('b1'), partitionKey: 'u1');
      await c.create(belief('b1', uid: 'u2', n: 2), partitionKey: 'u2');
      expect((await c.read('b1', partitionKey: 'u2'))!['n'], 2);
    });

    test('replace with ifMatch on a changed doc is a 412', () async {
      final c = open().container('accounts');
      final first = await c.upsert({
        'id': 'u1',
        'uid': 'u1',
        'xp': 1,
      }, partitionKey: 'u1');
      final etag = first['_etag'] as String;

      // Another write lands between the read and the replace.
      await c.upsert({'id': 'u1', 'uid': 'u1', 'xp': 5}, partitionKey: 'u1');
      await expectLater(
        c.replace(
          'u1',
          {'id': 'u1', 'uid': 'u1', 'xp': 2},
          partitionKey: 'u1',
          ifMatch: etag,
        ),
        _status(412),
      );
      expect((await c.read('u1', partitionKey: 'u1'))!['xp'], 5);

      // With the current etag it lands, and gets a new one.
      final current = (await c.read('u1', partitionKey: 'u1'))!['_etag'];
      final replaced = await c.replace(
        'u1',
        {'id': 'u1', 'uid': 'u1', 'xp': 6},
        partitionKey: 'u1',
        ifMatch: current as String,
      );
      expect(replaced['xp'], 6);
      expect(replaced['_etag'], isNot(current));
    });

    test('replace of a missing doc is a 404', () async {
      final c = open().container('accounts');
      await expectLater(
        c.replace('nope', {'id': 'nope', 'uid': 'u1'}, partitionKey: 'u1'),
        _status(404),
      );
    });

    test('executeBatch lands whole or not at all', () async {
      final c = open().container('goals');
      Map<String, Object?> goal(String id) => {'id': id, 'type': 'goal'};
      await c.create(goal('g1'), partitionKey: 'goal');

      // The last op fails (g1 exists): the first two do not land either.
      await expectLater(
        c.executeBatch([
          BatchOperation.upsert(goal('g2')),
          BatchOperation.delete('g1'),
          BatchOperation.create(goal('g1')),
          BatchOperation.create(goal('g1')),
        ], partitionKey: 'goal'),
        _status(409),
      );
      expect(await c.read('g2', partitionKey: 'goal'), isNull);
      expect(await c.read('g1', partitionKey: 'goal'), isNotNull);

      // A delete of a missing doc fails the batch too, as in Cosmos.
      await expectLater(
        c.executeBatch([
          BatchOperation.upsert(goal('g2')),
          BatchOperation.delete('missing'),
        ], partitionKey: 'goal'),
        _status(404),
      );
      expect(await c.read('g2', partitionKey: 'goal'), isNull);

      await c.executeBatch([
        BatchOperation.upsert(goal('g2')),
        BatchOperation.delete('g1'),
      ], partitionKey: 'goal');
      expect(await c.read('g2', partitionKey: 'goal'), isNotNull);
      expect(await c.read('g1', partitionKey: 'goal'), isNull);

      // And on disk.
      final reopened = open().container('goals');
      expect(await reopened.read('g2', partitionKey: 'goal'), isNotNull);
      expect(await reopened.read('g1', partitionKey: 'goal'), isNull);
    });

    test('a doc with a ttl expires, and is gone from disk at the next '
        'start', () async {
      final c = open().container('turn_content');
      await c.upsert({
        'id': 't1',
        'uid': 'u1',
        'ttl': 3600,
      }, partitionKey: 'u1');
      await c.upsert({'id': 't2', 'uid': 'u1'}, partitionKey: 'u1');

      now = now.add(const Duration(minutes: 59));
      expect(await c.read('t1', partitionKey: 'u1'), isNotNull);

      now = now.add(const Duration(minutes: 2));
      expect(await c.read('t1', partitionKey: 'u1'), isNull);
      expect(await c.query('SELECT c.id FROM c', partitionKey: 'u1'), [
        {'id': 't2'},
      ]);

      open();
      final files = Directory(p.join(root.path, 'turn_content'))
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(files, hasLength(1));
      expect(files.single.readAsStringSync(), contains('"t2"'));
    });

    test('every container exists, also one nobody wrote to', () async {
      final c = open().container('reports');
      expect(await c.read('r1', partitionKey: 'u1'), isNull);
      expect(await c.query('SELECT * FROM c', crossPartition: true), isEmpty);
      await c.delete('r1', partitionKey: 'u1');
    });

    test('a write whose partition key is not the doc\'s own is a 400', () {
      final c = open().container('progress');
      expect(
        c.upsert({'id': 'p1', 'uid': 'u1'}, partitionKey: 'u2'),
        _status(400),
      );
    });

    test('a query it does not understand is a 400', () {
      final c = open().container('progress');
      expect(c.query('SELECT VALUE COUNT(1) FROM c'), _status(400));
    });

    test('a query to one partition sees only that partition', () async {
      final c = open().container('progress');
      await c.upsert({'id': 'a', 'uid': 'u1'}, partitionKey: 'u1');
      await c.upsert({'id': 'b', 'uid': 'u2'}, partitionKey: 'u2');
      expect(await c.query('SELECT c.id FROM c', partitionKey: 'u1'), [
        {'id': 'a'},
      ]);
      expect(
        await c.query('SELECT c.id FROM c', crossPartition: true),
        hasLength(2),
      );
    });

    test('docs handed out are copies', () async {
      final c = open().container('progress');
      await c.upsert({
        'id': 'a',
        'uid': 'u1',
        'list': [1],
      }, partitionKey: 'u1');
      final read = (await c.read('a', partitionKey: 'u1'))!;
      (read['list'] as List).add(2);
      expect((await c.read('a', partitionKey: 'u1'))!['list'], [1]);
    });
  });

  group('on disk', () {
    test('saved, opened again over the same folder, all found back', () async {
      final first = open();
      await first.container('accounts').upsert({
        'id': 'u1',
        'uid': 'u1',
        'name': 'Profiel',
      }, partitionKey: 'u1');
      await first.container('translations').upsert({
        'id': 'goal_g1',
        'language': 'en',
        'title': 'Variables',
      }, partitionKey: 'en');
      await first
          .container('lo_beliefs')
          .upsert(belief('b1', n: 4), partitionKey: 'u1');
      await first
          .container('lo_beliefs')
          .upsert(belief('b2'), partitionKey: 'u1');
      await first.container('lo_beliefs').delete('b2', partitionKey: 'u1');
      final etag = (await first
          .container('accounts')
          .read('u1', partitionKey: 'u1'))!['_etag'];

      final second = open();
      final account = await second
          .container('accounts')
          .read('u1', partitionKey: 'u1');
      expect(account!['name'], 'Profiel');
      // The etag survives, so a read before and a replace after a restart
      // still match.
      expect(account['_etag'], etag);
      expect(
        (await second
            .container('translations')
            .read('goal_g1', partitionKey: 'en'))!['title'],
        'Variables',
      );
      expect(
        await second
            .container('lo_beliefs')
            .query(
              'SELECT * FROM c WHERE c.uid = @uid',
              parameters: {'@uid': 'u1'},
              partitionKey: 'u1',
            ),
        [isA<Map<String, dynamic>>().having((d) => d['n'], 'n', 4)],
      );
    });

    test('one JSON file per document, under container and partition', () async {
      await open()
          .container('lo_beliefs')
          .upsert(belief('b1'), partitionKey: 'u1');
      final file = File(p.join(root.path, 'lo_beliefs', 'u1', 'b1.json'));
      expect(file.existsSync(), isTrue);
      final stored = jsonDecode(file.readAsStringSync()) as Map;
      expect(stored['partitionKey'], 'u1');
      expect((stored['doc'] as Map)['id'], 'b1');
    });

    test('a write leaves no temporary file; one left by a crash is cleaned '
        'up and does not count', () async {
      await open()
          .container('lo_beliefs')
          .upsert(belief('b1'), partitionKey: 'u1');
      final dir = Directory(p.join(root.path, 'lo_beliefs', 'u1'));
      expect(dir.listSync().map((e) => p.basename(e.path)), ['b1.json']);

      // A crash between writing the temporary file and renaming it.
      File(p.join(dir.path, 'b1.json.tmp')).writeAsStringSync('{"half');
      final reopened = open().container('lo_beliefs');
      expect((await reopened.read('b1', partitionKey: 'u1'))!['id'], 'b1');
      expect(dir.listSync().map((e) => p.basename(e.path)), ['b1.json']);
    });

    test('ids that differ only in case, or are not file names, stay '
        'apart', () async {
      final c = open().container('questions');
      final ids = ['Ab', 'ab', 'a/b', 'a:b?', 'con', 'x' * 300];
      for (final id in ids) {
        await c.upsert({'id': id, 'subgoalId': 'S 1'}, partitionKey: 'S 1');
      }
      final reopened = open().container('questions');
      for (final id in ids) {
        expect((await reopened.read(id, partitionKey: 'S 1'))!['id'], id);
      }
      expect(localStorageSafeName('Ab'), isNot(localStorageSafeName('ab')));
      expect(localStorageSafeName('x' * 300).length, lessThanOrEqualTo(80));
    });
  });

  group('the app mode', () {
    test('stand-alone mode gets the local storage', () {
      final client = CosmosClient.forMode(
        const StandaloneMode(),
        localDataRoot: root,
      );
      expect(client, isA<LocalCosmosClient>());
    });

    test('stand-alone data lives under the stand-alone folder', () async {
      final base = Directory(p.join(root.path, 'support'));
      final dir = await standaloneDataDir(
        const StandaloneMode(),
        appSupportDir: () async => base,
      );
      expect(dir.path, p.join(base.path, 'standalone', 'data'));
    });
  });
}
