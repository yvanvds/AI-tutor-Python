// End-to-end (#229): a student who has worked on "Print" for half an hour
// without progress, with every answer wrong, answers wrong once more — the
// app writes a strong `noProgress` event to `turn_history`, and the teacher
// sees it during the lesson: the "needs attention" badge on the Students
// page, and in the student's detail drawer a line that says on which
// subgoal, since when, how many of the last answers were not right and
// which LO was asked most, with its μ. The student sees nothing.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → conductor → turn record → no-progress check over the
// student's turn history → Cosmos; then the real Students page, badge and
// detail drawer over the docs the student's app wrote. Only the model is
// scripted (`ScriptedLlm`, raw assistant text through the production
// parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/no_progress.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String kExercise = 'naam = ___\nprint("Hallo, " + naam)';
const String kNextExercise = 'stad = ___\nprint("Welkom in " + stad)';

/// The exercise on mount, a wrong grade with a strong negative on lo-print,
/// and the exercise the app asks for next.
List<String> wrongTurnScript() => [
  completeCodeReply(text: 'Vul de naam in.', code: kExercise),
  codeFeedbackReply(
    text: 'Dat klopt niet: de naam is niet ingevuld.',
    quality: 'wrong',
    loSignals: const [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'strong',
      },
    ],
  ),
  completeCodeReply(text: 'Nu de stad.', code: kNextExercise),
];

/// One wrong answer on lo-print of "Print" at [at], as the app writes it:
/// lo-print not mastered after it.
Map<String, dynamic> wrongTurn(String id, DateTime at) => {
  'id': id,
  'type': 'turn_history',
  'uid': kStudentUid,
  'turnAt': at.toUtc().toIso8601String(),
  'subgoalId': 's1',
  'targetLOIds': ['lo-print'],
  'questionType': 'completeCodeQuestion',
  'difficulty': 'medium',
  'isFollowUp': false,
  'chainDepth': 0,
  'overallQuality': 'wrong',
  'loSignals': [
    {
      'subgoalId': 's1',
      'loId': 'lo-print',
      'signal': 'negative',
      'strength': 'strong',
    },
  ],
  'hadFallback': false,
  'appliedSignals': [
    {
      'subgoalId': 's1',
      'loId': 'lo-print',
      'alphaDelta': 0.0,
      'betaDelta': 2.0,
    },
  ],
  'provenance': 'supervised',
  'calibrationBefore': 'medium',
  'calibrationAfter': 'medium',
  'subgoalProgressAfter': 0.0,
  'loStatusAfter': [
    {
      'loId': 'lo-print',
      'mean': 0.3,
      'evidence': 4.0,
      'mastered': false,
      'stuck': false,
    },
  ],
  'subgoalAdvanced': false,
};

/// The `noProgress` events in the turn history.
List<Map> stuckEvents(AppHarness harness) => [
  for (final doc in harness.cosmos['turn_history'].docs.values)
    for (final e in (doc['signalEvents'] as List?) ?? const [])
      if ((e as Map)['kind'] == 'noProgress') e,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  testWidgets('half an hour on "Print" with every answer wrong: the teacher '
      'sees the student stuck — a badge on the Students page and a line in '
      'the drawer — and the student sees nothing', (tester) async {
    // Six wrong answers over the last half hour, four minutes apart.
    final now = DateTime.now();
    final since = now.subtract(const Duration(minutes: 30));
    final seeded = [
      for (var i = 0; i < 6; i++)
        wrongTurn('wrong-$i', since.add(Duration(minutes: 4 * i))),
    ];
    final student = AppHarness(
      llm: ScriptedLlm(wrongTurnScript()),
      extraDocs: {'turn_history': seeded},
    );
    await student.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == kExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );

    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntil(
      tester,
      () => editorText(tester) == kNextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => stuckEvents(student).isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'no noProgress event was written after the answer',
    );

    final event = stuckEvents(student).single;
    expect(event['severity'], 'strong');
    final details = Map<String, dynamic>.from(event['details'] as Map);
    expect(details['subgoalId'], 's1');
    expect(details['since'], since.toUtc().toIso8601String());
    expect(details['minutes'], greaterThanOrEqualTo(30));
    expect(details['oefeningen'], 7);
    expect(details['answers'], 7);
    expect(details['notRight'], 7);
    expect(details['loId'], 'lo-print');
    expect(details['calibration'], 'medium');
    // The μ after today's answer, as the turn record has it.
    final answered = student.cosmos['turn_history'].docs.values.singleWhere(
      (d) =>
          (d['questionType'] as String? ?? '').isNotEmpty &&
          !seeded.any((s) => s['id'] == d['id']),
    );
    final mean = ((answered['loStatusAfter'] as List).single as Map)['mean'];
    expect(details['mean'], mean);

    // The student is told nothing: no notice, no line about it.
    expect(find.textContaining('Stuck'), findsNothing);
    expect(find.textContaining('without progress'), findsNothing);
    expect(find.textContaining('Loopt vast'), findsNothing);

    final turnHistory = [
      for (final d in student.cosmos['turn_history'].docs.values)
        Map<String, dynamic>.of(d),
    ];
    await student.dispose(tester);

    // The teacher, on the Students page over what the student's app wrote.
    final teacher = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'accounts': [accountDoc(studentIdentity)],
        'turn_history': turnHistory,
      },
    );
    await teacher.boot(tester);
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Sam Student'));
    final badge = find.byTooltip('Unacknowledged signal events');
    await pumpUntilFound(tester, badge);
    expect(
      find.descendant(of: badge, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Sam Student'));
    // All the way in before the tap on "Acknowledge" below.
    await pumpUntilEndDrawerOpen(tester, find.byType(StudentDetailDrawer));
    await pumpUntilFound(tester, find.text('Stuck without progress'));
    final clock = DateFormat.Hm('en').format(since);
    final mu = NumberFormat('0.00', 'en').format(mean as num);
    expect(
      find.textContaining(
        'Print since $clock (${details['minutes']} min): 7 of the last 7 '
        'answers not right, most asked: Use print() to show text (μ $mu)',
      ),
      findsOneWidget,
    );

    await pumpUntilFound(tester, find.text('Acknowledge (1)'));
    await tester.tap(find.text('Acknowledge (1)'));
    await pumpUntilFound(tester, find.text('Acknowledge (0)'));
    await tester.tap(
      find.descendant(
        of: find.byType(StudentDetailDrawer),
        matching: find.byTooltip('Close'),
      ),
    );
    await pumpUntilGone(tester, find.byType(StudentDetailDrawer));
    await pumpUntilGone(tester, badge);

    await teacher.dispose(tester);
  });
}
