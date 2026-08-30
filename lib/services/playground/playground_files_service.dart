// Reads / writes the `playground_files` Cosmos container (#31): one doc per
// `(uid, file name)`, partition key `uid`, doc id `${uid}_${name}`.
//
// A deleted file is kept as a *tombstone* (`deleted: true`, empty `code`)
// rather than removed. Without it a delete on one machine would be undone by
// the next sync from another machine that still has the file — the file would
// simply come back, which is the classic "deletes don't stick" bug.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One saved playground file as it lives in the student's account.
class PlaygroundFileDoc {
  const PlaygroundFileDoc({
    required this.name,
    required this.code,
    required this.updatedAt,
    this.deleted = false,
  });

  /// A tombstone for [name], stamped [updatedAt].
  PlaygroundFileDoc.tombstone(this.name, this.updatedAt)
    : code = '',
      deleted = true;

  factory PlaygroundFileDoc.fromCosmos(Map<String, dynamic> doc) {
    return PlaygroundFileDoc(
      name: doc['name'] as String,
      code: (doc['code'] as String?) ?? '',
      updatedAt: DateTime.parse(doc['updatedAt'] as String).toUtc(),
      deleted: (doc['deleted'] as bool?) ?? false,
    );
  }

  final String name;
  final String code;

  /// When the file was last written, by whichever machine wrote it. Used as
  /// the sync stamp: the local index remembers the value it last agreed with,
  /// so a changed stamp means "someone else touched this".
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap(String uid) => {
    'id': CosmosDocId.playgroundFile(uid, name),
    'uid': uid,
    'name': name,
    'code': code,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };
}

class PlaygroundFilesService {
  PlaygroundFilesService({CosmosContainer? container, required this._getUid})
    : _containerOverride = container;

  final CosmosContainer? _containerOverride;
  final String? Function() _getUid;

  CosmosContainer get _container =>
      _containerOverride ?? CosmosPaths.playgroundFiles();

  String get _uid {
    final uid = _getUid();
    if (uid == null) throw StateError('No authenticated user.');
    return uid;
  }

  /// Every doc of the signed-in student, tombstones included — the sync pass
  /// needs the tombstones to know what to remove locally.
  ///
  /// A doc that fails to parse is skipped rather than failing the whole read:
  /// one bad row must not strand every other file.
  Future<List<PlaygroundFileDoc>> listAll() {
    final uid = _uid;
    return safeCosmos(() async {
      final docs = await _container.query(
        'SELECT * FROM c WHERE c.uid = @uid',
        parameters: {'@uid': uid},
        partitionKey: uid,
      );
      final files = <PlaygroundFileDoc>[];
      for (final doc in docs) {
        try {
          files.add(PlaygroundFileDoc.fromCosmos(doc));
        } catch (_) {
          continue;
        }
      }
      return files;
    });
  }

  Future<void> upsert(PlaygroundFileDoc file) async {
    final uid = _uid;
    await safeCosmos(
      () => _container.upsert(file.toMap(uid), partitionKey: uid),
    );
  }
}

final playgroundFilesServiceProvider = Provider<PlaygroundFilesService>((ref) {
  return PlaygroundFilesService(
    getUid: () => ref.read(authServiceProvider)?.oid,
  );
});
