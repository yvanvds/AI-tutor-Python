// #317 — a tear-down's delete of a temp folder failed on Windows while a
// file in it was still held (errno 32). These hold a file open the way the
// virus scanner or the app's own last write does, and check that the
// shared helper waits it out, and names the file when it never lets go.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'delete_dir.dart';

void main() {
  late Directory dir;
  late RandomAccessFile held;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('delete_dir_test_');
    File('${dir.path}/free.txt').writeAsStringSync('free');
    held = File('${dir.path}/held.txt').openSync(mode: FileMode.write);
  });

  tearDown(() async {
    try {
      held.closeSync();
    } on FileSystemException {
      // Already closed by the test.
    }
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final windowsOnly = Platform.isWindows
      ? null
      : 'only Windows refuses to delete an open file';

  test('a single delete fails while a file is held', () {
    expect(
      () => dir.deleteSync(recursive: true),
      throwsA(isA<FileSystemException>()),
    );
  }, skip: windowsOnly);

  test('waits until the held file is closed, then deletes', () async {
    Future<void>.delayed(
      const Duration(milliseconds: 300),
      () => held.closeSync(),
    );
    await deleteDirRetrying(dir);
    expect(dir.existsSync(), isFalse);
  }, skip: windowsOnly);

  test('names the held file when it is never closed', () async {
    await expectLater(
      deleteDirRetrying(dir, timeout: const Duration(milliseconds: 200)),
      throwsA(
        isA<TestFailure>().having(
          (f) => f.message,
          'message',
          contains('held.txt'),
        ),
      ),
    );
  }, skip: windowsOnly);

  test('a folder that is already gone is fine', () async {
    held.closeSync();
    dir.deleteSync(recursive: true);
    await deleteDirRetrying(dir);
  });
}
