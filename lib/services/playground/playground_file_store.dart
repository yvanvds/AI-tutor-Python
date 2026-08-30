import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown by [PlaygroundFileStore] when a file name is empty, too long, or
/// contains characters that are not safe as a plain file name.
class InvalidPlaygroundFileName implements Exception {
  const InvalidPlaygroundFileName(this.name);
  final String name;

  @override
  String toString() => 'InvalidPlaygroundFileName($name)';
}

/// Thrown by [PlaygroundFileStore.save] when the code exceeds
/// [PlaygroundFileStore.maxFileBytes].
class PlaygroundFileTooLarge implements Exception {
  const PlaygroundFileTooLarge(this.name, this.bytes);
  final String name;
  final int bytes;

  @override
  String toString() => 'PlaygroundFileTooLarge($name, $bytes bytes)';
}

/// Thrown by [PlaygroundFileStore.save] when adding a *new* file would push
/// the student past [PlaygroundFileStore.maxFiles].
class PlaygroundStoreFull implements Exception {
  const PlaygroundStoreFull(this.limit);
  final int limit;

  @override
  String toString() => 'PlaygroundStoreFull($limit)';
}

/// On-disk storage for one student's playground code (issue #19), mirrored to
/// their account by `PlaygroundSyncService` (#31).
///
/// Files live as `<name>.py` in a single flat directory. Names are restricted
/// to letters, digits, spaces, `-` and `_` so a name can never escape the
/// directory or collide with reserved path syntax. The root directory is
/// resolved lazily through [rootDir] so tests can point the store at a temp
/// directory.
class PlaygroundFileStore {
  PlaygroundFileStore({required Future<Directory> Function() rootDir})
    : _rootDir = rootDir;

  final Future<Directory> Function() _rootDir;

  static const int maxNameLength = 60;
  static const String extension = '.py';

  /// Cap per file. Every synced file is one Cosmos doc (#31) and a doc tops
  /// out at 2 MB; 64 KB is far beyond any student script and keeps the RU
  /// cost of a full sync predictable.
  static const int maxFileBytes = 64 * 1024;

  /// Cap on how many files one student keeps. Bounds a sync to one query
  /// plus at most this many upserts.
  static const int maxFiles = 200;

  /// Sidecar written by the sync layer (#31). Not a `.py` file, so [list]
  /// skips it.
  static const String syncMetaFile = '_sync.json';

  static final RegExp _validName = RegExp(r'^[A-Za-z0-9_\- ]+$');

  /// Normalises what the student typed into a storable name: trims
  /// whitespace and drops a trailing `.py`. Returns null when the result is
  /// not a valid name.
  static String? normalizeName(String raw) {
    var name = raw.trim();
    if (name.toLowerCase().endsWith(extension)) {
      name = name.substring(0, name.length - extension.length).trimRight();
    }
    if (name.isEmpty || name.length > maxNameLength) return null;
    if (!_validName.hasMatch(name)) return null;
    return name;
  }

  Future<Directory> _root() async {
    final dir = await _rootDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileFor(String rawName) async {
    final name = normalizeName(rawName);
    if (name == null) throw InvalidPlaygroundFileName(rawName);
    final dir = await _root();
    return File(p.join(dir.path, '$name$extension'));
  }

  /// Saved file names (without extension), sorted case-insensitively.
  Future<List<String>> list() async {
    final dir = await _root();
    final names = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final base = p.basename(entity.path);
      if (!base.toLowerCase().endsWith(extension)) continue;
      final name = base.substring(0, base.length - extension.length);
      if (normalizeName(name) == name) names.add(name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<bool> exists(String name) async => (await _fileFor(name)).exists();

  Future<String> load(String name) async =>
      (await _fileFor(name)).readAsString();

  Future<void> save(String name, String code) async {
    final file = await _fileFor(name);
    final bytes = utf8.encode(code).length;
    if (bytes > maxFileBytes) throw PlaygroundFileTooLarge(name, bytes);
    if (!await file.exists() && (await list()).length >= maxFiles) {
      throw PlaygroundStoreFull(maxFiles);
    }
    await file.writeAsString(code, flush: true);
  }

  Future<void> delete(String name) async {
    final file = await _fileFor(name);
    if (await file.exists()) await file.delete();
  }

  /// Reads the sync sidecar ([syncMetaFile]), or null when it was never
  /// written. Owned by `PlaygroundSyncService`; the path lives here so only
  /// this class knows where the student's directory is.
  Future<String?> readSyncMeta() async {
    final file = File(p.join((await _root()).path, syncMetaFile));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> writeSyncMeta(String contents) async {
    final file = File(p.join((await _root()).path, syncMetaFile));
    await file.writeAsString(contents, flush: true);
  }
}

/// The file the playground buffer was last saved to or loaded from, with the
/// text as it was persisted — used to decide whether the buffer is dirty
/// before replacing it. Null when the buffer has never been saved or loaded.
class PlaygroundFile {
  const PlaygroundFile({required this.name, required this.content});
  final String name;
  final String content;
}

final playgroundFileProvider = StateProvider<PlaygroundFile?>((_) => null);

/// Resolves the directory holding [uid]'s files: `<base>/<uid>`.
///
/// #19 kept every file loose in `<base>`, which was fine while nothing ever
/// left the machine. Sync (#31) uploads whatever it finds to the signed-in
/// account and classroom machines are shared, so files are namespaced per
/// Entra object id — otherwise the next student to sign in would push the
/// previous one's code into their own account.
///
/// Loose `.py` files from the old layout are *moved* into the folder of the
/// first student to sign in after the upgrade. They were written by whoever
/// last used this machine and #19 assumed one student per machine, so that is
/// the only attribution available; moving (rather than copying) means the
/// second student to sign in does not inherit them.
Future<Directory> resolvePlaygroundDir(Directory base, String uid) async {
  final dir = Directory(p.join(base.path, uid));
  if (!await dir.exists()) await dir.create(recursive: true);
  if (!await base.exists()) return dir;

  final legacy = <File>[];
  await for (final entity in base.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name.toLowerCase().endsWith(PlaygroundFileStore.extension) ||
        name == PlaygroundFileStore.syncMetaFile) {
      legacy.add(entity);
    }
  }
  for (final file in legacy) {
    final target = p.join(dir.path, p.basename(file.path));
    if (await File(target).exists()) continue;
    await file.rename(target);
  }
  return dir;
}

final playgroundFileStoreProvider = Provider<PlaygroundFileStore>((ref) {
  final uid = ref.watch(authServiceProvider)?.oid;
  return PlaygroundFileStore(
    rootDir: () async {
      final docs = await getApplicationDocumentsDirectory();
      final base = Directory(
        p.join(docs.path, 'AI Tutor Python', 'playground'),
      );
      if (uid == null) return base;
      return resolvePlaygroundDir(base, uid);
    },
  );
});
