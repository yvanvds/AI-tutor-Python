// End-to-end (#147): the model hands the tutor an exercise whose prose has
// one word replaced by a run of non-Latin lookalikes — the reply from bug
// report #147, seen while a nano-class model was the per-device override.
// The student must never be left looking at it. The app refuses the reply,
// says so in chat, and its existing one re-send brings back a clean one,
// which is what stands in the chat and the editor when the turn settles.
//
// Real app, real navigation, real practice view, real editor, real chat
// rendering. Only the model is scripted (`ScriptedLlm`), and even that as
// raw assistant text, so the envelope assembly, the script guard and the
// withdrawal of the half-streamed message are the production ones.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/garbled_reply_retry.dart -d windows

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

/// The garbled word, in the Armenian block the glyphs on #147 were described
/// as. Dropped into otherwise normal Dutch, exactly as reported.
const String kGarbledWord = 'աբգդե';

const String kGarbledPrompt =
    'Vul de ontbrekende $kGarbledWord in: de naam moet in de variabele '
    'staan voordat je ze afdrukt.';

const String kCleanPrompt =
    'Vul de ontbrekende invoer in: de naam moet in de variabele staan '
    'voordat je ze afdrukt.';

const String kExercise = 'voornaam = ___\nprint("Welkom, " + voornaam + "!")';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ScriptedLlm llm;
  late AppHarness harness;

  setUp(() {
    llm = ScriptedLlm([
      completeCodeReply(text: kGarbledPrompt, code: kExercise),
      completeCodeReply(text: kCleanPrompt, code: kExercise),
    ]);
    harness = AppHarness(llm: llm);
  });

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  testWidgets('a reply with a run of characters from another alphabet is '
      'refused and the re-send reaches the student instead', (tester) async {
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    // "Try it yourself" opens the practice editor, which asks the tutor for
    // an exercise on mount — the turn that came back garbled on #147.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));

    // Both scripted replies are consumed: the first was refused, the app
    // re-sent, and the second was accepted.
    await pumpUntil(
      tester,
      () => llm.remaining == 0,
      timeout: const Duration(seconds: 30),
      reason: 'the app never asked for a replacement reply',
    );
    await pumpUntil(
      tester,
      () => editorText(tester).contains('___'),
      timeout: const Duration(seconds: 30),
      reason: 'the replacement exercise never reached the editor',
    );

    expect(llm.sends, 1);
    expect(llm.resends, 1);

    // The garbled prose is nowhere on screen — not as a finished message and
    // not as the half-streamed placeholder it arrived in.
    expect(
      find.textContaining(kGarbledWord, findRichText: true),
      findsNothing,
      reason: 'the garbled reply survived the turn',
    );
    expect(
      find.textContaining(kGarbledPrompt, findRichText: true),
      findsNothing,
    );

    // What the student reads is the clean re-send, on the same exercise.
    expect(find.textContaining(kCleanPrompt, findRichText: true), findsWidgets);
    expect(editorText(tester), kExercise);

    // And they were told why, once, in their language.
    expect(
      pills(tester).where((p) => p.contains('came back garbled')),
      hasLength(1),
      reason: 'no pill explained the refused reply',
    );

    await harness.dispose(tester);
  });
}
