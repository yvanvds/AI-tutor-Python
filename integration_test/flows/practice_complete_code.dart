// End-to-end (#78): the model hands the tutor a `complete_code` exercise with
// nothing removed — the finished three-line program from bug report #77. The
// student must never see it. The app rejects the response, says so in chat,
// and its existing retry brings back a real exercise, which is what lands in
// the editor.
//
// Real app, real navigation, real practice view, real editor. Only the model
// is scripted (`ScriptedLlm`), and even that is scripted as raw assistant
// text so the envelope parsing and the rejection are the production ones.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/practice_complete_code.dart -d windows

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

/// Verbatim from the payload attached to #77: three finished lines, no gap.
const String kNoBlank =
    'voornaam = input("Voer uw voornaam in: ")\n'
    'achternaam = input("Voer uw achternaam in: ")\n'
    'print("Hallo, " + voornaam + " " + achternaam)';

/// A real code-completion exercise, shaped like the good turn on #73.
const String kWithBlank = 'voornaam = ___\nprint("Welkom, " + voornaam + "!")';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedLlm llm;
  late AppHarness harness;

  setUp(() {
    llm = ScriptedLlm([
      completeCodeReply(text: 'Vul het ontbrekende stuk in.', code: kNoBlank),
      completeCodeReply(
        text: 'Vul de ontbrekende invoer in.',
        code: kWithBlank,
      ),
    ]);
    harness = AppHarness(llm: llm);
  });

  /// The text actually rendered in the practice editor.
  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  testWidgets('a complete_code exercise with nothing to fill in is refused '
      'and the retry reaches the student instead', (tester) async {
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    // "Try it yourself" opens the practice editor, which asks the tutor for
    // an exercise on mount — the request that produced #77.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    // Both scripted replies are consumed: the first was refused, the app
    // retried, and the second was accepted.
    await pumpUntil(
      tester,
      () => llm.remaining == 0,
      timeout: const Duration(seconds: 30),
      reason: 'the app never asked for a replacement exercise',
    );
    await pumpUntil(
      tester,
      () => editorText(tester).contains('___'),
      timeout: const Duration(seconds: 30),
      reason: 'the replacement exercise never reached the editor',
    );

    expect(llm.sends, 1);
    expect(llm.resends, 1);

    // The finished program never made it into the editor.
    final shown = editorText(tester);
    expect(shown, kWithBlank);
    expect(shown, isNot(contains('achternaam')));

    // The student was told why, in their language, and the refused prompt was
    // withdrawn from the chat rather than left standing above a good exercise.
    expect(
      pills(tester),
      contains(contains('nothing left to fill in')),
      reason: 'no pill explained the refused exercise',
    );
    expect(
      find.textContaining('Vul het ontbrekende stuk in.', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Vul de ontbrekende invoer in.', findRichText: true),
      findsWidgets,
    );

    await harness.dispose(tester);
  });
}
