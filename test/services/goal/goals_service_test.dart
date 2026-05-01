// 2.3 — Tests `GoalsService`. Covers the order math (1000-spacing), the
// reparent flow, the subtree backup→delete→restore round-trip, and the
// transactional batch shape. Container is injected via the constructor.
//
// We don't try to verify random uuid generation; a "non-empty id" assertion
// is enough.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/subtree_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

const _pk = CosmosPartitions.goal; // 'goal'

void main() {
  late MockCosmosContainer container;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(<BatchOperation>[]);
  });

  setUp(() {
    container = MockCosmosContainer();
  });

  GoalsService build() => GoalsService(container: container);

  void stubReadReturns(Map<String, Map<String, dynamic>> idToDoc) {
    when(
      () => container.read(any<String>(),
          partitionKey: any<Object>(named: 'partitionKey')),
    ).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.first as String;
      return idToDoc[id];
    });
  }

  group('_nextOrder (via createRoot / createChild)', () {
    test('createRoot returns 1000 when no roots exist', () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <Map<String, dynamic>>[]);
      when(
        () => container.create(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().createRoot('first');

      final captured = verify(
        () => container.create(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as Map<String, Object?>;
      expect(captured['order'], 1000);
      expect(captured['title'], 'first');
      expect(captured['parentId'], isNull);
      expect(captured['type'], _pk);
    });

    test('createRoot bumps the previous max order by 1000', () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => [
            {'o': 3000},
          ]);
      when(
        () => container.create(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().createRoot('next');

      final captured = verify(
        () => container.create(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as Map<String, Object?>;
      expect(captured['order'], 4000);
    });

    test('createChild scopes the order query by parentId', () async {
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => [
            {'o': 2000},
          ]);
      when(
        () => container.create(
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().createChild('parent-1', 'child');

      final captured = verify(
        () => container.query(
          captureAny<String>(),
          parameters: captureAny<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], contains('c.parentId = @parentId'));
      expect(captured[1], {'@parentId': 'parent-1'});

      final createCaptured = verify(
        () => container.create(
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as Map<String, Object?>;
      expect(createCaptured['parentId'], 'parent-1');
      expect(createCaptured['order'], 3000);
    });
  });

  group('reparent', () {
    test('reads the doc, then patches parentId + bumps order to end-of-list',
        () async {
      // First call (the read inside _nextOrder via query) returns 5000;
      // second is the actual doc read.
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => [
            {'o': 5000},
          ]);
      stubReadReturns({
        'goal-1': {
          'id': 'goal-1',
          'type': _pk,
          'title': 'Loops',
          'parentId': 'old-parent',
          'order': 1000,
        },
      });
      when(
        () => container.replace(
          any<String>(),
          any<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => <String, dynamic>{});

      await build().reparent('goal-1', 'new-parent');

      final captured = verify(
        () => container.replace(
          captureAny<String>(),
          captureAny<Map<String, Object?>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured;
      expect(captured[0], 'goal-1');
      final doc = captured[1] as Map<String, Object?>;
      expect(doc['parentId'], 'new-parent');
      expect(doc['order'], 6000);
      // Other fields preserved.
      expect(doc['title'], 'Loops');
    });
  });

  group('applyOrder', () {
    test('rewrites order with 1000 spacing and emits one upsert per id in a '
        'single batch', () async {
      stubReadReturns({
        'a': {'id': 'a', 'type': _pk, 'title': 'A', 'order': 9000},
        'b': {'id': 'b', 'type': _pk, 'title': 'B', 'order': 7000},
        'c': {'id': 'c', 'type': _pk, 'title': 'C', 'order': 8000},
      });
      when(
        () => container.executeBatch(
          any<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async {});

      await build().applyOrder('parent-1', ['a', 'b', 'c']);

      final captured = verify(
        () => container.executeBatch(
          captureAny<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as List<BatchOperation>;
      expect(captured, hasLength(3));
      // Each op should be an Upsert with the new order + parentId.
      final docs = captured
          .map((o) => (o.toJson()['resourceBody'] as Map<String, Object?>))
          .toList();
      expect(docs[0]['id'], 'a');
      expect(docs[0]['order'], 1000);
      expect(docs[0]['parentId'], 'parent-1');
      expect(docs[1]['order'], 2000);
      expect(docs[2]['order'], 3000);
      expect(captured.map((o) => o.operationType).toSet(), {'Upsert'});
    });

    test('skips ids whose doc is missing', () async {
      stubReadReturns({
        'a': {'id': 'a', 'type': _pk, 'title': 'A', 'order': 1},
      });
      when(
        () => container.executeBatch(
          any<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async {});

      await build().applyOrder(null, ['a', 'gone', 'also-gone']);

      final captured = verify(
        () => container.executeBatch(
          captureAny<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as List<BatchOperation>;
      expect(captured, hasLength(1));
      expect(
        (captured.single.toJson()['resourceBody'] as Map)['id'],
        'a',
      );
    });

    test('empty input is a no-op (no batch call at all)', () async {
      await build().applyOrder('parent', const []);
      verifyNever(
        () => container.executeBatch(
          any<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });
  });

  group('backupSubtree → deleteSubtree → restoreSubtree round-trip', () {
    Map<String, Map<String, dynamic>> tree() => {
          'root': {
            'id': 'root',
            'type': _pk,
            'title': 'Root',
            'description': 'root desc',
            'parentId': null,
            'order': 1000,
            'optional': false,
            'suggestions': const ['s'],
            'knownConcepts': const [],
          },
          'child-a': {
            'id': 'child-a',
            'type': _pk,
            'title': 'A',
            'description': null,
            'parentId': 'root',
            'order': 1000,
            'optional': false,
            'suggestions': const [],
            'knownConcepts': const [],
          },
          'child-b': {
            'id': 'child-b',
            'type': _pk,
            'title': 'B',
            'description': null,
            'parentId': 'root',
            'order': 2000,
            'optional': true,
            'suggestions': const ['x', 'y'],
            'knownConcepts': const [],
          },
        };

    setUp(() {
      // _collectSubtree calls _fetchAll via container.query
      when(
        () => container.query(
          any<String>(),
          parameters: any<Map<String, Object?>>(named: 'parameters'),
          partitionKey: any<Object?>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async => tree().values.toList());
      when(
        () => container.executeBatch(
          any<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).thenAnswer((_) async {});
    });

    test('backup then restore preserves ids and core fields', () async {
      final svc = build();
      final backup = await svc.backupSubtree('root');
      expect(backup.nodes.map((n) => n.$1).toSet(),
          {'root', 'child-a', 'child-b'});

      await svc.restoreSubtree(backup);

      final captured = verify(
        () => container.executeBatch(
          captureAny<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as List<BatchOperation>;
      expect(captured, hasLength(3));
      final ids = captured
          .map((o) => (o.toJson()['resourceBody'] as Map)['id'])
          .toSet();
      expect(ids, {'root', 'child-a', 'child-b'});
      // Each upsert carries the partition-key field.
      for (final op in captured) {
        expect((op.toJson()['resourceBody'] as Map)['type'], _pk);
      }
    });

    test('deleteSubtree fires one Delete op per node in a single batch',
        () async {
      await build().deleteSubtree('root');
      final captured = verify(
        () => container.executeBatch(
          captureAny<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      ).captured.single as List<BatchOperation>;
      expect(captured, hasLength(3));
      expect(captured.map((o) => o.operationType).toSet(), {'Delete'});
      expect(captured.map((o) => o.toJson()['id']).toSet(),
          {'root', 'child-a', 'child-b'});
    });

    test('countDescendants = subtree size minus 1', () async {
      expect(await build().countDescendants('root'), 2);
    });

    test('restoreSubtree on empty backup is a no-op', () async {
      await build().restoreSubtree(SubtreeBackup(const []));
      verifyNever(
        () => container.executeBatch(
          any<List<BatchOperation>>(),
          partitionKey: any<Object>(named: 'partitionKey'),
        ),
      );
    });
  });
}
