// End-to-end (#107): home credit that the class work after it contradicts
// reaches the teacher, and only the teacher. A student answered lo-print
// right at home and then wrong in class; one more wrong answer in today's
// lesson makes the gap — the app writes a `provenanceGap` event to
// `turn_history`, and the teacher reads it in the student's detail drawer:
// an audit line with no badge when it rests on three answers a side, a
// strong one that drives the "needs attention" badge on the Students page
// when it rests on six. The student sees nothing.
//
// The class answers before today include one that a build from before #219
// recorded as `home` although it fell in the lesson: the check reads it by
// the timetable, as the grade proposal's tally does, and without that
// reading the audit case would not have three class answers.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → conductor → turn record → provenance-gap check over the
// real timetable source (`config/classes`, the student's class) → Cosmos;
// then the real Students page, badge and detail drawer over the docs the
// student's app wrote. Only the model is scripted (`ScriptedLlm`, raw
// assistant text through the production parser).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/provenance_gap.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

/// The student, in class 6TEST.
Map<String, dynamic> studentInClass() => {
  ...accountDoc(studentIdentity),
  'className': '6TEST',
};

/// 6TEST has one lesson: today, from an hour before [now] to an hour after
/// it, in local time.
Map<String, dynamic> lessonAround(DateTime now) {
  final minute = now.hour * 60 + now.minute;
  return {
    'id': 'classes',
    'type': 'config',
    'classes': [
      {
        'name': '6TEST',
        'lessons': [
          {
            'weekday': now.weekday,
            'start': formatClockMinute(minute < 60 ? 0 : minute - 60),
            'end': formatClockMinute(
              minute > 23 * 60 - 1 ? 23 * 60 + 59 : minute + 60,
            ),
          },
        ],
      },
    ],
  };
}

/// One graded turn on lo-print as the app writes it: one direct applied
/// signal, right or wrong at medium.
Map<String, dynamic> turnDoc(
  String id,
  DateTime at, {
  required bool right,
  required String provenance,
}) => {
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
  'overallQuality': right ? 'correct' : 'wrong',
  'loSignals': [
    {
      'subgoalId': 's1',
      'loId': 'lo-print',
      'signal': right ? 'positive' : 'negative',
      'strength': 'strong',
    },
  ],
  'hadFallback': false,
  'appliedSignals': [
    {
      'subgoalId': 's1',
      'loId': 'lo-print',
      'alphaDelta': right ? 2.0 : 0.0,
      'betaDelta': right ? 0.0 : 2.0,
    },
  ],
  'provenance': provenance,
  'calibrationBefore': 'medium',
  'calibrationAfter': 'medium',
  'subgoalProgressAfter': 0.0,
  'loStatusAfter': const [],
  'subgoalAdvanced': false,
};

/// The student's work on lo-print before today's answer: [home] right
/// answers at home two days ago, then [inClass] wrong answers in class — the
/// first earlier in today's lesson, recorded `home` the way a build from
/// before #219 recorded it, the rest yesterday, recorded `supervised`.
List<Map<String, dynamic>> history(
  DateTime now, {
  required int home,
  required int inClass,
}) {
  final twoDaysAgo = now.subtract(const Duration(days: 2));
  final yesterday = now.subtract(const Duration(days: 1));
  var earlierToday = now.subtract(const Duration(minutes: 30));
  if (earlierToday.day != now.day) {
    earlierToday = DateTime(now.year, now.month, now.day, 0, 0, 30);
  }
  return [
    for (var i = 0; i < home; i++)
      turnDoc(
        'home-$i',
        twoDaysAgo.add(Duration(minutes: i)),
        right: true,
        provenance: 'home',
      ),
    turnDoc('class-today', earlierToday, right: false, provenance: 'home'),
    for (var i = 1; i < inClass; i++)
      turnDoc(
        'class-$i',
        yesterday.add(Duration(minutes: i)),
        right: false,
        provenance: 'supervised',
      ),
  ];
}

/// The `provenanceGap` events in the turn history.
List<Map> gapEvents(AppHarness harness) => [
  for (final doc in harness.cosmos['turn_history'].docs.values)
    for (final e in (doc['signalEvents'] as List?) ?? const [])
      if ((e as Map)['kind'] == 'provenanceGap') e,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      (tester.widget<CodeField>(find.byType(CodeField)).controller).text;

  /// The student, in today's lesson, answers lo-print wrong once, and the app
  /// moves on. Returns the turn history the student's app left behind, once
  /// the gap event is in it.
  Future<List<Map<String, dynamic>>> answerWrongInClass(
    WidgetTester tester, {
    required int home,
    required int inClass,
  }) async {
    final now = DateTime.now();
    final seeded = history(now, home: home, inClass: inClass);
    final harness = AppHarness(
      llm: ScriptedLlm(wrongTurnScript()),
      extraDocs: {
        'accounts': [studentInClass()],
        'config': [lessonAround(now)],
        'turn_history': seeded,
      },
    );
    await harness.boot(tester);

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
      () => gapEvents(harness).isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'no provenanceGap event was written after the answer',
    );

    // Today's answer was graded in the lesson.
    final answered = harness.cosmos['turn_history'].docs.values.singleWhere(
      (d) =>
          (d['questionType'] as String? ?? '').isNotEmpty &&
          !seeded.any((s) => s['id'] == d['id']),
    );
    expect(answered['provenance'], 'supervised');

    // The student is told nothing: no notice, no line about it.
    expect(find.textContaining('home work'), findsNothing);
    expect(find.textContaining('thuiswerk'), findsNothing);

    final docs = [
      for (final d in harness.cosmos['turn_history'].docs.values)
        Map<String, dynamic>.of(d),
    ];
    await harness.dispose(tester);
    return docs;
  }

  /// The teacher opens the Students page over [turnHistory].
  Future<AppHarness> openStudents(
    WidgetTester tester,
    List<Map<String, dynamic>> turnHistory,
  ) async {
    final harness = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'accounts': [studentInClass()],
        'turn_history': turnHistory,
      },
    );
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Sam Student'));
    return harness;
  }

  final badge = find.byTooltip('Unacknowledged signal events');
  final gapLabel = find.text('Class work contradicts home work');

  testWidgets('three right at home, then three wrong in class: an audit '
      'line in the teacher\'s drawer, no badge', (tester) async {
    final turnHistory = await answerWrongInClass(tester, home: 3, inClass: 2);

    final event = [
      for (final doc in turnHistory)
        for (final e in (doc['signalEvents'] as List?) ?? const [])
          if ((e as Map)['kind'] == 'provenanceGap') e,
    ].single;
    expect(event['severity'], 'audit');
    expect(event['details'], {
      'subgoalId': 's1',
      'loId': 'lo-print',
      'homeSignals': 3,
      'homePositive': 3,
      'supervisedSignals': 3,
      'supervisedPositive': 0,
      'windowDays': 42,
    });

    final harness = await openStudents(tester, turnHistory);
    // The badge stream has answered by the time the row is there; give it a
    // poll's worth of frames anyway before saying it stays away.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(badge, findsNothing);

    await tester.tap(find.text('Sam Student'));
    await pumpUntilEndDrawerOpen(tester, find.byType(StudentDetailDrawer));
    await pumpUntilFound(tester, gapLabel);
    expect(
      find.textContaining(
        'Use print() to show text: at home 3 of 3 positive, in class '
        'afterwards 0 of 3 (last 42 days)',
      ),
      findsOneWidget,
    );
    // Nothing to acknowledge: an audit line is not a badge.
    expect(find.text('Acknowledge (0)'), findsOneWidget);

    await harness.dispose(tester);
  });

  testWidgets('six right at home, then six wrong in class: strong — the '
      'Students page badges the student until the teacher acknowledges', (
    tester,
  ) async {
    final turnHistory = await answerWrongInClass(tester, home: 6, inClass: 5);

    final harness = await openStudents(tester, turnHistory);
    await pumpUntilFound(tester, badge);
    expect(
      find.descendant(of: badge, matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Sam Student'));
    // All the way in before the tap on "Acknowledge" below: a few frames
    // into its slide the drawer still reaches past the window.
    await pumpUntilEndDrawerOpen(tester, find.byType(StudentDetailDrawer));
    await pumpUntilFound(tester, gapLabel);
    expect(
      find.textContaining(
        'Use print() to show text: at home 6 of 6 positive, in class '
        'afterwards 0 of 6 (last 42 days)',
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

    await harness.dispose(tester);
  });
}
