// Windows' Controlled folder access (#344), as a test can have it.
//
// The real thing is a security setting of the pc, and a test must not turn
// it on. What it does to an app it does not know is simple, though: in a
// protected folder (Documents) every write fails — creating, writing,
// renaming or deleting a file or a folder — and reading still works. This
// gives a folder that behaves that way, through `IOOverrides`: every
// `File` and `Directory` under it that the code under test makes is
// read-only, and so is everything its listing hands out.
//
// Some files can also be made unreadable ([unreadable], by name), for a
// copy that fails half way — a OneDrive file that is only in the cloud,
// say, on a pc that is offline.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Runs [body] with every write under [folder] refused, as Controlled
/// folder access refuses it. Files named in [unreadable] cannot be read
/// either. Returns what [body] returns.
Future<T> withControlledFolderAccess<T>(
  Directory folder,
  Future<T> Function() body, {
  Set<String> unreadable = const {},
}) => IOOverrides.runWithIOOverrides(
  body,
  _ControlledFolderAccess(p.normalize(folder.absolute.path), unreadable),
);

/// The error a refused write gets: "Access is denied".
FileSystemException _denied(String path) => FileSystemException(
  'Controlled folder access blocked the change',
  path,
  const OSError('Access is denied.', 5),
);

final class _ControlledFolderAccess extends IOOverrides {
  _ControlledFolderAccess(this.folder, this.unreadable);

  final String folder;
  final Set<String> unreadable;

  bool protects(String path) {
    final full = p.normalize(p.absolute(path));
    return p.equals(full, folder) || p.isWithin(folder, full);
  }

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return protects(path) ? _ReadOnlyFile(file, this) : file;
  }

  @override
  Directory createDirectory(String path) {
    final dir = super.createDirectory(path);
    return protects(path) ? _ReadOnlyDirectory(dir, this) : dir;
  }
}

/// A file in the protected folder: reads go through, everything else is
/// refused ([noSuchMethod]).
class _ReadOnlyFile implements File {
  _ReadOnlyFile(this._file, this._access);

  final File _file;
  final _ControlledFolderAccess _access;

  void _checkReadable() {
    if (_access.unreadable.contains(p.basename(_file.path))) {
      throw FileSystemException(
        'The file cannot be read',
        _file.path,
        const OSError('The cloud file provider is not running.', 362),
      );
    }
  }

  @override
  String get path => _file.path;

  @override
  Uri get uri => _file.uri;

  @override
  bool get isAbsolute => _file.isAbsolute;

  @override
  Future<bool> exists() => _file.exists();

  @override
  bool existsSync() => _file.existsSync();

  @override
  Future<FileStat> stat() => _file.stat();

  @override
  FileStat statSync() => _file.statSync();

  @override
  Future<int> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() async {
    _checkReadable();
    return _file.readAsBytes();
  }

  @override
  Uint8List readAsBytesSync() {
    _checkReadable();
    return _file.readAsBytesSync();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    _checkReadable();
    return _file.readAsString(encoding: encoding);
  }

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    _checkReadable();
    return _file.readAsStringSync(encoding: encoding);
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    _checkReadable();
    return _file.openRead(start, end);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw _denied(_file.path);
}

/// A folder in the protected folder: it can be listed, not changed.
class _ReadOnlyDirectory implements Directory {
  _ReadOnlyDirectory(this._dir, this._access);

  final Directory _dir;
  final _ControlledFolderAccess _access;

  FileSystemEntity _wrap(FileSystemEntity entity) => switch (entity) {
    File() => _ReadOnlyFile(entity, _access),
    Directory() => _ReadOnlyDirectory(entity, _access),
    _ => entity,
  };

  @override
  String get path => _dir.path;

  @override
  Uri get uri => _dir.uri;

  @override
  bool get isAbsolute => _dir.isAbsolute;

  @override
  Future<bool> exists() => _dir.exists();

  @override
  bool existsSync() => _dir.existsSync();

  @override
  Future<FileStat> stat() => _dir.stat();

  @override
  FileStat statSync() => _dir.statSync();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => _dir.list(recursive: recursive, followLinks: followLinks).map(_wrap);

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => _dir
      .listSync(recursive: recursive, followLinks: followLinks)
      .map(_wrap)
      .toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw _denied(_dir.path);
}
