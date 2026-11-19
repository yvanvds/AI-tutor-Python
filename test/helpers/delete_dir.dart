import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// How long [deleteDirRetrying] keeps trying. Far above a file that is
/// still closing — hundreds of milliseconds on a slow disk with
/// scan-on-close at worst — and a handle that is genuinely leaked never
/// closes, so this is also how long a leak takes to fail.
const Duration deleteDirTimeout = Duration(seconds: 5);

/// Deletes [dir] recursively, retrying while a file in it is still held.
///
/// On Windows a file whose handle is still open — the app's own last
/// write (#143), or the virus scanner or the indexer looking at a file
/// that was just closed (#317) — cannot be deleted (a sharing violation,
/// errno 32), and neither can its directory. A single `deleteSync` in a
/// tear-down then fails a test that passed. So the delete is retried until
/// [timeout], and when it still fails the failure names the files that are
/// held — the recursive delete only ever names the directory, after it has
/// already removed every sibling that was free.
Future<void> deleteDirRetrying(
  Directory dir, {
  Duration timeout = deleteDirTimeout,
}) async {
  if (!dir.existsSync()) return;
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException catch (e) {
      if (!dir.existsSync()) return;
      if (DateTime.now().isAfter(deadline)) {
        fail(
          '${dir.path} still held after $timeout — '
          '${_heldFiles(dir).join(', ')}: $e',
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// The files in [dir] that refuse to be deleted, by path relative to [dir].
/// Only asked once the wait has been given up on: whatever it can delete on
/// the way, it does.
List<String> _heldFiles(Directory dir) {
  final held = <String>[];
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    try {
      file.deleteSync();
    } on FileSystemException {
      held.add(p.relative(file.path, from: dir.path));
    }
  }
  return held;
}
