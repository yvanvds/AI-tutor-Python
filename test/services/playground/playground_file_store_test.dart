import 'dart:io';

import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late PlaygroundFileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('playground_store_');
    store = PlaygroundFileStore(rootDir: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('normalizeName', () {
    test('trims and strips a trailing .py', () {
      expect(PlaygroundFileStore.normalizeName('  loops.py '), 'loops');
      expect(PlaygroundFileStore.normalizeName('My Game.PY'), 'My Game');
    });

    test('rejects empty, oversized and path-like names', () {
      expect(PlaygroundFileStore.normalizeName(''), isNull);
      expect(PlaygroundFileStore.normalizeName('.py'), isNull);
      expect(PlaygroundFileStore.normalizeName('../x'), isNull);
      expect(PlaygroundFileStore.normalizeName('a/b'), isNull);
      expect(PlaygroundFileStore.normalizeName(r'a\b'), isNull);
      expect(PlaygroundFileStore.normalizeName('a:b'), isNull);
      expect(PlaygroundFileStore.normalizeName('x' * 61), isNull);
    });
  });

  test('save / list / load / delete round-trip', () async {
    await store.save('b', 'print(2)');
    await store.save('A', 'print(1)');

    expect(await store.list(), ['A', 'b']);
    expect(await store.load('A'), 'print(1)');
    expect(File(p.join(root.path, 'b.py')).existsSync(), isTrue);

    await store.delete('b');
    expect(await store.list(), ['A']);
  });

  test('creates the root directory on first use', () async {
    final nested = Directory(p.join(root.path, 'nested', 'deeper'));
    final s = PlaygroundFileStore(rootDir: () async => nested);
    expect(await s.list(), isEmpty);
    expect(nested.existsSync(), isTrue);
  });

  test('ignores files that are not .py or have unsafe names', () async {
    File(p.join(root.path, 'notes.txt')).writeAsStringSync('x');
    File(p.join(root.path, 'ok.py')).writeAsStringSync('x');
    expect(await store.list(), ['ok']);
  });

  test('throws on an invalid name instead of touching the disk', () async {
    expect(
      () => store.save('../escape', 'x'),
      throwsA(isA<InvalidPlaygroundFileName>()),
    );
    expect(root.listSync(), isEmpty);
  });

  // Limits (#31): every saved file becomes one Cosmos doc in the student's
  // account, so both the size of a file and the number of them are capped.
  group('limits', () {
    test('refuses code over the per-file cap', () async {
      final tooBig = 'x' * (PlaygroundFileStore.maxFileBytes + 1);
      await expectLater(
        store.save('big', tooBig),
        throwsA(isA<PlaygroundFileTooLarge>()),
      );
      expect(await store.list(), isEmpty);
    });

    test('counts bytes, not characters', () async {
      // 'é' is two bytes in UTF-8, so this is one byte over the cap.
      final over = 'é' * (PlaygroundFileStore.maxFileBytes ~/ 2 + 1);
      await expectLater(
        store.save('accents', over),
        throwsA(isA<PlaygroundFileTooLarge>()),
      );
    });

    test(
      'refuses a new file past the count cap but still overwrites',
      () async {
        for (var i = 0; i < PlaygroundFileStore.maxFiles; i++) {
          File(p.join(root.path, 'f$i.py')).writeAsStringSync('x');
        }
        await expectLater(
          store.save('one more', 'x'),
          throwsA(isA<PlaygroundStoreFull>()),
        );
        // Saving over a file that already exists adds nothing, so it is fine.
        await store.save('f0', 'print(1)');
        expect(await store.load('f0'), 'print(1)');
      },
    );
  });

  test('the sync sidecar round-trips and stays out of the listing', () async {
    expect(await store.readSyncMeta(), isNull);
    await store.writeSyncMeta('{"version":1}');
    expect(await store.readSyncMeta(), '{"version":1}');
    expect(await store.list(), isEmpty);
  });

  group('resolvePlaygroundDir', () {
    test('gives each student their own folder', () async {
      final a = await resolvePlaygroundDir(root, 'uid-a');
      final b = await resolvePlaygroundDir(root, 'uid-b');
      expect(a.path, isNot(b.path));
      expect(p.basename(a.path), 'uid-a');
    });

    test('moves files from the flat #19 layout to the first student', () async {
      File(p.join(root.path, 'loops.py')).writeAsStringSync('print(1)');

      final a = await resolvePlaygroundDir(root, 'uid-a');
      expect(File(p.join(a.path, 'loops.py')).readAsStringSync(), 'print(1)');
      expect(File(p.join(root.path, 'loops.py')).existsSync(), isFalse);

      // The next student to sign in does not inherit them.
      final b = await resolvePlaygroundDir(root, 'uid-b');
      expect(Directory(b.path).listSync(), isEmpty);
    });
  });
}
