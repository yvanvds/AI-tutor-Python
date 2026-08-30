// End-to-end (#28, exercising #19): in playground mode a student saves the
// editor buffer to a named file and opens it again from the file browser.
// The store writes real files (to a temp directory the harness owns).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/playground_files.dart -d windows

import 'dart:io';

import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../harness/app_harness.dart';

const _code = 'for i in range(3):\n    print(i)\n';

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
}
