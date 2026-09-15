// End-to-end (#122): a student can switch to Playground while a quiz (MCQ)
// question is on screen. Before the fix the mode pill did flip the mode, but
// `PlaygroundView` reuses `PracticeView`, which rendered the pending MCQ in
// *every* mode — so the student saw the same quiz under a playground header
// and concluded the switch was blocked. The real app renders the quiz (real
// navigation, real top bar, real mode swap), the switch is driven through
// the real mode pill, and the quiz must be parked, not dropped: it comes
// back on return to Practice.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/playground_during_mcq.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

/// The question the student reads. The parser takes the MCQ prompt from the
/// envelope's TEXT part (`ai_response_parser.dart`), so this is what the
/// scripted turn's `text` must carry.
const String _prompt = 'What does this code print?';
const String _optionA = '2';
const String _optionB = '11';

/// The prompt is rendered through `TutorMarkdown` (a `RichText`), so a plain
/// `find.text` never sees it. A fresh finder per call: a reused instance
/// caches elements that the mode swap has since unmounted.
Finder _promptFinder() => find.textContaining(_prompt, findRichText: true);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppHarness harness;

  setUp(() {
    harness = AppHarness(
      llm: ScriptedLlm([
        llmEnvelope(
          text: _prompt,
          meta: jsonEncode({
            'type': 'multiple_choice',
            'prompt': _prompt,
            'code': 'print(1 + 1)',
            'options': [
              {'option': _optionA},
              {'option': _optionB},
            ],
          }),
        ),
      ]),
    );
  });

  testWidgets(
    'Playground opens while an MCQ is pending; the MCQ is back on return',
    (tester) async {
      await harness.boot(tester);

      await tester.tap(find.byTooltip('Learning path'));
      await pumpUntilFound(tester, find.byType(LeerpadPage));
      await tester.tap(find.text('Continue'));
      await pumpUntilFound(tester, find.byType(ExplainView));

      // "Try it yourself" mounts the practice view, whose exercise request
      // plays the scripted multiple_choice turn and opens the quiz render.
      await tester.tap(find.text('Try it yourself'));
      await pumpUntilFound(tester, find.byType(QuizView));
      await pumpUntilFound(tester, _promptFinder());
      expect(find.byType(Editor), findsNothing);

      // The switch the student could not make.
      await tester.tap(find.text('Playground'));
      await pumpUntilFound(tester, find.byType(PlaygroundView));
      await pumpUntilGone(tester, find.byType(QuizView));

      expect(harness.container.read(modeProvider), SessionMode.playground);
      expect(
        find.byType(Editor),
        findsOneWidget,
        reason: 'Playground must show the code editor, not the quiz',
      );
      expect(
        harness.container.read(activeMcqProvider),
        isNotNull,
        reason: 'the MCQ must stay pending while the student is in Playground',
      );

      // Back to Practice: the same question, still unanswered.
      await tester.tap(find.text('Practice'));
      await pumpUntilFound(tester, find.byType(QuizView));
      await pumpUntilGone(tester, find.byType(PlaygroundView));

      expect(harness.container.read(modeProvider), SessionMode.practice);
      await pumpUntilFound(tester, _promptFinder());
      expect(find.text(_optionA), findsOneWidget);
      expect(find.text(_optionB), findsOneWidget);
      expect(harness.container.read(activeMcqProvider)?.selected, isNull);
      expect(find.byType(Editor), findsNothing);

      await harness.dispose(tester);
    },
  );
}
