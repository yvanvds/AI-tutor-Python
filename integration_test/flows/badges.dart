// End-to-end (#220): badges for moments worth marking — no XP, no grade.
//
// What only the running app can show:
//
//   - the first start after the release: the shell starts the badge service,
//     which reads the student's `turn_history` partition once, stores what it
//     already earned on the account doc and puts up ONE summary — not a
//     notice per badge — that opens the trophy case from the rail;
//   - after a graded answer: the badge the answer earns is counted from the
//     history in memory, stored, and announced after the grade's feedback is
//     on screen — never before the answer is in — and only once. The turn
//     record carries `askedAt` (for "Rome …") and leaves `keyDisputed` out;
//   - the teacher has no trophy case on the rail, and reviews the badges on
//     the proof sheet under Options; About lists the icons' authors (CC BY
//     3.0).
//
// The model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser); Cosmos is the in-memory fake with the history seeded.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/badges.dart -d windows

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _exercise = 'print(___)';
const String _feedback = 'Juist: zo toon je de tekst.';

/// [count] oefeningen on "Print", on weekday mornings in September; the one
/// at [wrongAt] answered wrong, the rest right.
List<Map<String, dynamic>> _history(int count, {int? wrongAt}) => [
  for (var i = 0; i < count; i++)
    PersistedTurnRecord(
      id: 'seeded-${i.toString().padLeft(3, '0')}',
      turnAt: DateTime(2026, 9, 15, 10, i).toUtc(),
      subgoalId: 's1',
      targetLOIds: const ['lo-print'],
      questionType: 'completeCodeQuestion',
      difficulty: QuestionDifficulty.medium,
      isFollowUp: false,
      chainDepth: 0,
      selectionReason: null,
      overallQuality: i == wrongAt
          ? AnswerQuality.wrong
          : AnswerQuality.correct,
      loSignals: const [],
      hadFallback: false,
      appliedSignals: const [],
      calibrationBefore: QuestionDifficulty.medium,
      calibrationAfter: QuestionDifficulty.medium,
      subgoalProgressAfter: 0,
      loStatusAfter: const [],
      subgoalAdvanced: false,
    ).toMap(uid: kStudentUid),
];

Map<String, dynamic>? _badgesOnAccount(AppHarness harness) =>
    harness.cosmos['accounts'].docs[kStudentUid]?['badges']
        as Map<String, dynamic>?;

int _tierOnAccount(AppHarness harness, String id) =>
    ((_badgesOnAccount(harness)?[id] as Map?)?['tier'] as int?) ?? 0;

Finder _toast() => find.byKey(const ValueKey('badge-toast'));

Finder _inToast(Finder what) => find.descendant(of: _toast(), matching: what);

Finder _tile(String id) => find.byKey(ValueKey('badge-tile-$id'));

Finder _inTile(String id, Finder what) =>
    find.descendant(of: _tile(id), matching: what);

/// Brings a tile of the trophy case into view: the page is a real
/// `ListView`, so a tile below the fold is not built yet.
Future<void> _scrollTo(WidgetTester tester, Finder tile) async {
  final scrollable = find
      .descendant(
        of: find.byType(PrijzenkastPage),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(tile, 200, scrollable: scrollable);
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the first start sums up what the history already earned in '
      'one notice, which opens the trophy case', (tester) async {
    final harness = AppHarness(
      extraDocs: {
        'accounts': [
          {...accountDoc(studentIdentity), 'oefeningCount': 12},
        ],
        'turn_history': _history(12),
      },
    );
    await harness.boot(tester);

    // Twelve right oefeningen: Effort (10), On a roll (10 in a row) and
    // Hello, World!, in one summary.
    await pumpUntilFound(
      tester,
      _inToast(find.text("You've already earned 3 badges!")),
    );
    expect(
      _inToast(find.text('Effort, On a roll, Hello, World!')),
      findsOneWidget,
    );
    expect(_toast(), findsOneWidget, reason: 'one notice, not three');
    expect(_tierOnAccount(harness, 'effort'), 1);
    expect(_tierOnAccount(harness, 'streak'), 1);
    expect(_tierOnAccount(harness, 'helloWorld'), 1);
    expect(_badgesOnAccount(harness)!.containsKey('fortyTwo'), isFalse);
    // Badges are worth no XP: the count the XP is made of is untouched.
    expect(harness.cosmos['accounts'].docs[kStudentUid]!['oefeningCount'], 12);

    await tester.tap(_inToast(find.text('See your trophy case')));
    await pumpUntilFound(tester, find.byType(PrijzenkastPage));
    await pumpUntilGone(tester, _toast());
    expect(find.text('3 of 34 badges earned'), findsOneWidget);
    expect(_inTile('effort', find.text('Tier 1 of 6')), findsOneWidget);
    expect(_inTile('effort', find.text('12/100')), findsOneWidget);
    expect(_inTile('streak', find.text('Tier 1 of 4')), findsOneWidget);
    // The class has no lesson times (none seeded): the lesson badges wait.
    expect(
      _inTile(
        'homeWork',
        find.text('Your class has no lesson times yet, so this one waits.'),
      ),
      findsOneWidget,
    );
    // A secret not found: no name, no rule. Further down the page, which a
    // real window has not built yet.
    await _scrollTo(tester, _tile('rubberDuck'));
    expect(_inTile('rubberDuck', find.text('Secret badge')), findsOneWidget);
    expect(find.text('Rubber duck'), findsNothing);
    // The hoofddoel of the seed, its two LOs not mastered yet.
    await _scrollTo(tester, _tile('expert:r1'));
    expect(_inTile('expert:r1', find.text('Expert in Basics')), findsOneWidget);
    expect(_inTile('expert:r1', find.text('0/2')), findsOneWidget);

    // The rail entry goes to the same page.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.byTooltip('Trophy case'));
    await pumpUntilFound(tester, find.byType(PrijzenkastPage));

    await harness.dispose(tester);
  });

  testWidgets('a graded answer that earns a badge is announced after its '
      'feedback, once, and stored', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Toon de tekst Hallo.', code: _exercise),
        codeFeedbackReply(
          text: _feedback,
          quality: 'correct',
          loSignals: const [
            {
              'subgoalId': 's1',
              'loId': 'lo-print',
              'signal': 'positive',
              'strength': 'moderate',
            },
          ],
        ),
        // The grade asks for the next exercise.
        completeCodeReply(text: 'Nog een.', code: 'print(___ + 1)'),
      ]),
      extraDocs: {
        // Nine oefeningen, one wrong among them: no badge waiting at start
        // but "Hello, World!", which is stored already.
        'accounts': [
          {
            ...accountDoc(studentIdentity),
            'oefeningCount': 9,
            'badges': {
              'helloWorld': {'tier': 1, 'earnedAt': '2026-09-15T08:00:00.000Z'},
            },
          },
        ],
        'turn_history': _history(9, wrongAt: 4),
        // "Print" without its lesson, so the leerpad opens the editor.
        'goals': [
          goalDoc(
            id: 's1',
            title: 'Print',
            parentId: 'r1',
            order: 1000,
            objectives: [objective('lo-print', 'Use print() to show text')],
          ),
        ],
      },
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () =>
          tester.widget<CodeField>(find.byType(CodeField)).controller.text ==
          _exercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    // Nothing earned while the question is up.
    expect(_toast(), findsNothing);
    expect(_tierOnAccount(harness, 'effort'), 0);

    await tester.tap(find.byTooltip('Send to tutor'));
    await pumpUntilFound(
      tester,
      _toast(),
      timeout: const Duration(seconds: 30),
    );
    // The feedback was there first.
    expect(
      find.textContaining('zo toon je de tekst', findRichText: true),
      findsWidgets,
    );
    expect(_inToast(find.text('Effort')), findsOneWidget);
    expect(
      _inToast(find.text('Tier 1 · Exercises done, right or wrong.')),
      findsOneWidget,
    );
    expect(_tierOnAccount(harness, 'effort'), 1);
    expect(
      (_badgesOnAccount(harness)!['helloWorld'] as Map)['earnedAt'],
      '2026-09-15T08:00:00.000Z',
      reason: 'what was earned stays as it was',
    );

    // The record of the answer: when the question went up, and no dispute.
    final record = harness.cosmos['turn_history'].docs.values.firstWhere(
      (d) => !(d['id'] as String).startsWith('seeded-'),
    );
    final asked = DateTime.parse(record['askedAt'] as String);
    final answered = DateTime.parse(record['turnAt'] as String);
    expect(asked.isAfter(answered), isFalse);
    expect(record.containsKey('keyDisputed'), isFalse);

    // Closed, it stays closed: the badge is announced once.
    await tester.tap(_inToast(find.byTooltip('Close')));
    await pumpUntilGone(tester, _toast());
    final settle = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(settle)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(_toast(), findsNothing);
    expect(_tierOnAccount(harness, 'effort'), 1);

    await harness.dispose(tester);
  });

  testWidgets('a teacher has no trophy case, reviews the badges on the proof '
      'sheet, and About credits the icons', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    expect(find.text('Hi Yvan,'), findsOneWidget);
    expect(find.byTooltip('Trophy case'), findsNothing);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    final open = find.byKey(const ValueKey('options-badge-proof-sheet'));
    await tester.scrollUntilVisible(open, 200, scrollable: optionsScrollable());
    await tester.ensureVisible(open);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(open);
    await pumpUntilFound(tester, find.text('Badge proof sheet'));
    expect(find.byKey(const ValueKey('badge-proof-dark')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('badge-proof-light')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('badge-proof-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const ValueKey('badge-proof-light')), findsOneWidget);
    await tester.pageBack();
    await pumpUntilGone(tester, find.text('Badge proof sheet'));

    final credits = find.byKey(const ValueKey('about-badge-credits'));
    await tester.scrollUntilVisible(
      credits,
      200,
      scrollable: optionsScrollable(),
    );
    await tester.ensureVisible(credits);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(credits);
    await pumpUntilFound(tester, find.text('Badge icons'));
    expect(find.text('Weight lifting up by Delapouite'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await pumpUntilGone(tester, find.text('Badge icons'));
    // A teacher's account gets no badges.
    expect(
      harness.cosmos['accounts'].docs[teacherIdentity.oid]!.containsKey(
        'badges',
      ),
      isFalse,
    );

    await harness.dispose(tester);
  });
}
