// End-to-end (#183): what an exercise cost, from the wire to the teacher.
//
// Every chat.completions response carries a `usage` block, and the connector
// used to drop it: the cost of an exercise could only be estimated. Now the
// connector reads it — the cached share of the input too, which
// `dart_openai` does not parse — a streamed call asks for it
// (`stream_options.include_usage`), the tutor adds an exercise's calls up
// and writes the sum on its turn record, and the Students page adds the
// records up per class for the last 7 and 30 days.
//
// One flow, as the teacher: they practise an exercise themselves, so the
// app writes a turn record of its own through the production connectors —
// only the socket underneath is scripted (`AppHarness.openaiClient`) —
// then they open the Students page, where the card adds that record up with
// the students' seeded ones.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/token_usage.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_openai.dart';
import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _first = 'print(___)';
const String _second = 'naam = ___\nprint(naam)';

/// The card row of the accounts without a class — the teacher's own.
const Key _noClassRow = Key('token-usage-row-');

Map<String, dynamic> _student(String uid, String className) => {
  'id': uid,
  'uid': uid,
  'email': '$uid@example.com',
  'firstName': uid,
  'lastName': 'Student',
  'targetGoal': '',
  'mayUseGlobalKey': true,
  'createdAt': '2026-05-02T10:00:00Z',
  'updatedAt': '2026-05-02T10:00:00Z',
  'className': className,
};

/// A graded turn as a client writes it; [usage] is the #183 block, left
/// out the way a build from before it leaves it out.
Map<String, dynamic> _turn(
  String id,
  String uid,
  DateTime at, {
  Map<String, dynamic>? usage,
}) => {
  'id': id,
  'type': 'turn_history',
  'uid': uid,
  'turnAt': at.toUtc().toIso8601String(),
  'subgoalId': 's1',
  'targetLOIds': const ['lo-print'],
  'questionType': 'completeCodeQuestion',
  'difficulty': 'medium',
  'isFollowUp': false,
  'chainDepth': 0,
  'overallQuality': 'correct',
  'loSignals': const [],
  'hadFallback': false,
  'appliedSignals': const [],
  'provenance': 'home',
  'calibrationBefore': 'medium',
  'calibrationAfter': 'medium',
  'subgoalProgressAfter': 0.2,
  'loStatusAfter': const [],
  'subgoalAdvanced': false,
  if (usage != null) 'usage': usage,
};

Map<String, int> _tokens(int prompt, int cached, int completion) => {
  'promptTokens': prompt,
  'cachedTokens': cached,
  'completionTokens': completion,
};

/// A record's usage block: the sum on top, one kind of call under it.
Map<String, dynamic> _usage(int prompt, int cached, int completion) => {
  'model': 'gpt-4o',
  ..._tokens(prompt, cached, completion),
  'byCall': {'grading': _tokens(prompt, cached, completion)},
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Future<void> waitForExercise(
    WidgetTester tester,
    AppHarness harness,
    String exercise,
  ) => pumpUntil(
    tester,
    () =>
        editorText(tester) == exercise &&
        harness.container.read(tutorServiceProvider) == TutorState.idle,
    timeout: const Duration(seconds: 30),
    reason: 'exercise "$exercise" never reached the editor',
  );

  /// The texts of one card row, left to right: the class, then input,
  /// cached and output for 7 days, then the same for 30.
  List<String?> row(WidgetTester tester, Key key) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)),
      )
      .map((t) => t.data)
      .toList();

  testWidgets('an exercise writes what its calls cost on its turn record, '
      'and the Students page adds it up per class', (tester) async {
    // What the model answers, and what each answer reports it cost: the
    // question, the grade, and the next question the grade asks for.
    final script = [
      (
        completeCodeReply(text: 'Toon een groet.', code: _first),
        FakeOpenAi.usageBlock(prompt: 1200, completion: 150, cached: 1024),
      ),
      (
        codeFeedbackReply(
          text: 'Bijna: vergeet de tekst niet.',
          quality: 'partial',
        ),
        FakeOpenAi.usageBlock(prompt: 1500, completion: 300, cached: 1024),
      ),
      (
        completeCodeReply(text: 'Toon je naam.', code: _second),
        FakeOpenAi.usageBlock(prompt: 1300, completion: 160, cached: 1152),
      ),
    ];
    final openai = FakeOpenAi();
    openai.answer = (req) {
      final n = openai.requests.length - 1;
      if (n >= script.length) {
        return FakeOpenAi.apiError('unscripted request #$n', status: 500);
      }
      return FakeOpenAi.reply(req, script[n].$1, usage: script[n].$2);
    };

    final now = DateTime.now().toUtc();
    DateTime daysAgo(int d) => now.subtract(Duration(days: d));
    final harness = AppHarness(
      identity: teacherIdentity,
      openaiClient: openai.client,
      extraDocs: {
        'accounts': [
          _student('it-anna', '5A'),
          _student('it-ben', '5A'),
          _student('it-cara', '5B'),
        ],
        'turn_history': [
          _turn(
            't-anna',
            'it-anna',
            daysAgo(2),
            usage: _usage(5000, 3000, 700),
          ),
          _turn('t-ben', 'it-ben', daysAgo(10), usage: _usage(4000, 0, 500)),
          _turn(
            't-cara',
            'it-cara',
            daysAgo(3),
            usage: _usage(2100, 1000, 250),
          ),
          // Too old for the card.
          _turn(
            't-anna-old',
            'it-anna',
            daysAgo(40),
            usage: _usage(99999, 0, 9999),
          ),
          // Written before #183: nothing to add.
          _turn('t-cara-legacy', 'it-cara', daysAgo(1)),
        ],
      },
    );
    await harness.boot(tester);

    // The teacher practises: a question, their answer graded, the next
    // question.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(tester, harness, _first);
    await tester.tap(find.byTooltip('Send to tutor'));
    await waitForExercise(tester, harness, _second);
    expect(openai.requests, hasLength(3));

    // Every call streamed, and every stream asked for its usage chunk.
    for (final req in openai.requests) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['stream_options'], {'include_usage': true});
    }

    // The graded turn carries the question and the grade — the cached
    // share included — and not the next question, asked after it.
    final turns = harness.cosmos['turn_history'].docs.values;
    Iterable<Map<String, dynamic>> ownTurns() =>
        turns.where((d) => d['uid'] == teacherIdentity.oid);
    await pumpUntil(
      tester,
      () => ownTurns().isNotEmpty,
      reason: 'the graded turn was never written',
    );
    expect(ownTurns().single['usage'], {
      'model': 'gpt-4o',
      ..._tokens(2700, 2048, 450),
      'byCall': {
        'question': _tokens(1200, 1024, 150),
        'grading': _tokens(1500, 1024, 300),
      },
    });

    // The Students page: the card's header has the 30-day total.
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    // 5A 9000 + 1200, 5B 2100 + 250, the teacher 2700 + 450.
    await pumpUntilFound(
      tester,
      find.text('15,700 tokens in the last 30 days'),
    );

    // Opened: one row per class, the teacher's own under "No class". Input
    // leaves out what came from the cache.
    await tester.tap(find.byKey(const Key('token-usage-toggle')));
    await pumpUntilFound(tester, find.byKey(_noClassRow));
    expect(row(tester, const Key('token-usage-row-5A')), [
      '5A',
      '2,000', '3,000', '700', // 7 days: Anna
      '6,000', '3,000', '1,200', // 30 days: Anna and Ben
    ]);
    expect(row(tester, const Key('token-usage-row-5B')), [
      '5B',
      '1,100',
      '1,000',
      '250',
      '1,100',
      '1,000',
      '250',
    ]);
    expect(row(tester, _noClassRow), [
      'No class',
      '652',
      '2,048',
      '450',
      '652',
      '2,048',
      '450',
    ]);

    // And the student list is still there, under it.
    expect(find.text('it-cara@example.com'), findsOneWidget);

    await harness.dispose(tester);
  });
}
