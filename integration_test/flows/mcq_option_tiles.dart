// End-to-end (#254): two faults in the options of a generated multiple-choice
// question, both from "Lijsten, strings en indexen".
//
// Two options with the same text. On a question about `tekst = "komeet"`
// options B and C were both `"omee\nt t\n"`, and that was the key: both
// tiles turned green. Now the options are compared as a tile shows them —
// whitespace at the end of a line and empty lines at the end do not show —
// before the handler shuffles them. A key that looks the same as a
// distractor makes the question unaskable: the app says so in chat and its
// one re-send fetches a new question. Distractors that look the same are
// merged into one tile.
//
// Backticks in the options. "Welke uitspraak over dit programma is juist?"
// had sentences with code in them (`m`, `IndexError`) as options, drawn as
// plain monospace text with the backticks on screen. Now such an option is a
// sentence in the app's font with the code as inline code, like the
// feedback under it, and an option without backticks stays monospace.
//
// Real app, real navigation, real quiz view in the real window and fonts,
// real option rows (`IntrinsicHeight`, which a paragraph with inline code in
// it has to lay out under). Only the model is scripted (`ScriptedLlm`), as
// raw assistant text through the production parser.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/mcq_option_tiles.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';

/// The question from #254: B and C the same text, and B the key.
const String _twinPrompt = 'Wat drukt dit programma af?';
const List<String> _twinOptions = [
  'omee\nt t\nkomeet',
  'omee\nt t\n',
  'omee\nt t\n',
  'omee\nt\n',
];

/// The question the re-send brings: a sentence with code in it as the key,
/// and two distractors that differ only in an empty line at the end.
const String _prompt = 'Welke uitspraak over dit programma is juist?';
const String _code =
    'letters = ["k", "o", "m"]\nprint(letters[2])\nprint(letters[3])';
const String _sentence =
    'Het programma drukt eerst `m` af en stopt dan met een `IndexError`.';
const String _output = 'm\nNone';
const String _outputTwin = 'm\nNone\n';
const String _other = 'k\no';
const String _feedback = 'Juist: index 3 bestaat niet in een lijst van drie.';

String _mcqReply({
  required String prompt,
  required String code,
  required List<String> options,
  required String letter,
}) => llmEnvelope(
  text: prompt,
  meta: jsonEncode({
    'type': 'multiple_choice',
    'code': code,
    'options': [
      for (final o in options) {'option': o},
    ],
    'correct': letter,
  }),
);

/// True when [style] explicitly disables both ligature features (#83).
bool _stripsLigatures(TextStyle? style) {
  final features = style?.fontFeatures;
  if (features == null) return false;
  bool disables(String tag) =>
      features.any((f) => f.feature == tag && f.value == 0);
  return disables('calt') && disables('liga');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final String mono = AppMono.code().fontFamily!;

  Finder inQuiz(Finder f) =>
      find.descendant(of: find.byType(QuizView), matching: f);

  /// The paragraph the sentence option is drawn in.
  RichText sentenceParagraph(WidgetTester tester) => tester
      .widgetList<RichText>(inQuiz(find.byType(RichText)))
      .firstWhere(
        (r) => r.text.toPlainText().startsWith('Het programma drukt eerst '),
      );

  /// The option rows — the `AnimatedContainer` around each letter badge.
  List<BoxDecoration> rows(WidgetTester tester) => [
    for (final badge in const ['A', 'B', 'C', 'D'])
      if (inQuiz(find.text(badge)).evaluate().isNotEmpty)
        tester
                .widget<AnimatedContainer>(
                  find
                      .ancestor(
                        of: inQuiz(find.text(badge)),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration,
  ];

  testWidgets('a question whose key looks the same as a distractor is asked '
      'again; options that look the same are one tile, and a sentence '
      'option shows its code as inline code', (tester) async {
    final llm = ScriptedLlm([
      _mcqReply(
        prompt: _twinPrompt,
        code: 'tekst = "komeet"\nprint(tekst[1:5])\nprint(tekst[2:2])',
        options: _twinOptions,
        letter: 'B',
      ),
      _mcqReply(
        prompt: _prompt,
        code: _code,
        options: const [_sentence, _output, _outputTwin, _other],
        letter: 'A',
      ),
      llmEnvelope(
        text: _feedback,
        meta: jsonEncode({
          'type': 'mcq_feedback',
          'overallQuality': 'correct',
          'loSignals': <Object>[],
        }),
      ),
    ]);
    final harness = AppHarness(llm: llm);
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));

    // "Try it yourself" mounts the practice view, whose exercise request
    // plays the scripted questions.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntil(
      tester,
      () => harness.container.read(activeMcqProvider)?.prompt == _prompt,
      timeout: const Duration(seconds: 30),
      reason: 'the question with the twin key was put in front of the student',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    await tester.pump(AppDurations.hover);

    // The first question was refused and the re-send asked for a new one.
    expect(llm.sends, 1);
    expect(llm.resends, 1);
    expect(find.textContaining('komeet', findRichText: true), findsNothing);

    // And the chat — hidden while the quiz is up — says why, once.
    final notices = harness.container
        .read(chatServiceProvider)
        .controller
        .messages
        .whereType<SystemMessage>()
        .map((m) => ChatNotice.fromJson(m.metadata?[ChatNotice.metadataKey]))
        .nonNulls
        .where((n) => n.kind == ChatNoticeKind.optionsLookAlike);
    expect(notices, hasLength(1));

    // Three tiles: the two outputs that differ only in an empty line at the
    // end are one.
    expect(harness.container.read(activeMcqProvider)!.options, hasLength(3));
    expect(rows(tester), hasLength(3));
    expect(inQuiz(find.text('D')), findsNothing);
    expect(inQuiz(find.text(_output)), findsOneWidget);
    expect(inQuiz(find.text(_outputTwin)), findsNothing);

    // An option without backticks is output: monospace, without ligatures.
    for (final option in const [_output, _other]) {
      final style = tester.widget<Text>(inQuiz(find.text(option))).style;
      expect(style?.fontFamily, mono, reason: '"$option" is not monospace');
      expect(_stripsLigatures(style), isTrue);
    }

    // The sentence: no backticks on screen, the app's own font, and its
    // code as inline code chips in the code font.
    expect(
      inQuiz(find.textContaining('`', findRichText: true)),
      findsNothing,
      reason: 'the backticks of the option are on screen',
    );
    final sentence = sentenceParagraph(tester);
    expect(sentence.text.toPlainText(), contains(' af en stopt dan met een '));
    final body = Theme.of(tester.element(find.byType(QuizView)))
        .textTheme
        .bodyMedium!
        .fontFamily;
    expect(sentence.text.style?.fontFamily, body);
    expect(sentence.text.style?.fontFamily, isNot(mono));
    for (final code in const ['m', 'IndexError']) {
      final chip = inQuiz(find.text(code));
      expect(chip, findsOneWidget, reason: 'no inline code for `$code`');
      final style = tester.widget<Text>(chip).style;
      expect(style?.fontFamily, mono, reason: '`$code` is not in code font');
      expect(_stripsLigatures(style), isTrue);
    }
    // Laid out in the real window: the chips sit inside the sentence's tile.
    final tile = find.ancestor(
      of: find.byWidget(sentence),
      matching: find.byType(AnimatedContainer),
    );
    final tileRect = tester.getRect(tile.first);
    for (final code in const ['m', 'IndexError']) {
      final chipRect = tester.getRect(inQuiz(find.text(code)));
      expect(
        tileRect.contains(chipRect.topLeft) &&
            tileRect.contains(chipRect.bottomRight),
        isTrue,
        reason: '`$code` is drawn outside its tile',
      );
    }

    // The sentence tile is picked like any other, and only it is tinted.
    await tester.tap(find.byWidget(sentence));
    await pumpUntilFound(
      tester,
      find.textContaining('index 3 bestaat niet', findRichText: true),
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    await tester.pump(AppDurations.hover);
    await tester.pump();

    expect(harness.container.read(activeMcqProvider)?.selected, _sentence);
    expect(llm.remaining, 0);
    // The grading call is told the key as the text on the tile.
    final grading = jsonDecode(llm.sentInputs.last) as Map<String, dynamic>;
    expect(grading['correct_option'], _sentence);
    final tinted = rows(tester)
        .where((d) => (d.border! as Border).top.color != AppColors.ink2);
    expect(tinted, hasLength(1), reason: 'more than one tile looks picked');

    await harness.dispose(tester);
  });
}
