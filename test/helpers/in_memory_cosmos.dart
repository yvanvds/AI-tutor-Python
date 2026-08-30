// In-memory stand-in for `CosmosContainer` / `CosmosClient`, so real
// services (GoalsService, ContentService, ModuleService, AccountService, ...)
// can run unmodified against a map of docs. Interprets just enough of the
// SQL the services emit: parentId filters, root filter, uid / goalId /
// subgoalId filters, ORDER BY title / order, and the `TOP 1 ... AS o`
// next-order query.
//
// Two ways to use it:
//
//   - per service: `GoalsService(container: InMemoryCosmos([...]).container)`
//     (widget tests under `test/`);
//   - process-wide: `InMemoryCosmosClient(...).install()` swaps the
//     `CosmosClient.instance` singleton so every `CosmosPaths.*()` handle —
//     including the services without a `container:` seam — resolves to an
//     in-memory container (the `integration_test/` harness, #28).
//
// Pure Dart, no mocktail: `implements` on `CosmosContainer` / `CosmosClient`
// is enough because nothing outside `cosmos_client.dart` touches their
// private members.

import 'package:ai_tutor_python/core/cosmos_client.dart';

class InMemoryCosmos {
  InMemoryCosmos([Iterable<Map<String, dynamic>> seed = const []]) {
    for (final d in seed) {
      docs[d['id'] as String] = Map<String, dynamic>.from(d);
    }
    container = _InMemoryContainer(this);
  }

  late final CosmosContainer container;
  final Map<String, Map<String, dynamic>> docs = {};

  Map<String, dynamic>? operator [](String id) => docs[id];

  static Map<String, dynamic> _copy(Map<String, Object?> d) =>
      Map<String, dynamic>.from(d);

  Map<String, dynamic>? read(String id) {
    final d = docs[id];
    return d == null ? null : _copy(d);
  }

  Map<String, dynamic> create(Map<String, Object?> doc) {
    final d = _copy(doc);
    final id = d['id'] as String;
    if (docs.containsKey(id)) {
      throw CosmosException(409, 'id $id exists', code: 'Conflict');
    }
    docs[id] = d;
    return _copy(d);
  }

  Map<String, dynamic> upsert(Map<String, Object?> doc) {
    final d = _copy(doc);
    docs[d['id'] as String] = d;
    return _copy(d);
  }

  Map<String, dynamic> replace(String id, Map<String, Object?> doc) {
    final d = _copy(doc);
    docs[id] = d;
    return _copy(d);
  }

  void delete(String id) => docs.remove(id);

  void executeBatch(List<BatchOperation> ops) {
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
  }

  List<Map<String, dynamic>> query(String sql, Map<String, Object?> params) {
    Iterable<Map<String, dynamic>> rows = docs.values.map(_copy);

    if (sql.contains('c.parentId = @parentId')) {
      final pid = params['@parentId'];
      rows = rows.where((d) => d['parentId'] == pid);
    } else if (sql.contains('IS_NULL(c.parentId)')) {
      rows = rows.where((d) => d['parentId'] == null);
    }

    // Per-user containers (progress, progress_history, lo_beliefs,
    // turn_history) filter on uid and optionally on goal / subgoal.
    if (sql.contains('c.uid = @uid')) {
      rows = rows.where((d) => d['uid'] == params['@uid']);
    }
    if (sql.contains('c.goalId = @goalId')) {
      rows = rows.where((d) => d['goalId'] == params['@goalId']);
    }
    if (sql.contains('c.subgoalId = @sid')) {
      rows = rows.where((d) => d['subgoalId'] == params['@sid']);
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

class _InMemoryContainer implements CosmosContainer {
  _InMemoryContainer(this._store);

  final InMemoryCosmos _store;

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) async => _store.read(id);

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) async => _store.query(sql, parameters);

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async => _store.create(doc);

  @override
  Future<Map<String, dynamic>> upsert(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async => _store.upsert(doc);

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async => _store.replace(id, doc);

  @override
  Future<void> delete(String id, {required Object partitionKey}) async =>
      _store.delete(id);

  @override
  Future<void> executeBatch(
    List<BatchOperation> ops, {
    required Object partitionKey,
  }) async => _store.executeBatch(ops);
}

/// Whole-database fake: one [InMemoryCosmos] per container name, created on
/// first use. [install] makes it the process-wide `CosmosClient.instance`.
class InMemoryCosmosClient implements CosmosClient {
  InMemoryCosmosClient([Map<String, InMemoryCosmos> containers = const {}])
    : _containers = Map.of(containers);

  final Map<String, InMemoryCosmos> _containers;

  /// The store behind [containerId], e.g. `cosmos['goals'].docs`.
  InMemoryCosmos operator [](String containerId) =>
      _containers.putIfAbsent(containerId, InMemoryCosmos.new);

  @override
  CosmosContainer container(String containerId) => this[containerId].container;

  /// Routes every `CosmosPaths.*()` handle through this fake.
  void install() => CosmosClient.overrideInstance(this);
}
