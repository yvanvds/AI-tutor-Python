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
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo (#28).

import 'dart:io';

import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:py_runner/py_runner.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> requestExercise() async {}

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _code = 'for i in range(3):\n    print(i)\n';

void main() {
  late Directory root;
  late PlaygroundFileStore store;
  late OutputService output;
  late ChatService chat;

  setUp(() {
    root = Directory.systemTemp.createTempSync('playground_files_');
    store = PlaygroundFileStore(rootDir: () async => root);
    output = OutputService(
      pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
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
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  CodeService editor(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(PlaygroundView)),
  ).read(codeServiceProvider(SessionMode.playground));

  File fileFor(String name) => File(p.join(root.path, '$name.py'));

  Future<void> saveAs(WidgetTester tester, String name) async {
    await tester.tap(find.text('Save'));
    await settle(tester);
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
    await settle(tester);
  }

  testWidgets('Save writes the editor buffer to <name>.py and shows the name', (
    tester,
  ) async {
    await mount(tester);
    editor(tester).setText(_code);

    await saveAs(tester, 'loops');

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
    await settle(tester);

    expect(find.text('hello.py'), findsOneWidget);
    expect(find.text('loops.py'), findsOneWidget);

    await tester.tap(find.text('loops.py'));
    await settle(tester);

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
    await settle(tester);
    await tester.tap(find.text('loops.py'));
    await settle(tester);

    expect(find.text('Replace current code?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(editor(tester).getText(), 'x = 1\n');

    await tester.tap(find.text('Open'));
    await settle(tester);
    await tester.tap(find.text('loops.py'));
    await settle(tester);
    await tester.tap(find.text('Replace'));
    await settle(tester);
    expect(editor(tester).getText(), _code);

    await unmount(tester);
  });

  testWidgets('Open shows an empty state when nothing was saved yet', (
    tester,
  ) async {
    await mount(tester);

    await tester.tap(find.text('Open'));
    await settle(tester);

    expect(find.text('No saved files yet.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Delete in the open dialog removes the file after confirming', (
    tester,
  ) async {
    await seed(tester, 'loops', _code);
    await mount(tester);

    await tester.tap(find.text('Open'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await settle(tester);

    expect(find.text('Delete "loops"?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(fileFor('loops').existsSync(), isFalse);
    expect(find.text('No saved files yet.'), findsOneWidget);

    await unmount(tester);
  });
}
