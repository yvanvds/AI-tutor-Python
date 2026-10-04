// In-memory stand-in for `CosmosContainer` / `CosmosClient`, so real
// services (GoalsService, ContentService, ModuleService, AccountService, ...)
// can run unmodified against a map of docs. Interprets just enough of the
// SQL the services emit: parentId filters, root filter, uid / goalId /
// subgoalId filters, the signal-event and acknowledgement filters of
// `turn_history`, ORDER BY title / order, and the `TOP 1 ... AS o`
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
//
// Ids are unique per container, which is what every container but one
// relies on. `translations` (#206) holds the same id once per language, so
// it runs [InMemoryCosmos.partitioned]: keyed on (partition, id) the way
// Cosmos keys it, with single-partition queries kept to their partition.
//
// Every write gives the doc a fresh `_etag`, which every doc handed out
// carries, as in Cosmos; a replace with `ifMatch` answers 412 when the doc
// changed since (#223). [InMemoryCosmos.beforeReplace] lets a test put
// another app's write between a read and the replace that follows it.

import 'package:ai_tutor_python/core/cosmos_client.dart';

class InMemoryCosmos {
  InMemoryCosmos([Iterable<Map<String, dynamic>> seed = const []])
    : partitionKeyField = null {
    _init(seed);
  }

  /// A container partitioned on the doc field [partitionKeyField] in which
  /// one id can exist in several partitions (`translations`, #206). Docs are
  /// kept under `'$partitionKey/$id'` — `cosmos['en/content_s1']` — a write
  /// whose partition key does not match the doc's field fails as it does in
  /// Cosmos, and a query sent to one partition sees only that partition.
  InMemoryCosmos.partitioned(
    String this.partitionKeyField, [
    Iterable<Map<String, dynamic>> seed = const [],
  ]) {
    _init(seed);
  }

  void _init(Iterable<Map<String, dynamic>> seed) {
    for (final d in seed) {
      _put(_keyOf(d), Map<String, dynamic>.from(d));
    }
    container = _InMemoryContainer(this);
  }

  /// The doc field holding the partition key, when ids are unique per
  /// partition rather than per container (see [InMemoryCosmos.partitioned]).
  final String? partitionKeyField;

  late final CosmosContainer container;

  /// Keyed on id, or on `'$partitionKey/$id'` for a partitioned container.
  ///
  /// Each doc as it was last written — what the writer sent, so a test sees
  /// whether a service echoed Cosmos' system fields back. The `_etag` the
  /// docs handed out carry is kept apart ([etagOf]); a test that changes a
  /// doc here directly changes no `_etag`, and one it puts here directly has
  /// none until the store writes it. To stand in for another app's write,
  /// go through [upsert] or [replace].
  final Map<String, Map<String, dynamic>> docs = {};

  /// Runs before every replace through [container], after the caller read
  /// the doc and before the replace's `If-Match` is checked (#223): a test
  /// puts another app's write here — the teacher's badge landing between
  /// the student's read and replace. It sees the id and the doc as sent.
  Future<void> Function(String id, Map<String, Object?> doc)? beforeReplace;

  final Map<String, String> _etags = {};
  int _writes = 0;

  /// The `_etag` of the doc under [key]: a new one on every write.
  String? etagOf(String key) => _etags[key];

  void _put(String key, Map<String, dynamic> d) {
    docs[key] = d;
    _etags[key] = '"etag-${++_writes}"';
  }

  void _remove(String key) {
    docs.remove(key);
    _etags.remove(key);
  }

  /// A copy of the doc under [key] as Cosmos hands it out, with its `_etag`.
  Map<String, dynamic> _out(String key) {
    final d = _copy(docs[key]!);
    final etag = _etags[key];
    if (etag != null) d['_etag'] = etag;
    return d;
  }

  Map<String, dynamic>? operator [](String key) => docs[key];

  static Map<String, dynamic> _copy(Map<String, Object?> d) =>
      Map<String, dynamic>.from(d);

  String _key(String id, Object? partitionKey) =>
      partitionKeyField == null ? id : '$partitionKey/$id';

  String _keyOf(Map<String, dynamic> d) => _key(
    d['id'] as String,
    partitionKeyField == null ? null : d[partitionKeyField],
  );

  /// Cosmos rejects a write whose partition-key header is not the doc's own
  /// partition key; a partitioned fake does too.
  void _checkPartition(Map<String, dynamic> d, Object? partitionKey) {
    final field = partitionKeyField;
    if (field == null || d[field] == partitionKey) return;
    throw CosmosException(
      400,
      'PartitionKey extracted from document (${d[field]}) does not match the '
      'one specified in the header ($partitionKey)',
      code: 'BadRequest',
    );
  }

  Map<String, dynamic>? read(String id, {Object? partitionKey}) {
    final key = _key(id, partitionKey);
    return docs.containsKey(key) ? _out(key) : null;
  }

  Map<String, dynamic> create(
    Map<String, Object?> doc, {
    Object? partitionKey,
  }) {
    final d = _copy(doc);
    _checkPartition(d, partitionKey);
    final id = d['id'] as String;
    if (docs.containsKey(_keyOf(d))) {
      throw CosmosException(409, 'id $id exists', code: 'Conflict');
    }
    _put(_keyOf(d), d);
    return _out(_keyOf(d));
  }

  Map<String, dynamic> upsert(
    Map<String, Object?> doc, {
    Object? partitionKey,
  }) {
    final d = _copy(doc);
    _checkPartition(d, partitionKey);
    _put(_keyOf(d), d);
    return _out(_keyOf(d));
  }

  /// With [ifMatch], only when the stored doc still has that `_etag`: a 412
  /// otherwise, as Cosmos answers, and a 404 when the doc is gone.
  Map<String, dynamic> replace(
    String id,
    Map<String, Object?> doc, {
    Object? partitionKey,
    String? ifMatch,
  }) {
    final d = _copy(doc);
    _checkPartition(d, partitionKey);
    final key = _key(id, partitionKey);
    if (ifMatch != null) {
      if (!docs.containsKey(key)) {
        throw CosmosException(
          404,
          'Entity with the specified id does not exist in the system.',
          code: 'NotFound',
        );
      }
      if (_etags[key] != ifMatch) {
        throw CosmosException(
          412,
          'Operation cannot be performed because one of the specified '
          'precondition is not met.',
          code: 'PreconditionFailed',
        );
      }
    }
    _put(key, d);
    return _out(key);
  }

  void delete(String id, {Object? partitionKey}) =>
      _remove(_key(id, partitionKey));

  void executeBatch(List<BatchOperation> ops, {Object? partitionKey}) {
    for (final op in ops) {
      switch (op.operationType) {
        case 'Delete':
          _remove(_key(op.id!, partitionKey));
        case 'Create':
        case 'Upsert':
          final d = _copy(op.resourceBody!);
          _checkPartition(d, partitionKey);
          _put(_keyOf(d), d);
        case 'Replace':
          final d = _copy(op.resourceBody!);
          _checkPartition(d, partitionKey);
          _put(_key(op.id!, partitionKey), d);
      }
    }
  }

  List<Map<String, dynamic>> query(
    String sql,
    Map<String, Object?> params, {
    Object? partitionKey,
    bool crossPartition = false,
  }) {
    Iterable<Map<String, dynamic>> rows = docs.keys.map(_out);

    final field = partitionKeyField;
    if (field != null && !crossPartition && partitionKey != null) {
      rows = rows.where((d) => d[field] == partitionKey);
    }

    // Point lookup across partitions (`TranslationService.moveContent`).
    if (sql.contains('c.id = @id')) {
      rows = rows.where((d) => d['id'] == params['@id']);
    }

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
    // Cross-partition: one milestone, every student (#148).
    if (sql.contains('c.milestoneId = @milestoneId')) {
      rows = rows.where((d) => d['milestoneId'] == params['@milestoneId']);
    }
    // The teacher's signal events (CONDUCTOR_POLICY §8.2): records that
    // carry events, and of those the ones not yet acknowledged — what the
    // "needs attention" badge counts and the acknowledge action clears.
    if (sql.contains('ARRAY_LENGTH(c.signalEvents) > 0')) {
      rows = rows.where(
        (d) =>
            d['signalEvents'] is List && (d['signalEvents'] as List).isNotEmpty,
      );
    }
    if (sql.contains(
      '(NOT IS_DEFINED(c.acknowledgedAt) OR IS_NULL(c.acknowledgedAt))',
    )) {
      rows = rows.where((d) => d['acknowledgedAt'] == null);
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
  }) async => _store.read(id, partitionKey: partitionKey);

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) async => _store.query(
    sql,
    parameters,
    partitionKey: partitionKey,
    crossPartition: crossPartition,
  );

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async => _store.create(doc, partitionKey: partitionKey);

  @override
  Future<Map<String, dynamic>> upsert(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async => _store.upsert(doc, partitionKey: partitionKey);

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
    String? ifMatch,
  }) async {
    await _store.beforeReplace?.call(id, doc);
    return _store.replace(
      id,
      doc,
      partitionKey: partitionKey,
      ifMatch: ifMatch,
    );
  }

  @override
  Future<void> delete(String id, {required Object partitionKey}) async =>
      _store.delete(id, partitionKey: partitionKey);

  @override
  Future<void> executeBatch(
    List<BatchOperation> ops, {
    required Object partitionKey,
  }) async => _store.executeBatch(ops, partitionKey: partitionKey);
}

/// Whole-database fake: one [InMemoryCosmos] per container name, created on
/// first use. [install] makes it the process-wide `CosmosClient.instance`.
class InMemoryCosmosClient implements CosmosClient {
  InMemoryCosmosClient([Map<String, InMemoryCosmos> containers = const {}])
    : _containers = Map.of(containers);

  final Map<String, InMemoryCosmos> _containers;
  final Map<String, CosmosContainer> _routed = {};

  /// The containers whose ids are unique per partition rather than per
  /// container, with the doc field their partition key is read from.
  static const Map<String, String> _partitionedBy = {
    'translations': 'language',
  };

  /// The store behind [containerId], e.g. `cosmos['goals'].docs`.
  InMemoryCosmos operator [](String containerId) =>
      _containers.putIfAbsent(containerId, () {
        final field = _partitionedBy[containerId];
        return field == null
            ? InMemoryCosmos()
            : InMemoryCosmos.partitioned(field);
      });

  /// Serves [containerId] from [container] instead of its in-memory store —
  /// e.g. the real REST container of an account where it was never created
  /// (`UnprovisionedCosmos`, #170). `null` puts the in-memory store back,
  /// as creating the container would.
  void route(String containerId, CosmosContainer? container) {
    if (container == null) {
      _routed.remove(containerId);
    } else {
      _routed[containerId] = container;
    }
  }

  @override
  CosmosContainer container(String containerId) =>
      _routed[containerId] ?? this[containerId].container;

  /// Routes every `CosmosPaths.*()` handle through this fake.
  void install() => CosmosClient.overrideInstance(this);
}
