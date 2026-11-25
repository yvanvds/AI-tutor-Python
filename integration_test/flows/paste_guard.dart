// End-to-end (#334): a student could paste a chatbot's answer into the
// answer of an exercise. Now, in the real app, with the real Windows
// clipboard:
//
// - text put on the clipboard outside the app does not reach the editor of
//   an exercise — Ctrl+V, Shift+Insert and Paste in the right-click menu —
//   nor the chat composer, nor the Playground's editor; a short neutral
//   notice says so;
// - what the student copies inside the app (the exercise's code in the
//   editor) pastes as before, and typing works as before;
// - the oefening's `turn_history` record carries how many pastes were
//   blocked and how many characters they held, never the text;
// - with `BlockExternalPaste: false` in the school's `config/global` every
//   paste goes through, and the record does not say (unknown, not 0).
//
// Real app, real navigation, real practice view, editor, composer and
// Playground, real TutorService writing the record to the in-memory Cosmos;
// only the model is scripted.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/paste_guard.dart -d windows

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/clipboard/in_app_clipboard.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _exercise = 'som = 1 + ___\nprint(som)';
const String _chatbot = 'som = 1 + 2\nprint(som)  # de som van twee getallen\n';
const String _notice = "Pasting from outside the app isn't possible here.";

Finder get _editable => find.descendant(
  of: find.byType(CodeField),
  matching: find.byType(EditableText),
);

Finder get _composerField => find.descendant(
  of: find.byType(ComposerIdle),
  matching: find.byType(TextField),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  CodeController editorController(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller;

  String composerText(WidgetTester tester) =>
      tester.widget<TextField>(_composerField).controller!.text;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await settle(tester);
  }

  Future<void> ctrlV(WidgetTester tester) =>
      chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyV);

  Future<void> ctrlC(WidgetTester tester) =>
      chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyC);

  Future<void> shiftInsert(WidgetTester tester) =>
      chord(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.insert);

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(
      tester.getCenter(finder),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await settle(tester);
  }

  /// Waits for the notice, then lets it go, so the next one is its own.
  Future<void> expectNotice(WidgetTester tester) async {
    await pumpUntilFound(tester, find.text(_notice));
    ScaffoldMessenger.of(tester.element(find.text(_notice)))
        .removeCurrentSnackBar();
    await pumpUntilGone(tester, find.text(_notice));
  }

  /// Puts [text] on the Windows clipboard as another program would: not
  /// through the app.
  Future<void> copyOutside(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  testWidgets('a paste from outside the app reaches neither the answer nor '
      'the chat; a copy made in the app pastes; the record counts the '
      'blocked pastes', (tester) async {
    InAppClipboard.instance.clear();
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Maak de som af.', code: _exercise),
      codeFeedbackReply(text: 'Juist.', quality: 'correct'),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () =>
          editorText(tester) == _exercise &&
          harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );

    // A chatbot's answer on the clipboard, copied outside the app.
    await copyOutside(_chatbot);
    await tester.tap(find.byType(CodeField));
    await tester.pump();

    // Ctrl+V, Shift+Insert, Paste in the right-click menu: the answer stays
    // what the student had, and the notice says so each time.
    await ctrlV(tester);
    expect(editorText(tester), _exercise);
    await expectNotice(tester);

    await shiftInsert(tester);
    expect(editorText(tester), _exercise);
    await expectNotice(tester);

    await rightClick(tester, find.byType(CodeField));
    await pumpUntilFound(tester, find.text('Paste'));
    expect(find.text('Select all'), findsOneWidget);
    // Nothing is selected: nothing to copy, as in a text field's own menu.
    expect(find.text('Copy'), findsNothing);
    await tester.tap(find.text('Paste'));
    await settle(tester);
    expect(editorText(tester), _exercise);
    await expectNotice(tester);
    expect(find.text('Select all'), findsNothing, reason: 'the menu closed');

    // The chat composer next to it: the same.
    await tester.tap(_composerField);
    await tester.pump();
    await ctrlV(tester);
    expect(composerText(tester), isEmpty);
    await expectNotice(tester);

    // Typing works as before.
    await tester.enterText(_composerField, 'Klopt dit?');
    await tester.pump();
    expect(composerText(tester), 'Klopt dit?');
    await tester.enterText(_composerField, '');
    await tester.pump();

    // A copy made in the app — the `print(som)` of the exercise, from the
    // editor — pastes, in the editor and in the chat, without a notice.
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    final controller = editorController(tester);
    final start = _exercise.indexOf('print(som)');
    controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + 'print(som)'.length,
    );
    await tester.pump();
    await ctrlC(tester);
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, 'print(som)');
    await tester.tap(_composerField);
    await tester.pump();
    await ctrlV(tester);
    await pumpUntil(
      tester,
      () => composerText(tester) == 'print(som)',
      reason: 'the copy from the editor did not paste in the chat',
    );
    await tester.enterText(_composerField, '');
    await tester.pump();

    // In the editor, on a new line typed after the code, the copied line
    // pastes again.
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    await tester.enterText(_editable, '$_exercise\n');
    await tester.pump();
    final typed = editorText(tester);
    expect(typed, startsWith(_exercise));
    controller.selection = TextSelection.collapsed(offset: typed.length);
    await tester.pump();
    await ctrlV(tester);
    await pumpUntil(
      tester,
      () => editorText(tester) == '${typed}print(som)',
      reason: 'the copy from the editor did not paste in the editor',
    );
    expect(find.text(_notice), findsNothing);

    // Handed in: the record counts the four blocked pastes and their
    // characters, and holds none of the pasted text.
    await tester.tap(find.byTooltip('Send to tutor'));
    final records = harness.cosmos['turn_history'].docs.values;
    await pumpUntil(
      tester,
      () => records.any((d) => d['uid'] == kStudentUid),
      timeout: const Duration(seconds: 30),
      reason: 'no turn_history record was written',
    );
    final record = records.singleWhere((d) => d['uid'] == kStudentUid);
    expect(record['blockedPastes'], 4);
    expect(record['blockedPasteChars'], 4 * _chatbot.length);
    expect(
      record.values.whereType<String>().any((v) => v.contains('de som van')),
      isFalse,
      reason: 'the pasted text was kept',
    );

    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });

  testWidgets('in the Playground a paste from outside the app is blocked too', (
    tester,
  ) async {
    InAppClipboard.instance.clear();
    final harness = AppHarness();
    await harness.boot(tester);

    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    final before = editorText(tester);

    await copyOutside(_chatbot);
    await ctrlV(tester);
    expect(editorText(tester), before);
    await expectNotice(tester);

    await rightClick(tester, find.byType(CodeField));
    await pumpUntilFound(tester, find.text('Paste'));
    await tester.tap(find.text('Paste'));
    await settle(tester);
    expect(editorText(tester), before);
    await expectNotice(tester);

    await harness.dispose(tester);
  });

  testWidgets('with BlockExternalPaste false in config/global every paste '
      'goes through, and the record does not say', (tester) async {
    InAppClipboard.instance.clear();
    final llm = ScriptedLlm([
      completeCodeReply(text: 'Maak de som af.', code: _exercise),
      codeFeedbackReply(text: 'Juist.', quality: 'correct'),
    ]);
    final harness = AppHarness(
      llm: llm,
      extraDocs: {
        'config': [
          {
            'id': 'global',
            'type': 'config',
            'Model': 'gpt-4o',
            'ApiKey': '',
            'BlockExternalPaste': false,
          },
        ],
      },
    );
    await harness.boot(tester);

    // The Playground first: a paste from outside goes in.
    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    final before = editorText(tester);
    await copyOutside('x = 1');
    await ctrlV(tester);
    await pumpUntil(
      tester,
      () => editorText(tester) != before,
      reason: 'the paste did not go through with the block off',
    );
    expect(editorText(tester), contains('x = 1'));

    // An exercise: the paste goes in, and the record does not say.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () =>
          editorText(tester) == _exercise &&
          harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
    final answer = _exercise.replaceFirst('___', '2');
    await copyOutside(answer);
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    await tester.enterText(_editable, '');
    await tester.pump();
    await ctrlV(tester);
    await pumpUntil(
      tester,
      () => editorText(tester).contains('som = 1 + 2'),
      reason: 'the paste did not go through with the block off',
    );
    expect(find.text(_notice), findsNothing);

    await tester.tap(find.byTooltip('Send to tutor'));
    final records = harness.cosmos['turn_history'].docs.values;
    await pumpUntil(
      tester,
      () => records.any((d) => d['uid'] == kStudentUid),
      timeout: const Duration(seconds: 30),
      reason: 'no turn_history record was written',
    );
    final record = records.singleWhere((d) => d['uid'] == kStudentUid);
    expect(record.containsKey('blockedPastes'), isFalse);
    expect(record.containsKey('blockedPasteChars'), isFalse);

    expect(llm.remaining, 0);
    await harness.dispose(tester);
  });
}
