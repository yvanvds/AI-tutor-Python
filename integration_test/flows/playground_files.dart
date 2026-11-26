// End-to-end (#28, exercising #19 and #31): in playground mode a student
// saves the editor buffer to a named file and opens it again from the file
// browser. The store writes real files and the browser reconciles them with
// the `playground_files` docs in the student's account, so code written on
// one classroom machine is there on the next one.
//
// Where the files are (#344): in the app data, a folder per student —
// `playground/<uid>`, in the stand-alone mode under its own `standalone/`.
// Not in Documents, which Windows' Controlled folder access protects: a save
// there failed. The files a student had in Documents are copied over on the
// first start and opened from the app data; Documents is only read. The
// harness's own temp folders stand in for both (`AppHarness.appDataDir`,
// `AppHarness.documentsDir`); the app's real path logic runs on them.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/playground_files.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/curriculum_bundle.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/local_profile.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../../test/helpers/delete_dir.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

const _code = 'for i in range(3):\n    print(i)\n';
const _otherMachineCode = 'print("written in the other classroom")\n';
const _documentsCode = 'print("saved in Documents, before the update")\n';

/// The stand-alone profile's uid: a made-up one, as `LocalProfile.create`
/// makes them.
const _localUid = '0f3c2e7a-3440-4d6b-9c1e-5a7b8c9d0e1f';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Playground -> Save writes <name>.py; Open lists and loads it', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    final editor = harness.container.read(
      codeServiceProvider(SessionMode.playground),
    );
    editor.setText(_code);
    await tester.pump();

    await tester.tap(find.text('Save'));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'loops',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
    );

    // In the app data, in the student's own folder (#344).
    final file = File(
      p.join(harness.appDataDir.path, 'playground', kStudentUid, 'loops.py'),
    );
    // The content belongs in the wait condition: writeAsString creates the
    // file before filling it, so existence alone can expose an empty read on
    // a slow disk (#104).
    await pumpUntil(
      tester,
      () => file.existsSync() && file.readAsStringSync() == _code,
      reason: 'loops.py was not written',
    );
    await pumpUntilFound(tester, find.text('Saved as "loops".'));
    // Nothing in Documents, not even an empty folder.
    expect(harness.documentsDir.listSync(), isEmpty);
    expect(find.text('loops.py'), findsOneWidget);
    // The dialog route is still animating out when the snackbar appears.
    await pumpUntilGone(tester, find.byType(AlertDialog));

    // Replace the buffer with something else, then open the saved file.
    editor.setText('x = 1\n');
    await tester.pump();

    await tester.tap(find.text('Open'));
    await pumpUntilFound(tester, find.widgetWithText(ListTile, 'loops.py'));
    await tester.tap(find.widgetWithText(ListTile, 'loops.py'));

    // The buffer is dirty, so the open asks first.
    await pumpUntilFound(tester, find.text('Replace current code?'));
    await tester.tap(find.text('Replace'));
    await pumpUntil(
      tester,
      () => editor.getText() == _code,
      reason: 'the editor did not load loops.py',
    );
    await pumpUntilGone(tester, find.byType(AlertDialog));
    expect(find.text('loops.py'), findsOneWidget);

    await harness.dispose(tester);
  });

  testWidgets(
    'Playground -> code saved on another machine opens here, and a save '
    'goes back to the account',
    (tester) async {
      final harness = AppHarness();
      await harness.boot(tester);

      // What the student left in their account from the other classroom.
      // This machine has never seen it: its playground directory is empty.
      harness.cosmos['playground_files'].docs[CosmosDocId.playgroundFile(
        kStudentUid,
        'from school',
      )] = PlaygroundFileDoc(
        name: 'from school',
        code: _otherMachineCode,
        updatedAt: DateTime.utc(2026, 1, 1),
      ).toMap(kStudentUid);

      await tester.tap(find.text('Playground'));
      await pumpUntilFound(tester, find.byType(PlaygroundView));
      expect(harness.playgroundDir.existsSync(), isFalse);

      // Opening the browser reconciles with the account first.
      await tester.tap(find.text('Open'));
      await pumpUntilFound(
        tester,
        find.widgetWithText(ListTile, 'from school.py'),
      );
      await tester.tap(find.widgetWithText(ListTile, 'from school.py'));

      final editor = harness.container.read(
        codeServiceProvider(SessionMode.playground),
      );
      await pumpUntil(
        tester,
        () => editor.getText() == _otherMachineCode,
        reason: 'the file from the account did not open',
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));
      // It is on this machine now, so it is there again offline. Waited-for
      // rather than asserted flat: the local mirror write races the editor
      // update that the pumpUntil above observed (#104).
      final mirror = File(p.join(harness.playgroundDir.path, 'from school.py'));
      await pumpUntil(
        tester,
        () =>
            mirror.existsSync() &&
            mirror.readAsStringSync() == _otherMachineCode,
        reason: 'the account file was not mirrored to this machine',
      );

      // The other direction: what is saved here reaches the account.
      editor.setText(_code);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await pumpUntilFound(tester, find.byType(AlertDialog));
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'loops',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Save'),
        ),
      );

      final docId = CosmosDocId.playgroundFile(kStudentUid, 'loops');
      await pumpUntil(
        tester,
        () => harness.cosmos['playground_files'][docId] != null,
        reason: 'the save never reached the account',
      );
      final saved = PlaygroundFileDoc.fromCosmos(
        harness.cosmos['playground_files'][docId]!,
      );
      expect(saved.code, _code);
      expect(saved.deleted, isFalse);
      // The account write is not the app's last write for this save: the
      // sync layer then records the stamp it agreed with in its sidecar,
      // on disk next to the file (#31). Waited for, so the flow ends after
      // that write and not in the middle of it (#143) — its `close` can
      // still be in flight, which `dispose` waits out.
      final index = File(
        p.join(harness.playgroundDir.path, PlaygroundFileStore.syncMetaFile),
      );
      await pumpUntil(
        tester,
        () =>
            index.existsSync() && index.readAsStringSync().contains('"loops"'),
        reason: 'the save was not recorded in the sync index',
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));

      await harness.dispose(tester);
    },
  );

  testWidgets(
    'Playground (#344) -> after the update the files from Documents are '
    'there; a save lands in the app data, and Documents is only read',
    (tester) async {
      // What this student saved in Documents with the build before, and
      // another student's folder on the same pc.
      final harness = AppHarness(
        documentsPlaygroundFiles: {
          '$kStudentUid/from documents.py': _documentsCode,
          'another-student/theirs.py': 'print("not yours")\n',
        },
      );
      await harness.boot(tester);
      final documents = _snapshot(harness.documentsDir);
      expect(documents, hasLength(2));

      await tester.tap(find.text('Playground'));
      await pumpUntilFound(tester, find.byType(PlaygroundView));

      await tester.tap(find.text('Open'));
      await pumpUntilFound(
        tester,
        find.widgetWithText(ListTile, 'from documents.py'),
      );
      expect(find.widgetWithText(ListTile, 'theirs.py'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'from documents.py'));
      final editor = harness.container.read(
        codeServiceProvider(SessionMode.playground),
      );
      await pumpUntil(
        tester,
        () => editor.getText() == _documentsCode,
        reason: 'the file from Documents did not open',
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));

      // It is in the student's folder in the app data now, and the sync
      // took it to the account, as any file this machine had.
      final copied = File(
        p.join(
          harness.appDataDir.path,
          'playground',
          kStudentUid,
          'from documents.py',
        ),
      );
      expect(copied.readAsStringSync(), _documentsCode);
      final copiedId = CosmosDocId.playgroundFile(
        kStudentUid,
        'from documents',
      );
      await pumpUntil(
        tester,
        () => harness.cosmos['playground_files'][copiedId] != null,
        reason: 'the file from Documents never reached the account',
      );
      expect(
        PlaygroundFileDoc.fromCosmos(
          harness.cosmos['playground_files'][copiedId]!,
        ).code,
        _documentsCode,
      );

      // A save goes to the app data, and from there to the account.
      editor.setText(_code);
      await tester.pump();
      await _saveAs(tester, 'loops');
      final saved = File(p.join(harness.playgroundDir.path, 'loops.py'));
      await pumpUntil(
        tester,
        () => saved.existsSync() && saved.readAsStringSync() == _code,
        reason: 'loops.py was not written to the app data',
      );
      await pumpUntilFound(tester, find.text('Saved as "loops".'));
      final loopsId = CosmosDocId.playgroundFile(kStudentUid, 'loops');
      await pumpUntil(
        tester,
        () => harness.cosmos['playground_files'][loopsId] != null,
        reason: 'the save never reached the account',
      );
      final index = File(
        p.join(harness.playgroundDir.path, PlaygroundFileStore.syncMetaFile),
      );
      await pumpUntil(
        tester,
        () =>
            index.existsSync() && index.readAsStringSync().contains('"loops"'),
        reason: 'the save was not recorded in the sync index',
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));

      // Documents as it was: nothing written, moved or deleted there.
      expect(_snapshot(harness.documentsDir), documents);

      await harness.dispose(tester);
    },
  );

  testWidgets(
    'Playground (#344), stand-alone -> the same folder in its own app data; '
    'the files from Documents come along and a save reaches its own storage',
    (tester) async {
      final data = Directory.systemTemp.createTempSync('ai_tutor_standalone_');
      addTearDown(() => deleteDirRetrying(data));

      // The first start after the update: the profile and the key are there
      // from before, and so is what the student saved in Documents.
      final harness = AppHarness(
        appMode: const StandaloneMode(),
        localData: data,
        curriculumBundle: DirectoryCurriculumBundleSource(
          Directory('test/fixtures/curriculum_bundle'),
        ),
        prefs: {
          const StandaloneMode().scopedPrefsKey(
            LocalProfileStore.prefsKey,
          ): jsonEncode(
            const LocalProfile(uid: _localUid, firstName: 'Alex').toJson(),
          ),
          'local_api_key': 'sk-own-key',
        },
        documentsPlaygroundFiles: {
          '$_localUid/from documents.py': _documentsCode,
        },
      );
      await harness.boot(tester);
      final documents = _snapshot(harness.documentsDir);

      await tester.tap(find.text('Playground'));
      await pumpUntilFound(tester, find.byType(PlaygroundView));

      await tester.tap(find.text('Open'));
      await pumpUntilFound(
        tester,
        find.widgetWithText(ListTile, 'from documents.py'),
      );
      await tester.tap(find.widgetWithText(ListTile, 'from documents.py'));
      final editor = harness.container.read(
        codeServiceProvider(SessionMode.playground),
      );
      await pumpUntil(
        tester,
        () => editor.getText() == _documentsCode,
        reason: 'the file from Documents did not open',
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));

      editor.setText(_code);
      await tester.pump();
      await _saveAs(tester, 'loops');

      // In the stand-alone mode's own app data, never in school mode's.
      final saved = File(
        p.join(
          harness.appDataDir.path,
          'standalone',
          'playground',
          _localUid,
          'loops.py',
        ),
      );
      await pumpUntil(
        tester,
        () => saved.existsSync() && saved.readAsStringSync() == _code,
        reason: 'loops.py was not written to the stand-alone app data',
      );
      await pumpUntilFound(tester, find.text('Saved as "loops".'));
      expect(
        File(p.join(harness.playgroundDir.path, 'from documents.py'))
            .readAsStringSync(),
        _documentsCode,
      );
      expect(
        Directory(p.join(harness.appDataDir.path, 'playground')).existsSync(),
        isFalse,
      );
      // The stand-alone "account" is its own storage on the pc: the save is
      // there, as a doc of `playground_files`.
      final local = Directory(p.join(data.path, 'playground_files'));
      await pumpUntil(
        tester,
        () => _anyFileContains(local, 'range(3)'),
        reason: 'the save never reached the stand-alone storage',
      );
      final index = File(
        p.join(harness.playgroundDir.path, PlaygroundFileStore.syncMetaFile),
      );
      await pumpUntil(
        tester,
        () =>
            index.existsSync() && index.readAsStringSync().contains('"loops"'),
        reason: 'the save was not recorded in the sync index',
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));
      expect(_snapshot(harness.documentsDir), documents);

      await harness.dispose(tester);
    },
  );
}

/// Saves the editor buffer as [name] through the Save dialog.
Future<void> _saveAs(WidgetTester tester, String name) async {
  await tester.tap(find.text('Save'));
  await pumpUntilFound(tester, find.byType(AlertDialog));
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    name,
  );
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')),
  );
}

/// Whether a file under [dir] holds [text]. A file the local storage is
/// still writing (`<id>.json.tmp`, renamed when done) can be gone or held
/// by the time it is read; it is looked at again on the next try.
bool _anyFileContains(Directory dir, String text) {
  if (!dir.existsSync()) return false;
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    try {
      if (file.readAsStringSync().contains(text)) return true;
    } on FileSystemException {
      continue;
    }
  }
  return false;
}

/// Every file under [dir], by path relative to it, with its contents.
Map<String, String> _snapshot(Directory dir) => {
  for (final file in dir.listSync(recursive: true).whereType<File>())
    p.relative(file.path, from: dir.path): file.readAsStringSync(),
};
