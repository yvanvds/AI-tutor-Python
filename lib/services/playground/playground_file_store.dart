import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:flutter/foundation.dart';
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
  PlaygroundFileStore({required this._rootDir});

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

  /// Marker in a student's folder: their files were copied in from the old
  /// folder in Documents (#344), so that is never done again. Not a `.py`
  /// file either.
  static const String copiedFromDocumentsFile = '_copied_from_documents.json';

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

/// The app-data folder the playground keeps its files under (#344):
/// `getApplicationSupportDirectory()`, on Windows under `AppData\Roaming`,
/// where the school file is kept too. A provider so that tests and the
/// integration harness point it at a folder of their own.
final playgroundAppDataDirProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationSupportDirectory,
);

/// The Documents folder, where the playground kept its files before #344.
/// Only ever read, by the copy into the app data
/// ([copyPlaygroundFilesFromDocuments]); never written.
final playgroundDocumentsDirProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationDocumentsDirectory,
);

/// The folder that holds a folder per student (#31):
/// `<app data>/playground` in school mode, and in the stand-alone mode's own
/// folder (`<app data>/standalone/playground`, `AppMode.localDataDir`), so
/// the two modes never share local files.
///
/// Not the Documents folder (#344). Windows' Controlled folder access
/// protects Documents (often redirected to OneDrive) and lets only the apps
/// it knows write there; a new build of this app is not one of them, so a
/// save failed — and with it the sync, whose sidecar lives next to the
/// files. The app data is not protected.
Directory playgroundBaseDir(AppMode mode, Directory appData) =>
    Directory(p.join(mode.localDataDir(appData).path, 'playground'));

/// Where the playground kept its files before #344, for both modes:
/// `<Documents>/AI Tutor Python/playground`, a folder per student in it.
Directory documentsPlaygroundBaseDir(Directory documents) =>
    Directory(p.join(documents.path, 'AI Tutor Python', 'playground'));

/// Resolves the directory holding [uid]'s files: `<base>/<uid>`, created
/// when missing.
///
/// Classroom machines are shared and sync (#31) uploads whatever it finds
/// to the signed-in account, so files are kept per Entra object id (in
/// stand-alone mode: the local profile's uid) — otherwise the next student
/// to sign in would push the previous one's code into their own account.
///
/// With [documentsBase] (the folder of [documentsPlaygroundBaseDir]), the
/// files [uid] had there are copied in, once
/// ([copyPlaygroundFilesFromDocuments]).
///
/// The loose files of #19's flat layout (before v2.1.0+18, 31-08) are no
/// longer picked up: they were moved into the first student's folder by
/// every build since, and moving them now would mean writing in Documents.
Future<Directory> resolvePlaygroundDir(
  Directory base,
  String uid, {
  Directory? documentsBase,
}) async {
  final dir = Directory(p.join(base.path, uid));
  if (!await dir.exists()) await dir.create(recursive: true);
  if (documentsBase != null) {
    await copyPlaygroundFilesFromDocuments(
      from: Directory(p.join(documentsBase.path, uid)),
      to: dir,
    );
  }
  return dir;
}

/// Copies one student's files from their old folder in Documents ([from])
/// into their folder in the app data ([to]), once (#344): the first time
/// [to] is used, i.e. while it has no
/// [PlaygroundFileStore.copiedFromDocumentsFile] yet. That marker is then
/// written whatever the copy managed, so a file the student deletes later
/// is never copied back from the old folder.
///
/// Only reads [from]: copying rather than moving, because Windows'
/// Controlled folder access can refuse a delete or rename in Documents as
/// well as a write; reading is allowed. A file that is already in [to] is
/// left as it is.
///
/// Never throws for something in [from]. What cannot be read is left out,
/// and the next sync brings it from the account, as on a new pc. The sync
/// sidecar (`_sync.json`) is copied last and only when every `.py` file of
/// [from] is in [to]: it records which files this machine agreed with the
/// account on, and one it names that the copy left out would look deleted
/// here, so the sync would delete it from the account too. Without the
/// sidecar, the sync pulls what is missing.
Future<void> copyPlaygroundFilesFromDocuments({
  required Directory from,
  required Directory to,
}) async {
  final marker = File(
    p.join(to.path, PlaygroundFileStore.copiedFromDocumentsFile),
  );
  if (await marker.exists()) return;

  final copied = <String>[];
  final failed = <String>[];
  final code = <File>[];
  File? sidecar;
  var complete = true;
  try {
    if (await from.exists()) {
      await for (final entity in from.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name == PlaygroundFileStore.syncMetaFile) {
          sidecar = entity;
        } else if (name.toLowerCase().endsWith(PlaygroundFileStore.extension)) {
          code.add(entity);
        }
      }
    }
  } catch (e) {
    debugPrint('Playground: cannot read ${from.path}, nothing copied: $e');
    complete = false;
  }

  Future<void> copy(File source) async {
    final name = p.basename(source.path);
    try {
      final target = File(p.join(to.path, name));
      if (await target.exists()) return;
      // Through a temp name, so an interrupted copy never leaves a short
      // file under the real name; `list` skips the `.tmp`.
      final partial = File('${target.path}.tmp');
      await partial.writeAsBytes(await source.readAsBytes(), flush: true);
      await partial.rename(target.path);
      copied.add(name);
    } catch (e) {
      debugPrint('Playground: "$name" not copied from Documents: $e');
      failed.add(name);
      complete = false;
    }
  }

  for (final file in code) {
    await copy(file);
  }
  final index = sidecar;
  if (index != null) {
    if (complete) {
      await copy(index);
    } else {
      failed.add(PlaygroundFileStore.syncMetaFile);
    }
  }

  try {
    await marker.writeAsString(
      jsonEncode({
        'from': from.path,
        'at': DateTime.now().toUtc().toIso8601String(),
        'copied': copied,
        'notCopied': failed,
      }),
      flush: true,
    );
  } catch (e) {
    // The next start tries again; a file that is there by then is kept.
    debugPrint('Playground: copy from Documents not marked done: $e');
  }
}

final playgroundFileStoreProvider = Provider<PlaygroundFileStore>((ref) {
  final uid = ref.watch(authServiceProvider)?.oid;
  final mode = ref.watch(appModeProvider);
  final appData = ref.watch(playgroundAppDataDirProvider);
  final documents = ref.watch(playgroundDocumentsDirProvider);

  Future<Directory> resolve() async {
    final base = playgroundBaseDir(mode, await appData());
    if (uid == null) return base;
    Directory? documentsBase;
    try {
      documentsBase = documentsPlaygroundBaseDir(await documents());
    } catch (e) {
      debugPrint('Playground: no Documents folder, nothing to copy: $e');
    }
    return resolvePlaygroundDir(base, uid, documentsBase: documentsBase);
  }

  // Resolved once per student: the copy from Documents runs on the first
  // use, not again for every file operation. A failure is not kept.
  Future<Directory>? resolved;
  return PlaygroundFileStore(
    rootDir: () async {
      try {
        return await (resolved ??= resolve());
      } catch (_) {
        resolved = null;
        rethrow;
      }
    },
  );
});
