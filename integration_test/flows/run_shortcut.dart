// End-to-end (#300): the Run button and the chat composer showed `⌘↵`, the
// Mac shortcut, in an app that ships on Windows only — and no key at all was
// bound to Run. In the real app on Windows, both hints now read `Ctrl+↵`;
// Ctrl+Enter in the editor runs the code (once, without typing a newline),
// and Ctrl+Enter in the composer beside it still sends the message without
// running anything. Only the whole page shows that the two bindings do not
// reach each other: the editor and the composer are on screen together.
//
// The Python host is faked (the app's real one needs the bundled
// interpreter); everything above it — the practice page, the editor with
// its own Enter binding, the run controls, the chat — is the real app.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/run_shortcut.dart -d windows

import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/student_bubble.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_py_runner.dart';
import '../harness/app_harness.dart';

const _code = 'print("hoi")';

Finder _composerField() => find.descendant(
  of: find.byType(ComposerIdle),
  matching: find.byType(TextField),
);

Future<void> _ctrlEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Ctrl+Enter runs the code in the editor and sends in the chat, '
      'and both hints say Ctrl', (tester) async {
    final pyRunner = FakePyRunner();
    final harness = AppHarness(pyRunner: pyRunner);
    await harness.boot(tester);
    addTearDown(pyRunner.dispose);

    // Practice: the editor and the chat composer on one page.
    await tester.tap(find.text('Practice'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntilFound(tester, find.byType(ComposerIdle));

    // Both hints name the Windows key.
    expect(
      tester.widget<Text>(find.byKey(const Key('run-shortcut-hint'))).data,
      'Ctrl+↵',
    );
    expect(
      find.descendant(
        of: find.byType(ComposerIdle),
        matching: find.text('Ctrl+↵'),
      ),
      findsOneWidget,
    );
    expect(find.text('⌘↵'), findsNothing);

    // Ctrl+Enter in the editor runs what is in it.
    final editor = harness.container.read(
      codeServiceProvider(SessionMode.practice),
    );
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    editor.setText(_code);
    await tester.pump();

    await _ctrlEnter(tester);
    await pumpUntilFound(tester, find.text('Stop'));
    expect(pyRunner.ran, [_code]);
    expect(editor.getText(), _code, reason: 'Ctrl+Enter is not a new line');

    // Again during the run: the button is Stop, and the key starts nothing.
    await _ctrlEnter(tester);
    expect(pyRunner.ran, hasLength(1));

    await tester.tap(find.text('Stop'));
    await pumpUntilFound(tester, find.text('Run'));

    // Ctrl+Enter in the composer sends the message, and runs no code.
    await tester.tap(_composerField());
    await tester.pump();
    await tester.enterText(_composerField(), 'mag ik een tip?');
    await tester.pump();
    await _ctrlEnter(tester);
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(StudentBubble),
        matching: find.textContaining('mag ik een tip?', findRichText: true),
      ),
    );
    expect(tester.widget<TextField>(_composerField()).controller!.text, '');
    expect(pyRunner.ran, hasLength(1), reason: 'the composer ran the code');
    expect(editor.getText(), _code);

    await harness.dispose(tester);
  });
}
