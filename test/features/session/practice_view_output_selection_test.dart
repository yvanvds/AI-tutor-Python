// Issue #17 — the output panel must let the student select a range that
// spans several lines (a stack trace, a table) so they can copy it or ask
// the tutor about it. Before the fix every line was its own `SelectableText`
// inside a `ListView`, so a selection could never cross a line boundary.
//
// This mounts the real `PracticeView` (run controls, code editor, split view
// and output panel) over a real `OutputService` whose `PyRunner` is never
// started — lines are seeded straight into `OutputService.lines`, exactly as
// a finished run would leave them. The selection is driven with a mouse drag
// through the real gesture pipeline, and the assertion reads back what the
// panel's `EditableText` reports as selected.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo (#28).

import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/widgets/output_panel.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:py_runner/py_runner.dart';

import '../../helpers/localization.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> requestExercise() async {}

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _traceback = [
  'Traceback (most recent call last):',
  '  File "<stdin>", line 3, in <module>',
  'ZeroDivisionError: division by zero',
];

void main() {
  late OutputService output;
  late ChatService chat;

  setUp(() {
    output = OutputService(
      pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
      localizations: testLocalizations(),
    );
    chat = ChatService();
  });

  tearDown(() {
    chat.dispose();
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      tutorServiceProvider.overrideWith(() => _FakeTutorService()),
      outputServiceProvider.overrideWithValue(output),
      chatServiceProvider.overrideWithValue(chat),
      modeProvider.overrideWith((_) => SessionMode.practice),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PracticeView(showObjective: false)),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Finder outputEditable() => find.descendant(
    of: find.byType(OutputPanel),
    matching: find.byType(EditableText),
  );

  /// Global centre of the caret rect at [offset] in the output text.
  Offset caretAt(WidgetTester tester, int offset) {
    final state = tester.state<EditableTextState>(outputEditable());
    final rect = state.renderEditable.getLocalRectForCaret(
      TextPosition(offset: offset),
    );
    return state.renderEditable.localToGlobal(rect.center);
  }

  testWidgets('a mouse drag selects a range spanning several output lines', (
    tester,
  ) async {
    await mount(tester);

    output.lines.value = [
      const OutputLine('hello'),
      for (final l in _traceback) OutputLine(l, isError: true),
    ];
    await tester.pump();
    await tester.pump();

    // Every line is visible, and the whole output is one selectable.
    for (final l in _traceback) {
      expect(find.textContaining(l, findRichText: true), findsOneWidget);
    }
    expect(outputEditable(), findsOneWidget);

    final fullText = tester
        .state<EditableTextState>(outputEditable())
        .textEditingValue
        .text;
    final start = fullText.indexOf(_traceback.first);
    final end = fullText.indexOf(_traceback.last) + _traceback.last.length;

    final gesture = await tester.startGesture(
      caretAt(tester, start),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(caretAt(tester, end));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final value = tester
        .state<EditableTextState>(outputEditable())
        .textEditingValue;
    final selected = value.selection.textInside(value.text);
    expect(selected, _traceback.join('\n'));

    await unmount(tester);
  });

  testWidgets('select-all covers every output line', (tester) async {
    await mount(tester);

    output.lines.value = [
      const OutputLine('a'),
      const OutputLine('b'),
      const OutputLine('c'),
    ];
    await tester.pump();
    await tester.pump();

    final state = tester.state<EditableTextState>(outputEditable());
    state.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();

    final value = state.textEditingValue;
    expect(value.selection.textInside(value.text), 'a\nb\nc');

    await unmount(tester);
  });
}
