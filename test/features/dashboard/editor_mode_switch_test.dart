// #322 — Practice and Playground each have their own editor buffer, and the
// session view fades one mode's page out while the next fades in
// (`SessionView`'s AnimatedSwitcher, mirrored here): for that moment both
// editors are mounted. These check that the dropdown after a dot belongs to
// the editor it was opened in — the fading editor keeps its own buffer, the
// dropdown closes when its page goes, and coming back to the page and
// pressing Enter writes a new line instead of a member from a dropdown that
// is no longer on screen.

import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _turtleCode = 'import turtle\nt = turtle.Turtle()\n';

/// The session view's mode switch, editor pages only: the page of the mode
/// in a KeyedSubtree, faded by an AnimatedSwitcher as `SessionView` does.
class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);
    return AnimatedSwitcher(
      duration: AppDurations.modeSwap,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(
        key: ValueKey(mode),
        child: mode == SessionMode.explain
            ? const SizedBox.expand()
            : const Editor(),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late ProviderContainer container;

  CodeController controllerOf(SessionMode mode) =>
      container.read(codeServiceProvider(mode)).controller;

  List<String> dropdown(SessionMode mode) {
    final popup = controllerOf(mode).popupController;
    return popup.shouldShow ? popup.suggestions : const [];
  }

  Future<void> mount(WidgetTester tester, SessionMode mode) async {
    container = ProviderContainer();
    container.read(modeProvider.notifier).state = mode;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: _ModeSwitch())),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  Future<void> switchTo(WidgetTester tester, SessionMode mode) async {
    container.read(modeProvider.notifier).state = mode;
    await tester.pump();
  }

  /// Puts [code] in [mode]'s buffer, caret at the end, then types [typed]
  /// key by key into the one editor on screen.
  Future<void> type(
    WidgetTester tester,
    SessionMode mode,
    String code,
    String typed,
  ) async {
    final controller = controllerOf(mode);
    controller.fullText = code;
    controller.selection = TextSelection.collapsed(offset: code.length);
    await tester.pump();
    final editable = find.descendant(
      of: find.byType(CodeField),
      matching: find.byType(EditableText),
    );
    for (var k = 1; k <= typed.length; k++) {
      await tester.enterText(editable, code + typed.substring(0, k));
      await tester.pump();
    }
  }

  testWidgets('while both pages are mounted, each editor keeps its own '
      'buffer and only one dropdown is open', (tester) async {
    await mount(tester, SessionMode.playground);
    await type(tester, SessionMode.playground, _turtleCode, 't.');
    expect(dropdown(SessionMode.playground), contains('forward(distance)'));

    await switchTo(tester, SessionMode.practice);
    // Mid-fade: the playground page is still there, fading out.
    final fields = tester.widgetList<CodeField>(find.byType(CodeField));
    expect(fields, hasLength(2));
    expect(
      fields.map((f) => f.controller).toSet(),
      {
        controllerOf(SessionMode.playground),
        controllerOf(SessionMode.practice),
      },
      reason:
          'the fading playground editor must not take over the practice '
          'buffer (and its dropdown)',
    );
    expect(
      dropdown(SessionMode.playground),
      isEmpty,
      reason: 'the playground dropdown closes when its page goes',
    );
    expect(find.text('forward(distance)'), findsNothing);

    await tester.pump(AppDurations.modeSwap * 2);
    expect(find.byType(CodeField), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('back on the page, Enter writes a new line, not a member from '
      'a dropdown that is no longer shown', (tester) async {
    await mount(tester, SessionMode.playground);
    await type(tester, SessionMode.playground, _turtleCode, 't.');
    expect(dropdown(SessionMode.playground), isNotEmpty);

    await switchTo(tester, SessionMode.practice);
    await tester.pump(AppDurations.modeSwap * 2);
    await switchTo(tester, SessionMode.playground);
    await tester.pump(AppDurations.modeSwap * 2);
    expect(find.text('forward(distance)'), findsNothing);

    // The student gives the editor the keyboard again without moving the
    // caret (Tab from the controls above does that; a click that lands on
    // the same spot can too) and starts a new line.
    await tester.showKeyboard(
      find.descendant(
        of: find.byType(CodeField),
        matching: find.byType(EditableText),
      ),
    );
    await tester.pump();
    final controller = controllerOf(SessionMode.playground);
    expect(controller.selection.baseOffset, '${_turtleCode}t.'.length);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.fullText, startsWith('${_turtleCode}t.\n'));
    expect(controller.fullText, isNot(contains('backward')));
    await unmount(tester);
  });

  testWidgets('an editor that leaves the screen without a mode switch closes '
      'its dropdown too', (tester) async {
    // In Practice a multiple-choice question takes the editor's place
    // without the mode changing; here the page is simply swapped out.
    await mount(tester, SessionMode.practice);
    await type(tester, SessionMode.practice, _turtleCode, 't.');
    expect(dropdown(SessionMode.practice), isNotEmpty);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.expand())),
      ),
    );
    await tester.pump();
    expect(dropdown(SessionMode.practice), isEmpty);
    await unmount(tester);
  });
}
