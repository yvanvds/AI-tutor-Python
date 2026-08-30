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
}
