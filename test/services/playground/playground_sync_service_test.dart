// Issue #31 — playground files used to live only on the machine the student
// happened to be sitting at, so their code did not follow them between
// classroom computers. `PlaygroundSyncService` reconciles the local store
// with a `playground_files` doc per file in the student's account.
//
// The interesting behaviour is not "upload a file" but what happens when the
// same name moved on both sides: these tests pin the four outcomes the
// service promises — push, pull, tombstoned delete, and a conflict that keeps
// both versions instead of picking one.

import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:ai_tutor_python/services/playground/playground_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _uid = 'student-1';
const _loops = 'for i in range(3):\n    print(i)\n';

void main() {
  late Directory root;
  late PlaygroundFileStore store;
  late InMemoryCosmos cosmos;
  late PlaygroundSyncService sync;
  String? uid;

  setUp(() {
    root = Directory.systemTemp.createTempSync('playground_sync_');
    store = PlaygroundFileStore(rootDir: () async => root);
    cosmos = InMemoryCosmos();
    uid = _uid;
    sync = PlaygroundSyncService(
      store: store,
      remote: PlaygroundFilesService(
        container: cosmos.container,
        getUid: () => uid,
      ),
      getUid: () => uid,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Writes a doc the way the student's *other* machine would have left it.
  void onOtherMachine(
    String name,
    String code, {
    DateTime? at,
    bool deleted = false,
  }) {
    cosmos.docs[CosmosDocId.playgroundFile(_uid, name)] = PlaygroundFileDoc(
      name: name,
      code: code,
      updatedAt: at ?? DateTime.utc(2026, 1, 1),
      deleted: deleted,
    ).toMap(_uid);
  }

  PlaygroundFileDoc? account(String name) {
    final doc = cosmos[CosmosDocId.playgroundFile(_uid, name)];
    return doc == null ? null : PlaygroundFileDoc.fromCosmos(doc);
  }

  test('first sync uploads the files this machine already had', () async {
    await store.save('loops', _loops);

    final result = await sync.sync();

    expect(result.pushed, 1);
    expect(result.pulled, 0);
    expect(account('loops')!.code, _loops);
    expect(account('loops')!.deleted, isFalse);
  });

  test('a file saved on another machine lands on this one', () async {
    onOtherMachine('hello', 'print("hi")\n');

    final result = await sync.sync();

    expect(result.pulled, 1);
    expect(await store.list(), ['hello']);
    expect(await store.load('hello'), 'print("hi")\n');
  });

  test('a second sync with nothing changed transfers nothing', () async {
    await store.save('loops', _loops);
    onOtherMachine('hello', 'print("hi")\n');
    await sync.sync();

    final result = await sync.sync();

    expect(result.pushed, 0);
    expect(result.pulled, 0);
    expect(result.removed, 0);
    expect(result.conflicts, isEmpty);
  });

  test(
    'deleting here leaves a tombstone instead of dropping the doc',
    () async {
      await store.save('loops', _loops);
      await sync.sync();

      await store.delete('loops');
      final result = await sync.sync();

      expect(result.pushed, 1);
      expect(account('loops')!.deleted, isTrue);
      // Without the tombstone the next sync would pull the file straight back.
      final again = await sync.sync();
      expect(again.pulled, 0);
      expect(await store.list(), isEmpty);
    },
  );

  test('a delete on another machine removes the local file', () async {
    await store.save('loops', _loops);
    await sync.sync();

    onOtherMachine('loops', '', at: DateTime.utc(2026, 2, 1), deleted: true);
    final result = await sync.sync();

    expect(result.removed, 1);
    expect(await store.list(), isEmpty);
  });

  test('a local edit wins when the account did not move', () async {
    await store.save('loops', _loops);
    await sync.sync();

    await store.save('loops', 'print("edited here")\n');
    final result = await sync.sync();

    expect(result.pushed, 1);
    expect(result.conflicts, isEmpty);
    expect(account('loops')!.code, 'print("edited here")\n');
  });

  test('a remote edit wins when this machine did not move', () async {
    await store.save('loops', _loops);
    await sync.sync();

    onOtherMachine(
      'loops',
      'print("edited there")\n',
      at: DateTime.utc(2026, 3),
    );
    final result = await sync.sync();

    expect(result.pulled, 1);
    expect(result.conflicts, isEmpty);
    expect(await store.load('loops'), 'print("edited there")\n');
  });

  test('the same file edited on both machines keeps both versions', () async {
    await store.save('loops', _loops);
    await sync.sync();

    await store.save('loops', 'print("mine")\n');
    onOtherMachine('loops', 'print("theirs")\n', at: DateTime.utc(2026, 3));

    final result = await sync.sync();

    expect(result.conflicts, ['loops conflict']);
    // Nothing is discarded: the account's version keeps the name, this
    // machine's version is kept beside it and uploaded too.
    expect(await store.load('loops'), 'print("theirs")\n');
    expect(await store.load('loops conflict'), 'print("mine")\n');
    expect(account('loops conflict')!.code, 'print("mine")\n');
    expect((await store.list())..sort(), ['loops', 'loops conflict']);

    // And the conflict is not re-reported once both sides know about it.
    expect((await sync.sync()).conflicts, isEmpty);
  });

  test('a conflict copy does not overwrite an existing name', () async {
    await store.save('loops', _loops);
    await store.save('loops conflict', 'print("older conflict")\n');
    await sync.sync();

    await store.save('loops', 'print("mine")\n');
    onOtherMachine('loops', 'print("theirs")\n', at: DateTime.utc(2026, 3));

    final result = await sync.sync();

    expect(result.conflicts, ['loops conflict 2']);
    expect(await store.load('loops conflict'), 'print("older conflict")\n');
    expect(await store.load('loops conflict 2'), 'print("mine")\n');
  });

  test('a file deleted here but edited elsewhere comes back', () async {
    await store.save('loops', _loops);
    await sync.sync();

    await store.delete('loops');
    onOtherMachine('loops', 'print("theirs")\n', at: DateTime.utc(2026, 3));

    final result = await sync.sync();

    expect(result.pulled, 1);
    expect(await store.load('loops'), 'print("theirs")\n');
  });

  test('push mirrors one save, and the next sync has nothing to do', () async {
    await store.save('loops', _loops);
    await sync.push('loops', _loops);

    expect(account('loops')!.code, _loops);
    final result = await sync.sync();
    expect(result.pushed, 0);
    expect(result.pulled, 0);
  });

  test('pushDelete tombstones one delete straight away', () async {
    await store.save('loops', _loops);
    await sync.push('loops', _loops);

    await store.delete('loops');
    await sync.pushDelete('loops');

    expect(account('loops')!.deleted, isTrue);
    expect((await sync.sync()).pulled, 0);
  });

  test('nothing is uploaded when no one is signed in', () async {
    uid = null;
    await store.save('loops', _loops);

    final result = await sync.sync();

    expect(result.pushed, 0);
    expect(cosmos.docs, isEmpty);
  });

  test('a lost sync index duplicates rather than drops work', () async {
    await store.save('loops', _loops);
    await sync.sync();
    await store.save('loops', 'print("mine")\n');
    // Wipe the sidecar: every file now looks locally changed.
    File('${root.path}/${PlaygroundFileStore.syncMetaFile}').deleteSync();

    final result = await sync.sync();

    expect(result.conflicts, ['loops conflict']);
    expect(await store.load('loops'), _loops);
    expect(await store.load('loops conflict'), 'print("mine")\n');
  });
}
