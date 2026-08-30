// Issue #19 — students in playground mode ("vrij coderen") had no way to keep
// their code between sessions. The playground header now carries a Save
// button (name prompt, writes `<name>.py`) and an Open button (lists saved
// files, loads one into the editor, can delete one).
//
// This mounts the real `PlaygroundView` (header strip + the full
// `PracticeView` with run controls, code editor, split view and output
// panel) over a real `PlaygroundFileStore` pointed at a temp directory, so
// the flows are exercised through the real dialogs and land on disk exactly
// as they would for a student. The `OutputService` wraps a `PyRunner` that
// is never started.
//
// The account side of the browser (#31) is driven here too: the store is
// backed by a temp directory and the `playground_files` container by an
// in-memory Cosmos, so Open reconciles and Save mirrors exactly as they do
// for a signed-in student.
//
// The end-to-end run of the same flows lives in
// `integration_test/flows/playground_files.dart` (#28).

import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:ai_tutor_python/services/playground/playground_sync_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:py_runner/py_runner.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> requestExercise() async {}

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _code = 'for i in range(3):\n    print(i)\n';
const _uid = 'student-1';

void main() {
  late Directory root;
  late PlaygroundFileStore store;
  late InMemoryCosmos cosmos;
  late PlaygroundSyncService sync;
  late OutputService output;
  late ChatService chat;

  setUp(() {
    root = Directory.systemTemp.createTempSync('playground_files_');
    store = PlaygroundFileStore(rootDir: () async => root);
    cosmos = InMemoryCosmos();
    sync = PlaygroundSyncService(
      store: store,
      remote: PlaygroundFilesService(
        container: cosmos.container,
        getUid: () => _uid,
      ),
      getUid: () => _uid,
    );
    output = OutputService(
      pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
      localizations: testLocalizations(),
    );
    chat = ChatService();
  });

  tearDown(() {
    chat.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      tutorServiceProvider.overrideWith(() => _FakeTutorService()),
      outputServiceProvider.overrideWithValue(output),
      chatServiceProvider.overrideWithValue(chat),
      modeProvider.overrideWith((_) => SessionMode.playground),
      playgroundFileStoreProvider.overrideWithValue(store),
      playgroundSyncServiceProvider.overrideWithValue(sync),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PlaygroundView()),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pump();
  }

  /// Seeds a file on disk the way an earlier session would have left it.
  /// Real file IO only completes with the real event loop running, so it
  /// goes through `runAsync`.
  Future<void> seed(WidgetTester tester, String name, String code) =>
      tester.runAsync(() => store.save(name, code));

  /// The editor's cursor blink never settles (so no `pumpAndSettle`), and the
  /// store's file IO — kicked off by the taps — needs real time to complete.
  /// Alternate a slice of real time with a fake-clock frame so dialog
  /// animations and IO both make progress.
  ///
  /// Ten slices always run (enough for the dialog animations, which are on
  /// the fake clock). When [until] is given, slices keep running until it
  /// holds, bounded by a real-time deadline: how long `save(flush: true)` or
  /// `list()` takes is the runner's disk speed, not a fixed number of slices
  /// — the fixed budget passed on a warm developer machine and failed on a
  /// cold CI runner under `--coverage` (#28).
  Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var i = 0;
    while (i < 10 || (until != null && !until())) {
      if (i >= 10 && DateTime.now().isAfter(deadline)) {
        fail('settle: condition still false after 10 s');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      i++;
    }
  }

  bool Function() shown(Finder finder) =>
      () => finder.evaluate().isNotEmpty;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  CodeService editor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PlaygroundView)))
          .read(codeServiceProvider(SessionMode.playground));

  File fileFor(String name) => File(p.join(root.path, '$name.py'));

  Future<void> saveAs(
    WidgetTester tester,
    String name, {
    bool Function()? until,
  }) async {
    await tester.tap(find.text('Save'));
    await settle(tester, until: shown(find.byType(AlertDialog)));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      name,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save'),
      ),
    );
    await settle(tester, until: until);
  }

  testWidgets('Save writes the editor buffer to <name>.py and shows the name', (
    tester,
  ) async {
    await mount(tester);
    editor(tester).setText(_code);

    // The header names the file once the write has completed *and* the
    // provider update has been pumped; wait for that, not for a clock.
    await saveAs(tester, 'loops', until: shown(find.text('loops.py')));

    expect(fileFor('loops').readAsStringSync(), _code);
    expect(find.text('loops.py'), findsOneWidget);
    expect(find.text('Saved as "loops".'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Save rejects an unsafe name and keeps the dialog open', (
    tester,
  ) async {
    await mount(tester);

    await saveAs(tester, '../escape');

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Use letters, digits, spaces, - or _ (max 60 characters).'),
      findsOneWidget,
    );
    expect(root.listSync(), isEmpty);

    await unmount(tester);
  });

  testWidgets('Open lists saved files and loads the chosen one', (
    tester,
  ) async {
    await seed(tester, 'loops', _code);
    await seed(tester, 'hello', 'print("hi")\n');
    await mount(tester);

    await tester.tap(find.text('Open'));
    await settle(tester, until: shown(find.text('loops.py')));

    expect(find.text('hello.py'), findsOneWidget);
    expect(find.text('loops.py'), findsOneWidget);

    await tester.tap(find.text('loops.py'));
    await settle(tester, until: () => editor(tester).getText() == _code);

    expect(find.byType(AlertDialog), findsNothing);
    expect(editor(tester).getText(), _code);
    // Header now names the open file; the editor shows its content.
    expect(find.text('loops.py'), findsOneWidget);
    expect(find.textContaining('range(3)', findRichText: true), findsWidgets);

    await unmount(tester);
  });

  testWidgets('Open asks before replacing unsaved work', (tester) async {
    await seed(tester, 'loops', _code);
    await mount(tester);
    editor(tester).setText('x = 1\n');

    await tester.tap(find.text('Open'));
    await settle(tester, until: shown(find.text('loops.py')));
    await tester.tap(find.text('loops.py'));
    await settle(tester, until: shown(find.text('Replace current code?')));

    expect(find.text('Replace current code?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(editor(tester).getText(), 'x = 1\n');

    await tester.tap(find.text('Open'));
    await settle(tester, until: shown(find.text('loops.py')));
    await tester.tap(find.text('loops.py'));
    await settle(tester, until: shown(find.text('Replace current code?')));
    await tester.tap(find.text('Replace'));
    await settle(tester, until: () => editor(tester).getText() == _code);
    expect(editor(tester).getText(), _code);

    await unmount(tester);
  });

  testWidgets('Open shows an empty state when nothing was saved yet', (
    tester,
  ) async {
    await mount(tester);

    await tester.tap(find.text('Open'));
    await settle(tester, until: shown(find.text('No saved files yet.')));

    expect(find.text('No saved files yet.'), findsOneWidget);

    await unmount(tester);
  });

  // #31 — the account side. Opening the browser reconciles first, so code
  // saved on another classroom machine is there; saving mirrors back up.
  testWidgets('Open lists a file the student saved on another computer', (
    tester,
  ) async {
    cosmos.docs[CosmosDocId.playgroundFile(_uid, 'shared')] = PlaygroundFileDoc(
      name: 'shared',
      code: _code,
      updatedAt: DateTime.utc(2026, 1, 1),
    ).toMap(_uid);
    await mount(tester);

    await tester.tap(find.text('Open'));
    await settle(tester, until: shown(find.text('shared.py')));

    expect(find.text('shared.py'), findsOneWidget);
    await tester.tap(find.text('shared.py'));
    await settle(tester, until: () => editor(tester).getText() == _code);

    expect(editor(tester).getText(), _code);
    // It was written to this machine too, so it is there offline next time.
    expect(fileFor('shared').readAsStringSync(), _code);

    await unmount(tester);
  });

  testWidgets('Save mirrors the file to the account', (tester) async {
    await mount(tester);
    editor(tester).setText(_code);

    await saveAs(
      tester,
      'loops',
      until: () => cosmos[CosmosDocId.playgroundFile(_uid, 'loops')] != null,
    );

    final doc = PlaygroundFileDoc.fromCosmos(
      cosmos[CosmosDocId.playgroundFile(_uid, 'loops')]!,
    );
    expect(doc.code, _code);
    expect(doc.deleted, isFalse);

    await unmount(tester);
  });

  testWidgets('Delete in the open dialog removes the file after confirming', (
    tester,
  ) async {
    await seed(tester, 'loops', _code);
    await mount(tester);

    await tester.tap(find.text('Open'));
    await settle(tester, until: shown(find.byIcon(Icons.delete_outline)));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await settle(tester, until: shown(find.text('Delete "loops"?')));

    expect(find.text('Delete "loops"?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settle(tester, until: shown(find.text('No saved files yet.')));

    expect(fileFor('loops').existsSync(), isFalse);
    expect(find.text('No saved files yet.'), findsOneWidget);
    // A tombstone, not a missing doc — otherwise the student's other machine
    // would push the file straight back on its next sync (#31).
    expect(
      PlaygroundFileDoc.fromCosmos(
        cosmos[CosmosDocId.playgroundFile(_uid, 'loops')]!,
      ).deleted,
      isTrue,
    );

    await unmount(tester);
  });
}
