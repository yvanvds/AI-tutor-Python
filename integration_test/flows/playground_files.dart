// End-to-end (#28, exercising #19 and #31): in playground mode a student
// saves the editor buffer to a named file and opens it again from the file
// browser. The store writes real files (to a temp directory the harness
// owns) and the browser reconciles them with the `playground_files` docs in
// the student's account, so code written on one classroom machine is there on
// the next one.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/playground_files.dart -d windows

import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../harness/app_harness.dart';
import '../harness/seed.dart';

const _code = 'for i in range(3):\n    print(i)\n';
const _otherMachineCode = 'print("written in the other classroom")\n';

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

    final file = File(p.join(harness.playgroundDir.path, 'loops.py'));
    await pumpUntil(
      tester,
      () => file.existsSync(),
      reason: 'loops.py was not written',
    );
    expect(file.readAsStringSync(), _code);
    await pumpUntilFound(tester, find.text('Saved as "loops".'));
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
      expect(harness.playgroundDir.listSync(), isEmpty);

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
      // It is on this machine now, so it is there again offline.
      expect(
        File(p.join(harness.playgroundDir.path, 'from school.py'))
            .readAsStringSync(),
        _otherMachineCode,
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
      await pumpUntilGone(tester, find.byType(AlertDialog));

      await harness.dispose(tester);
    },
  );
}
