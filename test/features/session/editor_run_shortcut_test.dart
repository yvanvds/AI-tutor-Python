// Issue #300 — the Run button showed a key hint, but no key was bound to
// Run. Ctrl+Enter (Cmd+Enter on a Mac) in the editor now runs the code, as
// the button does: once, without the newline a plain Enter types, and not
// again while the run is going (the button is Stop then).
//
// The real `Editor` (the package's `CodeField` with its own Enter binding)
// over a scripted Python host. The hint on the button is
// `test/widgets/submit_shortcut_test.dart`; the end-to-end run, with the chat
// composer beside the editor, is `integration_test/flows/run_shortcut.dart`.

import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../helpers/fake_py_runner.dart';
import '../../helpers/localization.dart';

const _code = 'print("hoi")';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakePyRunner py;
  late OutputService output;

  setUp(() {
    py = FakePyRunner();
    output = OutputService(pyRunner: py, localizations: testLocalizations());
  });

  tearDown(() => py.dispose());

  /// The editor of [mode], focused, holding [_code] with the caret at the
  /// end.
  Future<CodeService> mount(WidgetTester tester, SessionMode mode) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pc = ProviderContainer(
      overrides: [
        modeProvider.overrideWith((_) => mode),
        outputServiceProvider.overrideWithValue(output),
      ],
    );
    addTearDown(pc.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Editor()),
        ),
      ),
    );
    final code = pc.read(codeServiceProvider(mode));
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    code.setText(_code);
    await tester.pump();
    return code;
  }

  /// Lets the editor's 500 ms analysis debounce, started by every edit,
  /// run out before the test ends.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  Future<void> press(WidgetTester tester, LogicalKeyboardKey modifier) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets('Ctrl+Enter runs the code once, without typing a newline', (
    tester,
  ) async {
    final code = await mount(tester, SessionMode.practice);

    await press(tester, LogicalKeyboardKey.controlLeft);

    expect(py.ran, [_code]);
    expect(output.isRunning.value, isTrue);
    expect(code.getText(), _code, reason: 'Ctrl+Enter is not a new line');

    // Pressed again during the run: the button is Stop now, and the key
    // does not start a second run either.
    await press(tester, LogicalKeyboardKey.controlLeft);
    expect(py.ran, [_code]);

    await output.stop();
    await settle(tester);
  });

  testWidgets('Cmd+Enter runs the code too', (tester) async {
    await mount(tester, SessionMode.practice);

    await press(tester, LogicalKeyboardKey.metaLeft);

    expect(py.ran, [_code]);
    await output.stop();
    await settle(tester);
  });

  testWidgets('runs the playground buffer in the playground', (tester) async {
    await mount(tester, SessionMode.playground);

    await press(tester, LogicalKeyboardKey.controlLeft);

    expect(py.ran, [_code]);
    await output.stop();
    await settle(tester);
  });

  testWidgets('a plain Enter is still a new line, and runs nothing', (
    tester,
  ) async {
    final code = await mount(tester, SessionMode.practice);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(code.getText(), '$_code\n');
    expect(py.ran, isEmpty);
    await settle(tester);
  });
}
