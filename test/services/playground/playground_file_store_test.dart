import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:ai_tutor_python/services/playground/playground_sync_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../helpers/controlled_folder_access.dart';
import '../../helpers/delete_dir.dart';
import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/test_app_mode.dart';

void main() {
  late Directory root;
  late PlaygroundFileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('playground_store_');
    store = PlaygroundFileStore(rootDir: () async => root);
  });

  tearDown(() => deleteDirRetrying(root));

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
  });

  // #344: Windows' Controlled folder access protects Documents, where the
  // playground used to keep its files, and a save there failed. The files
  // now live in the app data, a folder per student.
  group('where the files are (#344)', () {
    late Directory appData;
    late Directory documents;

    setUp(() {
      appData = Directory(p.join(root.path, 'AppData'))..createSync();
      documents = Directory(p.join(root.path, 'Documents'))..createSync();
    });

    ProviderContainer app({String? uid = 'uid-a', AppMode? mode}) {
      final container = ProviderContainer(
        overrides: [
          appModeProvider.overrideWithValue(mode ?? kTestSchoolMode),
          authServiceProvider.overrideWith(() => _SignedIn(uid)),
          playgroundAppDataDirProvider.overrideWithValue(() async => appData),
          playgroundDocumentsDirProvider.overrideWithValue(
            () async => documents,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the app data folder, not Documents, is where they go', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(playgroundAppDataDirProvider),
        getApplicationSupportDirectory,
      );
    });

    test('a save lands in <app data>/playground/<uid>; Documents stays '
        'empty', () async {
      final store = app().read(playgroundFileStoreProvider);
      await store.save('loops', 'print(1)');

      final saved = File(
        p.join(appData.path, 'playground', 'uid-a', 'loops.py'),
      );
      expect(saved.readAsStringSync(), 'print(1)');
      expect(await store.list(), ['loops']);
      expect(documents.listSync(), isEmpty);
    });

    test('each student has a folder of their own', () async {
      await app(uid: 'uid-a').read(playgroundFileStoreProvider).save('a', 'a');
      await app(uid: 'uid-b').read(playgroundFileStoreProvider).save('b', 'b');

      final base = p.join(appData.path, 'playground');
      expect(File(p.join(base, 'uid-a', 'a.py')).existsSync(), isTrue);
      expect(File(p.join(base, 'uid-b', 'b.py')).existsSync(), isTrue);
      expect(File(p.join(base, 'uid-a', 'b.py')).existsSync(), isFalse);
    });

    test('stand-alone: the same folder, in the stand-alone mode\'s own '
        'app data', () async {
      final store = app(
        uid: 'local-uid',
        mode: const StandaloneMode(),
      ).read(playgroundFileStoreProvider);
      await store.save('loops', 'print(1)');

      expect(
        File(
          p.join(
            appData.path,
            'standalone',
            'playground',
            'local-uid',
            'loops.py',
          ),
        ).readAsStringSync(),
        'print(1)',
      );
      expect(documents.listSync(), isEmpty);
    });

    test('with Documents protected, saving works and the old files are '
        'there', () async {
      final old = _oldFolder(documents, 'uid-a')..createSync(recursive: true);
      File(p.join(old.path, 'old.py')).writeAsStringSync('print("old")');

      await withControlledFolderAccess(documents, () async {
        final store = app().read(playgroundFileStoreProvider);
        await store.save('new', 'print("new")');
        expect(await store.list(), ['new', 'old']);
        expect(await store.load('old'), 'print("old")');
      });

      expect(old.listSync().map((e) => p.basename(e.path)), ['old.py']);
    });
  });

  group('copy from Documents (#344)', () {
    late Directory appData;
    late Directory documents;

    setUp(() {
      appData = Directory(p.join(root.path, 'AppData', 'playground'))
        ..createSync(recursive: true);
      documents = Directory(
        p.join(root.path, 'Documents', 'AI Tutor Python', 'playground'),
      )..createSync(recursive: true);
    });

    /// [files] in [uid]'s old folder in Documents.
    Directory inDocuments(String uid, Map<String, String> files) {
      final dir = Directory(p.join(documents.path, uid))..createSync();
      files.forEach((name, text) {
        File(p.join(dir.path, name)).writeAsStringSync(text);
      });
      return dir;
    }

    /// What a folder holds, by name, without the copy's marker.
    Map<String, String> contents(Directory dir) => {
      for (final file in dir.listSync().whereType<File>())
        if (p.basename(file.path) !=
            PlaygroundFileStore.copiedFromDocumentsFile)
          p.basename(file.path): file.readAsStringSync(),
    };

    Future<Directory> start(String uid) =>
        resolvePlaygroundDir(appData, uid, documentsBase: documents);

    test('the files in the old folder come over once', () async {
      final old = inDocuments('uid-a', {
        'loops.py': 'print(1)',
        'game.py': 'print(2)',
        PlaygroundFileStore.syncMetaFile: '{"version":1,"files":{}}',
      });
      inDocuments('uid-b', {'theirs.py': 'print(3)'});

      final dir = await start('uid-a');
      expect(p.equals(dir.path, p.join(appData.path, 'uid-a')), isTrue);
      expect(contents(dir), {
        'loops.py': 'print(1)',
        'game.py': 'print(2)',
        PlaygroundFileStore.syncMetaFile: '{"version":1,"files":{}}',
      });
      // Copied, not moved; another student's files stay where they are.
      expect(contents(old), hasLength(3));
      expect(Directory(p.join(appData.path, 'uid-b')).existsSync(), isFalse);

      // The student deletes one; the next start does not bring it back.
      final store = PlaygroundFileStore(rootDir: () => start('uid-a'));
      await store.delete('loops');
      expect(await store.list(), ['game']);
      expect(contents(await start('uid-a')).keys, isNot(contains('loops.py')));
    });

    test('a file already in the new folder is not overwritten', () async {
      inDocuments('uid-a', {'loops.py': 'print("old")', 'game.py': 'x'});
      final dir = Directory(p.join(appData.path, 'uid-a'))..createSync();
      File(p.join(dir.path, 'loops.py')).writeAsStringSync('print("new")');

      await start('uid-a');

      expect(contents(dir), {'loops.py': 'print("new")', 'game.py': 'x'});
    });

    test('an old folder that cannot be written does not make the copy '
        'fail', () async {
      final old = inDocuments('uid-a', {
        'loops.py': 'print(1)',
        PlaygroundFileStore.syncMetaFile: '{"version":1,"files":{}}',
      });

      final dir = await withControlledFolderAccess(
        documents,
        () => start('uid-a'),
      );

      expect(contents(dir), {
        'loops.py': 'print(1)',
        PlaygroundFileStore.syncMetaFile: '{"version":1,"files":{}}',
      });
      expect(contents(old), hasLength(2));
    });

    test('without an old folder there is nothing to copy', () async {
      final dir = await start('uid-new');
      expect(contents(dir), isEmpty);
      expect(
        await PlaygroundFileStore(rootDir: () async => dir).list(),
        isEmpty,
      );
    });

    test('what cannot be read is left to the sync, which brings it from the '
        'account instead of deleting it there', () async {
      // Both files agreed with the account at the last sync on the old
      // folder; `game.py` is a OneDrive file that cannot be read now.
      final at = DateTime.utc(2026, 10, 22);
      final cosmos = InMemoryCosmos();
      final remote = PlaygroundFilesService(
        container: cosmos.container,
        getUid: () => 'uid-a',
      );
      await remote.upsert(
        PlaygroundFileDoc(name: 'loops', code: 'print(1)', updatedAt: at),
      );
      await remote.upsert(
        PlaygroundFileDoc(name: 'game', code: 'print(2)', updatedAt: at),
      );
      final sidecar = {
        'version': 1,
        'files': {
          for (final (name, code) in [
            ('loops', 'print(1)'),
            ('game', 'print(2)'),
          ])
            name: {
              'remoteAt': at.toIso8601String(),
              'hash': sha1.convert(utf8.encode(code)).toString(),
            },
        },
      };
      inDocuments('uid-a', {
        'loops.py': 'print(1)',
        'game.py': 'print(2)',
        PlaygroundFileStore.syncMetaFile: jsonEncode(sidecar),
      });

      final dir = await withControlledFolderAccess(
        documents,
        () => start('uid-a'),
        unreadable: {'game.py'},
      );
      // The sidecar stays behind with it: it names `game`, which is not here.
      expect(contents(dir), {'loops.py': 'print(1)'});

      final store = PlaygroundFileStore(rootDir: () async => dir);
      final result = await PlaygroundSyncService(
        store: store,
        remote: remote,
        getUid: () => 'uid-a',
      ).sync();

      expect(result.pulled, 1);
      expect(await store.load('game'), 'print(2)');
      final game = (await remote.listAll()).singleWhere(
        (d) => d.name == 'game',
      );
      expect(game.deleted, isFalse);
    });
  });
}

/// A student's folder in Documents, before #344.
Directory _oldFolder(Directory documents, String uid) =>
    Directory(p.join(documentsPlaygroundBaseDir(documents).path, uid));

class _SignedIn extends AuthService {
  _SignedIn(this._uid);
  final String? _uid;

  @override
  AccountIdentity? build() => _uid == null
      ? null
      : AccountIdentity(
          oid: _uid,
          displayName: 'Test Student',
          email: '',
          firstName: 'Test',
          lastName: 'Student',
          isTeacher: false,
        );
}
