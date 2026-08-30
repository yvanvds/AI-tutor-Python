// End-to-end (#28, fixing #51): in the real app, a turtle program used to
// run completely silently — the Run button turned into Stop, a Tk window
// floated over the app, and the output panel stayed blank for the whole run
// and stayed blank after Stop. This drives Playground → Run → Stop and reads
// the panel the student reads.
//
// The Python host is faked here (the app's real one needs the bundled
// interpreter, and a real turtle run would open an OS window and block on
// `turtle.done()`); everything above it — run controls, OutputService, the
// output panel, localization — is the real app.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/turtle_run_notice.dart -d windows

import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/widgets/output_panel.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_py_runner.dart';
import '../harness/app_harness.dart';

const _turtleCode =
    'import turtle\n'
    'turtle.forward(100)\n'
    'turtle.done()\n';

const _plainCode = 'print("hello")\n';

Finder _inPanel(String text) => find.descendant(
  of: find.byType(OutputPanel),
  matching: find.textContaining(text, findRichText: true),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Playground -> a turtle run explains itself, and Stop says so', (
    tester,
  ) async {
    final pyRunner = FakePyRunner();
    final harness = AppHarness(pyRunner: pyRunner);
    await harness.boot(tester);
    addTearDown(pyRunner.dispose);

    await tester.tap(find.text('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));

    final editor = harness.container.read(
      codeServiceProvider(SessionMode.playground),
    );

    // A plain program is not narrated — the notice is turtle-specific.
    editor.setText(_plainCode);
    await tester.pump();
    await tester.tap(find.text('Run'));
    await pumpUntilFound(tester, find.text('Stop'));
    expect(_inPanel('turtle window'), findsNothing);
    await tester.tap(find.text('Stop'));
    await pumpUntilFound(tester, _inPanel('Stopped.'));
    await pumpUntilFound(tester, find.text('Run'));

    // The turtle run: the panel used to stay blank for its whole length.
    editor.setText(_turtleCode);
    await tester.pump();
    await tester.tap(find.text('Run'));

    await pumpUntilFound(tester, _inPanel('A turtle window is open.'));
    expect(_inPanel('press Stop, to finish the run'), findsOneWidget);
    // Still running: turtle.done() blocks until the window is closed, so the
    // notice has to be readable while the run sits there.
    expect(find.text('Stop'), findsOneWidget);
    expect(pyRunner.lastHandle.cancelled, isFalse);

    await tester.tap(find.text('Stop'));

    await pumpUntilFound(tester, _inPanel('Stopped.'));
    expect(_inPanel('A turtle window is open.'), findsOneWidget);
    expect(pyRunner.lastHandle.cancelled, isTrue);
    await pumpUntilFound(tester, find.text('Run'));

    await harness.dispose(tester);
  });
}
