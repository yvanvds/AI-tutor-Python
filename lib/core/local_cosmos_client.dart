// Local storage for the stand-alone mode (#263, part of #261).
//
// The same interface as Cosmos (`CosmosClient` / `CosmosContainer`), so the
// services run unchanged; only the storage underneath differs. The school
// mode never builds one.
//
// On disk, one JSON file per document:
//
//   <root>/<container>/<partition>/<id>.json
//
// holding `{"partitionKey": ..., "doc": {...}}`. Folder and file names are
// the partition key and id made safe for Windows (lower case, digits, `_`
// and `-` as they are; everything else `%XX`; a long name shortened with a
// hash). The names are only a place: the file itself says what it holds.
//
// A write goes to `<id>.json.tmp` first and is then renamed over the old
// file, so a crash mid-write leaves the old document or the new one, never a
// broken file. An exercise writes a handful of small files and never one big
// file again. Many docs at once (the content bundle at start, #346) go
// through [LocalCosmosClient.upsertAll]: the same files, written
// asynchronously, several at a time.
//
// [LocalCosmosClient.open] reads everything once; after that every read and
// query is served from memory and every write goes to memory and disk.
//
// Behaviour the app relies on, as Cosmos has it:
//
//   - `create` on an existing id: 409;
//   - `replace` on a missing id: 404; with `ifMatch` on a changed doc: 412;
//   - `executeBatch` lands whole or not at all (in memory and in what it
//     hands back; a crash in the middle of writing its files can leave part
//     of it on disk);
//   - a doc with a `ttl` (seconds, `turn_content`) expires that long after its
//     last write: it is no longer handed out, and it is deleted from disk
//     when the storage is next opened;
//   - every container exists: there is no "container missing" (#170);
//   - a write whose partition key is not the doc's own: 400;
//   - a query the interpreter does not understand: 400 ([CosmosQuery]).

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_query.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The doc field each container is partitioned on, as in the school's
/// database (see `CosmosPaths`). A container that is not listed accepts any
/// partition key.
const Map<String, String> kCosmosPartitionKeyFields = {
  'accounts': 'uid',
  'progress': 'uid',
  'progress_history': 'uid',
  'status_reports': 'uid',
  'goals': 'type',
  'instructions': 'type',
  'config': 'type',
  'content': 'type',
  'modules': 'type',
  'lo_beliefs': 'uid',
  'turn_history': 'uid',
  'playground_files': 'uid',
  'milestones': 'type',
  'grade_proposals': 'uid',
  'reports': 'uid',
  'questions': 'subgoalId',
  'translations': 'language',
  'turn_content': 'uid',
  'podium': 'type',
};

/// Where the stand-alone mode keeps its data:
/// `<app support>/standalone/data` (`AppMode.localDataDir`). Deleting that
/// folder while the app is closed starts the stand-alone mode afresh; the
/// school mode never looks there.
Future<Directory> standaloneDataDir(
  AppMode mode, {
  Future<Directory> Function() appSupportDir = getApplicationSupportDirectory,
}) async =>
    Directory(p.join(mode.localDataDir(await appSupportDir()).path, 'data'));

/// Stand-alone storage: Cosmos' interface over JSON files on the pc.
class LocalCosmosClient implements CosmosClient {
  LocalCosmosClient._(this.root, this._clock);

  /// Reads every document under [root] (created when missing) and returns
  /// a client that serves them. Expired docs and files left behind by an
  /// interrupted write are removed on the way.
  ///
  /// Reads synchronously: it runs once, at start, before the app's first
  /// screen (in `main()`, behind the loading page, #346).
  factory LocalCosmosClient.open(
    Directory root, {
    DateTime Function() clock = DateTime.now,
  }) {
    final client = LocalCosmosClient._(root, clock);
    client._load();
    return client;
  }

  /// The folder that holds every container.
  final Directory root;
  final DateTime Function() _clock;

  final Map<String, _LocalContainer> _containers = {};

  @override
  CosmosContainer container(String containerId) => _containers.putIfAbsent(
    containerId,
    () => _LocalContainer(this, containerId),
  );

  int _etagCounter = 0;

  String _newEtag() =>
      '"${_clock().microsecondsSinceEpoch.toRadixString(16)}-'
      '${(++_etagCounter).toRadixString(16)}"';

  void _load() {
    root.createSync(recursive: true);
    for (final dir in root.listSync().whereType<Directory>()) {
      final name = p.basename(dir.path);
      final container = _containerFor(name);
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.tmp')) {
          _tryDelete(entity);
          continue;
        }
        if (!entity.path.endsWith('.json')) continue;
        container._loadFile(entity);
      }
    }
  }

  /// [container], typed. Each folder under [root] is a container's name.
  _LocalContainer _containerFor(String containerId) =>
      container(containerId) as _LocalContainer;

  /// Upserts [docs] into [containerId] as [CosmosContainer.upsert] does —
  /// each doc to its own file, through `<id>.json.tmp`, flushed — but with
  /// asynchronous writes, [parallel] files at a time. For loading many docs
  /// at once (the content bundle at start, #346): the UI isolate is not held
  /// up while the files are written, and the disk is kept busy.
  ///
  /// Every doc is checked before anything is written; of two docs with the
  /// same id and partition key, the last one counts. [onWritten] is called
  /// after each doc has landed on disk and in memory. A failed write throws
  /// (500) once the writes under way are done, and can leave part of [docs]
  /// written, as a crash in [CosmosContainer.executeBatch] can. Nothing else
  /// may write to the container meanwhile.
  Future<void> upsertAll(
    String containerId,
    List<({Map<String, Object?> doc, Object partitionKey})> docs, {
    int parallel = 16,
    void Function()? onWritten,
  }) =>
      _containerFor(containerId)
          ._upsertAll(docs, parallel: parallel, onWritten: onWritten);
}

/// A doc [LocalCosmosClient.upsertAll] is about to write, and where.
typedef _PlannedWrite = ({
  File file,
  Object partitionKey,
  Map<String, Object?> doc,
});

class _Entry {
  _Entry(this.partitionKey, this.doc)
    : partitionKeyJson = jsonEncode(partitionKey);
  final Object? partitionKey;
  final String partitionKeyJson;

  /// The doc as stored, with `_etag` and `_ts`.
  final Map<String, dynamic> doc;
}

class _LocalContainer implements CosmosContainer {
  _LocalContainer(this._client, this._name);

  final LocalCosmosClient _client;
  final String _name;

  /// Keyed on [_key]: ids are unique per partition, as in Cosmos.
  final Map<String, _Entry> _docs = {};

  Directory get _dir => Directory(p.join(_client.root.path, _name));

  static String _key(Object? partitionKey, String id) =>
      '${jsonEncode(partitionKey)}\u0000$id';

  File _fileFor(Object? partitionKey, String id) => File(
    p.join(
      _dir.path,
      _safeName(
        partitionKey is String ? partitionKey : jsonEncode(partitionKey),
      ),
      '${_safeName(id)}.json',
    ),
  );

  // --- loading ---------------------------------------------------------------

  void _loadFile(File file) {
    final Map<String, dynamic> entry;
    try {
      entry = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on Object catch (e) {
      // Atomic writes make this unlikely; leave the file for a human rather
      // than delete what may be someone's work.
      debugPrint('LocalCosmosClient: skipped unreadable ${file.path}: $e');
      return;
    }
    final doc = entry['doc'];
    if (doc is! Map<String, dynamic> || doc['id'] is! String) {
      debugPrint('LocalCosmosClient: skipped ${file.path}: no doc');
      return;
    }
    final pk = entry['partitionKey'];
    if (_expired(doc)) {
      _tryDelete(file);
      return;
    }
    _docs[_key(pk, doc['id'] as String)] = _Entry(pk, doc);
  }

  // --- semantics -------------------------------------------------------------

  bool _expired(Map<String, dynamic> doc) {
    final ttl = doc['ttl'];
    final ts = doc['_ts'];
    if (ttl is! num || ttl <= 0 || ts is! num) return false;
    final nowSeconds = _client._clock().millisecondsSinceEpoch / 1000;
    return nowSeconds >= ts + ttl;
  }

  _Entry? _live(String key) {
    final e = _docs[key];
    if (e == null || _expired(e.doc)) return null;
    return e;
  }

  void _checkPartition(Map<String, Object?> doc, Object? partitionKey) {
    final field = kCosmosPartitionKeyFields[_name];
    if (field == null || doc[field] == partitionKey) return;
    throw CosmosException(
      400,
      'PartitionKey extracted from document (${doc[field]}) does not match '
      'the one specified in the header ($partitionKey)',
      code: 'BadRequest',
    );
  }

  static String _idOf(Map<String, Object?> doc) {
    final id = doc['id'];
    if (id is String && id.isNotEmpty) return id;
    throw CosmosException(
      400,
      'The input content is invalid because the required property, id, '
      'is missing.',
      code: 'BadRequest',
    );
  }

  static CosmosException _notFound() => CosmosException(
    404,
    'Entity with the specified id does not exist in the system.',
    code: 'NotFound',
  );

  static CosmosException _conflict(String id) => CosmosException(
    409,
    'Entity with the specified id already exists in the system ($id).',
    code: 'Conflict',
  );

  /// A stored copy of [doc] with fresh system fields.
  Map<String, dynamic> _stamp(Map<String, Object?> doc) {
    final d = _copy(doc)
      ..remove('_etag')
      ..remove('_ts');
    d['_etag'] = _client._newEtag();
    d['_ts'] = _client._clock().millisecondsSinceEpoch ~/ 1000;
    return d;
  }

  static Map<String, dynamic> _copy(Map<String, Object?> d) =>
      jsonDecode(jsonEncode(d)) as Map<String, dynamic>;

  // --- disk ------------------------------------------------------------------

  void _writeFile(Object? partitionKey, Map<String, dynamic> doc) {
    final file = _fileFor(partitionKey, doc['id'] as String);
    final tmp = File('${file.path}.tmp');
    try {
      file.parent.createSync(recursive: true);
      tmp.writeAsStringSync(
        jsonEncode({'partitionKey': partitionKey, 'doc': doc}),
        flush: true,
      );
      tmp.renameSync(file.path);
    } on FileSystemException catch (e) {
      _tryDelete(tmp);
      throw CosmosException(
        500,
        'Could not write ${file.path}: ${e.message}',
        code: 'LocalWriteFailed',
      );
    }
  }

  /// [_writeFile], without blocking the isolate.
  Future<void> _writeFileAsync(
    File file,
    Object? partitionKey,
    Map<String, dynamic> doc,
  ) async {
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsString(
        jsonEncode({'partitionKey': partitionKey, 'doc': doc}),
        flush: true,
      );
      await tmp.rename(file.path);
    } on FileSystemException catch (e) {
      _tryDelete(tmp);
      throw CosmosException(
        500,
        'Could not write ${file.path}: ${e.message}',
        code: 'LocalWriteFailed',
      );
    }
  }

  void _deleteFile(Object? partitionKey, String id) {
    final file = _fileFor(partitionKey, id);
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException catch (e) {
      throw CosmosException(
        500,
        'Could not delete ${file.path}: ${e.message}',
        code: 'LocalWriteFailed',
      );
    }
  }

  /// Puts [doc] in memory and on disk; disk first, so a failed write leaves
  /// memory as it was.
  Map<String, dynamic> _store(
    String key,
    Object? partitionKey,
    Map<String, Object?> doc,
  ) {
    final stamped = _stamp(doc);
    _writeFile(partitionKey, stamped);
    _docs[key] = _Entry(partitionKey, stamped);
    return _copy(stamped);
  }

  /// See [LocalCosmosClient.upsertAll].
  Future<void> _upsertAll(
    List<({Map<String, Object?> doc, Object partitionKey})> docs, {
    required int parallel,
    void Function()? onWritten,
  }) async {
    final planned = <String, _PlannedWrite>{};
    for (final (:doc, :partitionKey) in docs) {
      _checkPartition(doc, partitionKey);
      final id = _idOf(doc);
      planned[_key(partitionKey, id)] = (
        file: _fileFor(partitionKey, id),
        partitionKey: partitionKey,
        doc: doc,
      );
    }
    // The folders first, one at a time: two writers making the same folder
    // at once can trip over each other.
    for (final folder in {for (final w in planned.values) w.file.parent.path}) {
      try {
        await Directory(folder).create(recursive: true);
      } on FileSystemException catch (e) {
        throw CosmosException(
          500,
          'Could not make $folder: ${e.message}',
          code: 'LocalWriteFailed',
        );
      }
    }

    final queue = planned.entries.iterator;
    var failed = false;
    Future<void> writer() async {
      while (!failed && queue.moveNext()) {
        final MapEntry(:key, value: w) = queue.current;
        final stamped = _stamp(w.doc);
        try {
          await _writeFileAsync(w.file, w.partitionKey, stamped);
        } on Object {
          failed = true;
          rethrow;
        }
        _docs[key] = _Entry(w.partitionKey, stamped);
        onWritten?.call();
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) writer()]);
  }

  // --- CosmosContainer -------------------------------------------------------

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) async {
    final e = _live(_key(partitionKey, id));
    return e == null ? null : _copy(e.doc);
  }

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) async {
    final parsed = CosmosQuery.parse(sql);
    final pkJson = !crossPartition && partitionKey != null
        ? jsonEncode(partitionKey)
        : null;
    final rows = <Map<String, dynamic>>[
      for (final e in _docs.values)
        if ((pkJson == null || e.partitionKeyJson == pkJson) &&
            !_expired(e.doc))
          e.doc,
    ];
    return parsed.execute(rows, parameters);
  }

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    _checkPartition(doc, partitionKey);
    final id = _idOf(doc);
    final key = _key(partitionKey, id);
    if (_live(key) != null) throw _conflict(id);
    return _store(key, partitionKey, doc);
  }

  @override
  Future<Map<String, dynamic>> upsert(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    _checkPartition(doc, partitionKey);
    final id = _idOf(doc);
    return _store(_key(partitionKey, id), partitionKey, doc);
  }

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
    String? ifMatch,
  }) async {
    _checkPartition(doc, partitionKey);
    if (_idOf(doc) != id) {
      throw CosmosException(
        400,
        'The id in the document (${doc['id']}) is not the id replaced ($id).',
        code: 'BadRequest',
      );
    }
    final key = _key(partitionKey, id);
    final existing = _live(key);
    if (existing == null) throw _notFound();
    if (ifMatch != null && existing.doc['_etag'] != ifMatch) {
      throw CosmosException(
        412,
        'Operation cannot be performed because one of the specified '
        'precondition is not met.',
        code: 'PreconditionFailed',
      );
    }
    return _store(key, partitionKey, doc);
  }

  @override
  Future<void> delete(String id, {required Object partitionKey}) async {
    final key = _key(partitionKey, id);
    if (!_docs.containsKey(key)) return;
    _deleteFile(partitionKey, id);
    _docs.remove(key);
  }

  @override
  Future<void> executeBatch(
    List<BatchOperation> ops, {
    required Object partitionKey,
  }) async {
    if (ops.isEmpty) return;

    // Check every op against the container as the ops before it leave it;
    // nothing is written until all of them pass.
    final present = <String, bool>{};
    bool exists(String key) => present[key] ?? _live(key) != null;
    final planned = <({String key, String id, Map<String, Object?>? doc})>[];
    for (final op in ops) {
      switch (op.operationType) {
        case 'Create':
        case 'Upsert':
        case 'Replace':
          final doc = op.resourceBody!;
          _checkPartition(doc, partitionKey);
          final id = op.operationType == 'Replace' ? op.id! : _idOf(doc);
          if (op.operationType == 'Replace' && _idOf(doc) != id) {
            throw CosmosException(
              400,
              'Batch replace of $id carries id ${doc['id']}.',
              code: 'BadRequest',
            );
          }
          final key = _key(partitionKey, id);
          if (op.operationType == 'Create' && exists(key)) {
            throw _conflict(id);
          }
          if (op.operationType == 'Replace' && !exists(key)) {
            throw _notFound();
          }
          present[key] = true;
          planned.add((key: key, id: id, doc: doc));
        case 'Delete':
          final key = _key(partitionKey, op.id!);
          if (!exists(key)) throw _notFound();
          present[key] = false;
          planned.add((key: key, id: op.id!, doc: null));
        default:
          throw CosmosException(
            400,
            'Unknown batch operation ${op.operationType}.',
            code: 'BadRequest',
          );
      }
    }

    for (final op in planned) {
      final doc = op.doc;
      if (doc == null) {
        _deleteFile(partitionKey, op.id);
        _docs.remove(op.key);
      } else {
        _store(op.key, partitionKey, doc);
      }
    }
  }
}

void _tryDelete(File f) {
  try {
    if (f.existsSync()) f.deleteSync();
  } on FileSystemException {
    // Best effort; the next start tries again.
  }
}

/// [raw] as a file or folder name that is safe on Windows and never
/// collides with another raw value, even on a case-insensitive disk.
String _safeName(String raw) {
  final buf = StringBuffer();
  for (final byte in utf8.encode(raw)) {
    final ch = String.fromCharCode(byte);
    final keep =
        (byte >= 0x61 && byte <= 0x7a) || // a-z
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        ch == '_' ||
        ch == '-';
    buf.write(
      keep ? ch : '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
    );
  }
  var name = buf.toString();
  if (name.isEmpty) name = '%';
  // CON, NUL, COM1, ... are device names on Windows, with any extension.
  if (RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])$').hasMatch(name)) {
    name =
        '%${name.codeUnitAt(0).toRadixString(16).toUpperCase()}'
        '${name.substring(1)}';
  }
  // Keep paths well under Windows' 260 characters.
  if (name.length > 80) {
    final hash = sha256.convert(utf8.encode(raw)).toString().substring(0, 24);
    name = '${name.substring(0, 40)}~$hash';
  }
  return name;
}

/// Exposed for tests: the on-disk name of a partition key or id.
@visibleForTesting
String localStorageSafeName(String raw) => _safeName(raw);
