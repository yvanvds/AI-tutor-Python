// End-to-end (#333): Ctrl+Z in the editor ran on past the start of the
// exercise into the code of the exercise before it. Each new exercise puts
// its code in the editor, but the editor's undo history was kept, so
// pressing Ctrl+Z long enough brought back what the student had written for
// the previous exercise. Now, in the real app:
//
// - Ctrl+Z stops at the code the exercise opened with, and redo
//   (Ctrl+Shift+Z) brings back what was typed in it;
// - an exercise that opens with an empty editor (an open question) undoes
//   to the empty editor, not to the exercise before;
// - in the Playground, Ctrl+Z after opening a file stops at the file and
//   never brings back the code it replaced.
//
// Real app, real navigation, real practice view and editor with the
// package's own undo bindings, real TutorService putting each exercise in
// the editor, real Playground file browser. Only the model is scripted
// (`ScriptedLlm`, raw assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/editor_undo_start.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/playground/playground_files_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _exerciseA = 'som = 1 + ___\nprint(som)';
const String _typedInA = 'klaar = 1';
const String _exerciseB = 'leeftijd = ___\nprint(leeftijd)';
const String _typedInB = 'x = 2';
const String _openQuestion = 'Wat doet print?';
const String _fileCode = 'for i in range(3):\n    print(i)\n';

Finder get _editable => find.descendant(
  of: find.byType(CodeField),
  matching: find.byType(EditableText),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The text the practice or playground editor on screen shows.
  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// Focuses the editor and types [typed] one key at a time after what is
  /// in it, as a student does.
  Future<void> type(WidgetTester tester, String typed) async {
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    final before = editorText(tester);
    for (var k = 1; k <= typed.length; k++) {
      await tester.enterText(_editable, before + typed.substring(0, k));
      await tester.pump();
    }
    expect(editorText(tester), before + typed);
  }

  Future<void> ctrlZ(WidgetTester tester, {bool shift = false}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  /// Presses Ctrl+Z a dozen times — more than anything typed here takes —
  /// and returns what the editor showed after each press.
  Future<List<String>> undoMany(WidgetTester tester) async {
    final seen = <String>[];
    for (var i = 0; i < 12; i++) {
      await ctrlZ(tester);
      seen.add(editorText(tester));
    }
    return seen;
  }

  testWidgets('Ctrl+Z stops at the start of the exercise and never brings '
      'back the exercise before', (tester) async {
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Maak de som af.', code: _exerciseA),
      codeFeedbackReply(text: 'Bijna: welk getal?', quality: 'partial'),
      completeCodeReply(text: 'Vul je leeftijd in.', code: _exerciseB),
      codeFeedbackReply(text: 'Bijna: welke leeftijd?', quality: 'partial'),
      llmEnvelope(
        text: _openQuestion,
        meta: jsonEncode({
          'type': 'socratic_question',
          'prompt': _openQuestion,
        }),
      ),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);

    /// Waits until [exercise] is in the editor and the turn that put it
    /// there has finished.
    Future<void> waitForExercise(String exercise) => pumpUntil(
      tester,
      () =>
          editorText(tester) == exercise &&
          harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'exercise "$exercise" never reached the editor',
    );

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    // Exercise A: the student writes something and hands it in.
    await waitForExercise(_exerciseA);
    await type(tester, _typedInA);
    await tester.tap(find.byTooltip('Send to tutor'));

    // Exercise B: the student writes, then holds Ctrl+Z.
    await waitForExercise(_exerciseB);
    await type(tester, _typedInB);
    var seen = await undoMany(tester);
    expect(editorText(tester), _exerciseB);
    for (final text in seen) {
      expect(text, startsWith(_exerciseB), reason: 'undo left exercise B');
      expect(text, isNot(contains('som')), reason: 'exercise A came back');
      expect(text, isNot(contains(_typedInA)));
    }

    // Redo still gives back what was typed in this exercise.
    await ctrlZ(tester, shift: true);
    expect(editorText(tester), _exerciseB + _typedInB);

    // An open question opens with an empty editor: Ctrl+Z stays there.
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise('');
    await pumpUntilFound(
      tester,
      find.textContaining(_openQuestion, findRichText: true),
    );
    await type(tester, _typedInB);
    seen = await undoMany(tester);
    expect(editorText(tester), isEmpty);
    for (final text in seen) {
      expect(text, isNot(contains('leeftijd')), reason: 'exercise B came back');
    }
    await ctrlZ(tester, shift: true);
    expect(editorText(tester), _typedInB);

    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });

  testWidgets('in the Playground, Ctrl+Z after opening a file stops at the '
      'file and never brings back the code it replaced', (tester) async {
    final harness = AppHarness();
    await harness.boot(tester);

    // A file in the student's account, to open from the browser.
    harness.cosmos['playground_files'].docs[CosmosDocId.playgroundFile(
      kStudentUid,
      'lus',
    )] = PlaygroundFileDoc(
      name: 'lus',
      code: _fileCode,
      updatedAt: DateTime.utc(2026, 1, 1),
    ).toMap(kStudentUid);

    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));
    final editor = harness.container.read(
      codeServiceProvider(SessionMode.playground),
    );

    // Unsaved work in the buffer, then the file replaces it.
    await type(tester, '\n$_typedInA');
    await tester.tap(find.text('Open'));
    await pumpUntilFound(tester, find.widgetWithText(ListTile, 'lus.py'));
    await tester.tap(find.widgetWithText(ListTile, 'lus.py'));
    await pumpUntilFound(tester, find.text('Replace current code?'));
    await tester.tap(find.text('Replace'));
    await pumpUntil(
      tester,
      () => editor.getText() == _fileCode,
      reason: 'the editor did not load lus.py',
    );
    await pumpUntilGone(tester, find.byType(AlertDialog));

    await type(tester, _typedInB);
    final seen = await undoMany(tester);
    expect(editor.getText(), _fileCode);
    for (final text in seen) {
      expect(text, startsWith(_fileCode), reason: 'undo left the file');
      expect(
        text,
        isNot(contains(_typedInA)),
        reason: 'replaced code came back',
      );
      expect(text, isNot(contains(CodeService.starterText)));
    }

    // The open also writes the file to this machine; the flow ends after
    // that write, not in the middle of it (#104, #143).
    final mirror = File(p.join(harness.playgroundDir.path, 'lus.py'));
    await pumpUntil(
      tester,
      () => mirror.existsSync() && mirror.readAsStringSync() == _fileCode,
      reason: 'the opened file was not mirrored to this machine',
    );

    await harness.dispose(tester);
  });
}
