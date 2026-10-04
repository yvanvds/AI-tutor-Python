// Issue #223 — the in-memory Cosmos keeps an `_etag` per doc, as Cosmos
// does, and honours `If-Match` on a replace, so a test can put a second
// writer between a read and the replace that follows it. Most tests run
// against this fake, so what it promises is pinned here.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_cosmos.dart';

Map<String, dynamic> _doc([Map<String, dynamic> extra = const {}]) => {
  'id': 'u1',
  'uid': 'u1',
  ...extra,
};

Matcher _cosmosError(int status) => throwsA(
  isA<CosmosException>().having((e) => e.statusCode, 'statusCode', status),
);

void main() {
  test('every write gives the doc a new _etag, which reads, queries and the '
      'written doc carry', () async {
    final store = InMemoryCosmos([_doc()]);
    final c = store.container;
    final seeded = (await c.read('u1', partitionKey: 'u1'))!['_etag'];
    expect(seeded, isA<String>());

    final etags = <Object?>[
      seeded,
      (await c.upsert(_doc({'x': 1}), partitionKey: 'u1'))['_etag'],
      (await c.replace('u1', _doc({'x': 2}), partitionKey: 'u1'))['_etag'],
    ];
    await c.executeBatch([
      BatchOperation.replace('u1', _doc({'x': 3})),
    ], partitionKey: 'u1');
    etags.add((await c.read('u1', partitionKey: 'u1'))!['_etag']);
    expect(etags.toSet(), hasLength(4));

    final rows = await c.query('SELECT * FROM c', crossPartition: true);
    expect(rows.single['_etag'], etags.last);
    expect(store.etagOf('u1'), etags.last);
    expect(
      (await c.create({'id': 'u2', 'uid': 'u2'}, partitionKey: 'u2'))['_etag'],
      store.etagOf('u2'),
    );
  });

  test('the stored doc is what the writer sent: a service that strips the '
      'system fields leaves none behind', () async {
    final store = InMemoryCosmos([_doc()]);
    final read = (await store.container.read('u1', partitionKey: 'u1'))!;
    read.removeWhere((k, _) => k.startsWith('_'));
    await store.container.replace('u1', read, partitionKey: 'u1');
    expect(store['u1']!.keys, isNot(contains('_etag')));
    expect(
      (await store.container.read('u1', partitionKey: 'u1'))!['_etag'],
      store.etagOf('u1'),
    );
  });

  test('a replace with the etag it read lands; one with an older etag gets '
      'a 412 and writes nothing; one without ifMatch is not checked', () async {
    final store = InMemoryCosmos([
      _doc({'x': 0}),
    ]);
    final c = store.container;
    final first = (await c.read('u1', partitionKey: 'u1'))!;
    final stale = first['_etag'] as String;

    await c.replace(
      'u1',
      {...first, 'x': 1},
      partitionKey: 'u1',
      ifMatch: stale,
    );
    expect(store['u1']!['x'], 1);

    await expectLater(
      c.replace('u1', {...first, 'x': 2}, partitionKey: 'u1', ifMatch: stale),
      _cosmosError(412),
    );
    expect(store['u1']!['x'], 1);

    await c.replace('u1', {...first, 'x': 3}, partitionKey: 'u1');
    expect(store['u1']!['x'], 3);

    await expectLater(
      c.replace('gone', _doc(), partitionKey: 'gone', ifMatch: stale),
      _cosmosError(404),
    );
  });

  test('beforeReplace runs between the read and the replace: a write it '
      'makes turns the replace into a 412', () async {
    final store = InMemoryCosmos([
      _doc({'x': 0}),
    ]);
    final c = store.container;
    final seen = <String>[];
    store.beforeReplace = (id, doc) async {
      seen.add('$id:${doc['x']}');
      store.beforeReplace = null;
      await c.upsert(_doc({'x': 'other'}), partitionKey: 'u1');
    };
    final read = (await c.read('u1', partitionKey: 'u1'))!;

    await expectLater(
      c.replace(
        'u1',
        {...read, 'x': 'mine'},
        partitionKey: 'u1',
        ifMatch: read['_etag'] as String,
      ),
      _cosmosError(412),
    );
    expect(seen, ['u1:mine']);
    expect(store['u1']!['x'], 'other');
  });
}
