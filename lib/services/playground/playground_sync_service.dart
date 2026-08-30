// Two-way sync between the student's local playground files (#19) and the
// `playground_files` container in their account (#31), so saved code follows
// them between classroom machines.
//
// Local-first, on purpose. The playground is the one part of the app that
// works with no network, and it stays that way: every read and write still
// goes to disk, and the account is a mirror that is reconciled when the
// student opens the file browser (and pushed to after a save or a delete).
// Every remote step is best-effort — a failure leaves the local files
// untouched and the next sync picks up where this one stopped.
//
// Conflict handling. Local mtimes are useless here: two classroom machines
// need not agree on the clock, and "newest wins" silently throws away a
// student's work. Instead each machine keeps a sidecar index
// (`_sync.json`, written through `PlaygroundFileStore.writeSyncMeta`) that
// remembers, per file, the content hash and the remote `updatedAt` it last
// agreed with. That turns "who is newer" into two independent yes/no
// questions — did this machine change the file since the last sync, did the
// account change it — and only when *both* say yes and the contents differ is
// there a real conflict. Then nothing is discarded: the account's version
// becomes `<name>` and this machine's version is kept (and uploaded) as
// `<name> conflict`.
//
// Losing the sidecar (a wiped profile, a corrupt file) is safe: every file
// then looks locally changed, so the pass uploads what it has and makes
// conflict copies where the account disagrees. Files are duplicated, never
// dropped.

import 'dart:convert';

import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What one [PlaygroundSyncService.sync] pass did.
class PlaygroundSyncResult {
  const PlaygroundSyncResult({
    this.pulled = 0,
    this.pushed = 0,
    this.removed = 0,
    this.conflicts = const [],
  });

  /// Files written to disk from the account.
  final int pulled;

  /// Files (and tombstones) written to the account from this machine.
  final int pushed;

  /// Files deleted locally because the account says they are gone.
  final int removed;

  /// Names of the conflict copies this pass created, e.g. `loops conflict`.
  final List<String> conflicts;

  static const PlaygroundSyncResult empty = PlaygroundSyncResult();
}

/// One line of the sidecar index: the state this machine last agreed with.
class _Agreed {
  const _Agreed({required this.remoteAt, required this.hash});

  /// The `updatedAt` of the account doc at that point, or `''` when the file
  /// did not exist in the account.
  final String remoteAt;

  /// Content hash at that point, or null when the file did not exist here.
  final String? hash;
}

class PlaygroundSyncService {
  PlaygroundSyncService({
    required PlaygroundFileStore store,
    required PlaygroundFilesService remote,
    required String? Function() getUid,
  }) : _store = store,
       _remote = remote,
       _getUid = getUid;

  final PlaygroundFileStore _store;
  final PlaygroundFilesService _remote;
  final String? Function() _getUid;

  static const int _indexVersion = 1;
  static const String _conflictSuffix = 'conflict';

  /// Reconciles disk and account. Never throws: the playground has to keep
  /// working offline, so a remote failure degrades to "local only".
  Future<PlaygroundSyncResult> sync() async {
    if (_getUid() == null) return PlaygroundSyncResult.empty;

    final List<PlaygroundFileDoc> docs;
    try {
      docs = await _remote.listAll();
    } catch (e) {
      debugPrint('PlaygroundSync: account unreachable, staying local: $e');
      return PlaygroundSyncResult.empty;
    }

    try {
      return await _reconcile(docs);
    } catch (e) {
      debugPrint('PlaygroundSync: sync aborted: $e');
      return PlaygroundSyncResult.empty;
    }
  }

  Future<PlaygroundSyncResult> _reconcile(List<PlaygroundFileDoc> docs) async {
    final remote = <String, PlaygroundFileDoc>{
      for (final doc in docs) doc.name: doc,
    };
    final local = (await _store.list()).toSet();
    final agreed = await _readIndex();
    final next = Map<String, _Agreed>.from(agreed);

    var pulled = 0;
    var pushed = 0;
    var removed = 0;
    final conflicts = <String>[];

    final names = <String>{...remote.keys, ...local, ...agreed.keys}.toList()
      ..sort();

    for (final name in names) {
      final doc = remote[name];
      final was = agreed[name];
      final remoteAt = doc?.updatedAt.toUtc().toIso8601String() ?? '';
      final remoteHash = doc == null || doc.deleted ? null : _hash(doc.code);

      try {
        final code = local.contains(name) ? await _store.load(name) : null;
        final hash = code == null ? null : _hash(code);

        // Both sides already hold the same content (or nothing at all): no
        // transfer, just record the stamp so the next pass sees agreement.
        if (hash == remoteHash) {
          if (doc == null) {
            next.remove(name);
          } else {
            next[name] = _Agreed(remoteAt: remoteAt, hash: hash);
          }
          continue;
        }

        final localChanged = hash != was?.hash;
        final remoteChanged = remoteAt != (was?.remoteAt ?? '');

        if (localChanged && remoteChanged) {
          if (code == null) {
            // Deleted here, edited there. The edit is the newer intent and
            // the only copy of that work, so it wins.
            await _store.save(name, doc!.code);
            next[name] = _Agreed(remoteAt: remoteAt, hash: remoteHash);
            pulled++;
          } else if (doc == null || doc.deleted) {
            // Deleted there, edited here — keep the work, undo the delete.
            next[name] = await _push(name, code, hash!);
            pushed++;
          } else {
            // The real conflict: different content on both sides. Keep both.
            final copy = _conflictName(
              name,
              taken: {...local, ...remote.keys, ...next.keys},
            );
            await _store.save(copy, code);
            next[copy] = await _push(copy, code, hash!);
            await _store.save(name, doc.code);
            next[name] = _Agreed(remoteAt: remoteAt, hash: remoteHash);
            conflicts.add(copy);
            pulled++;
            pushed++;
          }
          continue;
        }

        if (localChanged) {
          if (code != null) {
            next[name] = await _push(name, code, hash!);
            pushed++;
          } else if (doc != null && !doc.deleted) {
            // Deleted here: leave a tombstone so the other machines drop it.
            next[name] = await _pushTombstone(name);
            pushed++;
          } else {
            next.remove(name);
          }
          continue;
        }

        // Only the account changed.
        if (doc == null) {
          // The doc was removed outright (an account wipe, not a delete in
          // the app). Put this machine's copy back rather than lose it.
          next[name] = await _push(name, code!, hash!);
          pushed++;
        } else if (doc.deleted) {
          if (code != null) {
            await _store.delete(name);
            removed++;
          }
          next[name] = _Agreed(remoteAt: remoteAt, hash: null);
        } else {
          await _store.save(name, doc.code);
          next[name] = _Agreed(remoteAt: remoteAt, hash: remoteHash);
          pulled++;
        }
      } catch (e) {
        // One unreadable or oversized file must not strand the rest; the
        // index keeps its previous line so the next pass retries this file.
        debugPrint('PlaygroundSync: skipped "$name": $e');
      }
    }

    await _writeIndex(next);
    return PlaygroundSyncResult(
      pulled: pulled,
      pushed: pushed,
      removed: removed,
      conflicts: conflicts,
    );
  }

  /// Mirrors a just-saved file to the account. Best-effort: a failure leaves
  /// the file marked as locally changed, so the next [sync] uploads it.
  Future<void> push(String name, String code) async {
    if (_getUid() == null) return;
    try {
      final entry = await _push(name, code, _hash(code));
      final index = await _readIndex();
      await _writeIndex({...index, name: entry});
    } catch (e) {
      debugPrint('PlaygroundSync: push of "$name" deferred: $e');
    }
  }

  /// Mirrors a just-deleted file to the account as a tombstone.
  Future<void> pushDelete(String name) async {
    if (_getUid() == null) return;
    try {
      final entry = await _pushTombstone(name);
      final index = await _readIndex();
      await _writeIndex({...index, name: entry});
    } catch (e) {
      debugPrint('PlaygroundSync: delete of "$name" deferred: $e');
    }
  }

  Future<_Agreed> _push(String name, String code, String hash) async {
    final now = DateTime.now().toUtc();
    await _remote.upsert(
      PlaygroundFileDoc(name: name, code: code, updatedAt: now),
    );
    return _Agreed(remoteAt: now.toIso8601String(), hash: hash);
  }

  Future<_Agreed> _pushTombstone(String name) async {
    final now = DateTime.now().toUtc();
    await _remote.upsert(PlaygroundFileDoc.tombstone(name, now));
    return _Agreed(remoteAt: now.toIso8601String(), hash: null);
  }

  /// `<name> conflict`, or `<name> conflict 2`, 3, … when that is taken.
  /// The base is trimmed so the result still fits [maxNameLength].
  static String _conflictName(String name, {required Set<String> taken}) {
    const room = _conflictSuffix.length + 5; // ' conflict' + ' 999'
    final limit = PlaygroundFileStore.maxNameLength - room;
    var base = name.length > limit ? name.substring(0, limit) : name;
    base = base.trimRight();
    var candidate = '$base $_conflictSuffix';
    var n = 2;
    while (taken.contains(candidate)) {
      if (n > 999) throw StateError('no free conflict name for "$name"');
      candidate = '$base $_conflictSuffix $n';
      n++;
    }
    return candidate;
  }

  static String _hash(String code) =>
      sha1.convert(utf8.encode(code)).toString();

  Future<Map<String, _Agreed>> _readIndex() async {
    try {
      final raw = await _store.readSyncMeta();
      if (raw == null) return {};
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != _indexVersion) return {};
      final files = (json['files'] as Map<String, dynamic>?) ?? {};
      return files.map((name, value) {
        final line = value as Map<String, dynamic>;
        return MapEntry(
          name,
          _Agreed(
            remoteAt: (line['remoteAt'] as String?) ?? '',
            hash: line['hash'] as String?,
          ),
        );
      });
    } catch (e) {
      // Unreadable index: treat everything as locally changed. Safe — the
      // pass then uploads and, where the account disagrees, duplicates.
      debugPrint('PlaygroundSync: sync index unreadable, rebuilding: $e');
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, _Agreed> index) async {
    await _store.writeSyncMeta(
      jsonEncode({
        'version': _indexVersion,
        'files': {
          for (final entry in index.entries)
            entry.key: {
              'remoteAt': entry.value.remoteAt,
              'hash': entry.value.hash,
            },
        },
      }),
    );
  }
}

final playgroundSyncServiceProvider = Provider<PlaygroundSyncService>((ref) {
  return PlaygroundSyncService(
    store: ref.watch(playgroundFileStoreProvider),
    remote: ref.watch(playgroundFilesServiceProvider),
    getUid: () => ref.read(authServiceProvider)?.oid,
  );
});
