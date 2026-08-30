import 'dart:io';

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

/// Local, per-device storage for the student's playground code (issue #19).
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
    await file.writeAsString(code, flush: true);
  }

  Future<void> delete(String name) async {
    final file = await _fileFor(name);
    if (await file.exists()) await file.delete();
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

final playgroundFileStoreProvider = Provider<PlaygroundFileStore>((ref) {
  return PlaygroundFileStore(
    rootDir: () async {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, 'AI Tutor Python', 'playground'));
    },
  );
});
