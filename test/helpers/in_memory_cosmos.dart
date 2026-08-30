// In-memory stand-in for one `CosmosContainer`, built on the mocktail mock so
// real services (GoalsService, ContentService, ModuleService) can run
// unmodified against a map of docs. Interprets just enough of the SQL the
// services emit: parentId filters, root filter, ORDER BY title / order, and
// the `TOP 1 ... AS o` next-order query.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:mocktail/mocktail.dart';

import 'mocks.dart';

class InMemoryCosmos {
  InMemoryCosmos([Iterable<Map<String, dynamic>> seed = const []]) {
    for (final d in seed) {
      docs[d['id'] as String] = Map<String, dynamic>.from(d);
    }
    _wire();
  }

  final MockCosmosContainer container = MockCosmosContainer();
  final Map<String, Map<String, dynamic>> docs = {};

  Map<String, dynamic>? operator [](String id) => docs[id];

  static Map<String, dynamic> _copy(Map<String, Object?> d) =>
      Map<String, dynamic>.from(d);

  void _wire() {
    when(
      () => container.read(
        any<String>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((inv) async {
      final id = inv.positionalArguments.first as String;
      final d = docs[id];
      return d == null ? null : _copy(d);
    });

    when(
      () => container.create(
        any<Map<String, Object?>>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((inv) async {
      final d = _copy(inv.positionalArguments.first as Map<String, Object?>);
      final id = d['id'] as String;
      if (docs.containsKey(id)) {
        throw CosmosException(409, 'id $id exists', code: 'Conflict');
      }
      docs[id] = d;
      return _copy(d);
    });

    when(
      () => container.upsert(
        any<Map<String, Object?>>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((inv) async {
      final d = _copy(inv.positionalArguments.first as Map<String, Object?>);
      docs[d['id'] as String] = d;
      return _copy(d);
    });

    when(
      () => container.replace(
        any<String>(),
        any<Map<String, Object?>>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      final d = _copy(inv.positionalArguments[1] as Map<String, Object?>);
      docs[id] = d;
      return _copy(d);
    });

    when(
      () => container.delete(
        any<String>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((inv) async {
      docs.remove(inv.positionalArguments.first as String);
    });

    when(
      () => container.executeBatch(
        any<List<BatchOperation>>(),
        partitionKey: any<Object>(named: 'partitionKey'),
      ),
    ).thenAnswer((inv) async {
      final ops = inv.positionalArguments.first as List<BatchOperation>;
      for (final op in ops) {
        switch (op.operationType) {
          case 'Delete':
            docs.remove(op.id);
          case 'Create':
          case 'Upsert':
            final d = _copy(op.resourceBody!);
            docs[d['id'] as String] = d;
          case 'Replace':
            docs[op.id!] = _copy(op.resourceBody!);
        }
      }
    });

    when(
      () => container.query(
        any<String>(),
        parameters: any<Map<String, Object?>>(named: 'parameters'),
        partitionKey: any<Object?>(named: 'partitionKey'),
      ),
    ).thenAnswer((inv) async {
      final sql = inv.positionalArguments.first as String;
      final params =
          (inv.namedArguments[#parameters] as Map<String, Object?>?) ??
          const {};
      return _query(sql, params);
    });
  }

  List<Map<String, dynamic>> _query(String sql, Map<String, Object?> params) {
    Iterable<Map<String, dynamic>> rows = docs.values.map(_copy);

    if (sql.contains('c.parentId = @parentId')) {
      final pid = params['@parentId'];
      rows = rows.where((d) => d['parentId'] == pid);
    } else if (sql.contains('IS_NULL(c.parentId)')) {
      rows = rows.where((d) => d['parentId'] == null);
    }

    var list = rows.toList();
    if (sql.contains('ORDER BY c.title')) {
      list.sort(
        (a, b) => ((a['title'] as String?) ?? '').compareTo(
          (b['title'] as String?) ?? '',
        ),
      );
    } else if (sql.contains('ORDER BY c["order"] DESC')) {
      list.sort(
        (a, b) =>
            ((b['order'] as int?) ?? 0).compareTo((a['order'] as int?) ?? 0),
      );
    } else if (sql.contains('ORDER BY c["order"]')) {
      list.sort(
        (a, b) =>
            ((a['order'] as int?) ?? 0).compareTo((b['order'] as int?) ?? 0),
      );
    }

    if (sql.contains('SELECT TOP 1 c["order"] AS o')) {
      if (list.isEmpty) return const [];
      return [
        {'o': list.first['order']},
      ];
    }
    return list;
  }
}
