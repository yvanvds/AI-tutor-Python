// End-to-end (#221): the badges the teacher gives — Foutenjager, Helpende
// hand, Goede vraag! — for what the app cannot see.
//
// What only the running app can show:
//
//   - the teacher opens a student from the real Students page, presses
//     "Award badge" in the drawer's header, sees how often each badge was
//     given so far, and gives one: it lands on the student's account doc with
//     the other badges, `awardedBy: teacher`, `earnedAt`, its count one up;
//   - the student's app announces it at the next start, with how often by
//     now, marks it seen on the doc so another laptop does not announce it
//     again, and the trophy case shows "Received 2×" under "From your
//     teacher";
//   - with the app open, a badge the teacher gives arrives with the next
//     poll of the account doc (5 s);
//   - a badge the teacher gives between the student's app reading the doc
//     and writing a graded answer back is not overwritten (#223): the write
//     goes with `If-Match` on the doc's `_etag`, meets the teacher's, reads
//     again — and the answer is counted and the badge announced.
//
// Cosmos is the in-memory fake, which keeps an `_etag` per doc and honours
// `If-Match`; the one graded answer comes from a scripted model.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/teacher_badges.dart -d windows

import 'dart:convert';

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

Map<String, dynamic> _student({Map<String, dynamic>? badges}) => {
  ...accountDoc(studentIdentity),
  'className': '6TEST',
  'oefeningCount': 3,
  'badges': ?badges,
};

Map<String, dynamic> _given(int count, {int? seen}) => {
  'tier': 1,
  'awardedBy': 'teacher',
  'earnedAt': '2026-10-05T10:00:00.000Z',
  'count': count,
  'seen': ?seen,
};

Map<String, dynamic> _storedBadges(AppHarness harness) =>
    harness.cosmos['accounts'].docs[kStudentUid]!['badges']
        as Map<String, dynamic>;

Finder _toast() => find.byKey(const ValueKey('badge-toast'));

Finder _inToast(Finder what) => find.descendant(of: _toast(), matching: what);

const String _mcqWrong = '11';

String _mcqReply(String prompt) => llmEnvelope(
  text: prompt,
  meta: jsonEncode({
    'type': 'multiple_choice',
    'code': 'print(1 + 1)',
    'options': [
      {'option': '2'},
      {'option': _mcqWrong},
      {'option': 'Error'},
    ],
    'correct': 'A',
  }),
);

String _mcqGrade(String text) => llmEnvelope(
  text: text,
  meta: jsonEncode({
    'type': 'mcq_feedback',
    'overallQuality': 'wrong',
    'loSignals': [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'negative',
        'strength': 'moderate',
      },
    ],
  }),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the teacher gives a badge from the student drawer: its count '
      'goes up on the student\'s account doc', (tester) async {
    final harness = AppHarness(
      identity: teacherIdentity,
      extraDocs: {
        'accounts': [
          _student(
            badges: {
              'effort': {'tier': 1, 'earnedAt': '2026-10-01T10:00:00.000Z'},
              'teacher:helpingHand': _given(1, seen: 1),
            },
          ),
        ],
      },
    );
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(tester, find.text('Sam Student'));
    await tester.tap(find.text('Sam Student'));
    final drawer = find.byType(StudentDetailDrawer);
    // All the way in before the tap: a few frames into its slide the
    // drawer still reaches past the window.
    await pumpUntilEndDrawerOpen(tester, drawer);

    final award = find.descendant(
      of: drawer,
      matching: find.byKey(const ValueKey('drawer-award-badge')),
    );
    // The button fits in the drawer's header, inside the 1280 x 720 window.
    final header = tester.getRect(drawer);
    final button = tester.getRect(award);
    expect(button.left, greaterThanOrEqualTo(header.left));
    expect(button.right, lessThanOrEqualTo(header.right));
    expect(header.right, lessThanOrEqualTo(kRunnerWindowSize.width));
    expect(button.bottom, lessThanOrEqualTo(kRunnerWindowSize.height));
    expect(
      find.descendant(of: award, matching: find.text('Award badge')),
      findsOneWidget,
    );
    await tester.tap(award);
    final dialog = find.byKey(const ValueKey('award-badge-dialog'));
    await pumpUntilFound(tester, dialog);
    expect(find.text('Award a badge to Sam Student'), findsOneWidget);

    final helping = find.byKey(
      const ValueKey('award-badge-teacher:helpingHand'),
    );
    expect(
      find.descendant(of: helping, matching: find.text('Given 1× so far')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('award-badge-teacher:faultFinder')),
        matching: find.text('Not given yet'),
      ),
      findsOneWidget,
    );
    await tester.tap(helping);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('award-badge-confirm')));
    await pumpUntilGone(tester, dialog);
    await pumpUntilFound(tester, find.text('Helping hand awarded (2×).'));

    final entry = _storedBadges(harness)['teacher:helpingHand'] as Map;
    expect(entry['count'], 2);
    expect(entry['seen'], 1, reason: 'the student has not seen it yet');
    expect(entry['awardedBy'], 'teacher');
    final at = DateTime.parse(entry['earnedAt'] as String);
    expect(DateTime.now().toUtc().difference(at).inMinutes, lessThan(5));
    // Everything else on the doc as it was.
    expect(_storedBadges(harness)['effort'], {
      'tier': 1,
      'earnedAt': '2026-10-01T10:00:00.000Z',
    });
    final doc = harness.cosmos['accounts'].docs[kStudentUid]!;
    expect(doc['oefeningCount'], 3);
    expect(doc['className'], '6TEST');
    // The teacher's own account gets nothing.
    expect(
      harness.cosmos['accounts'].docs[teacherIdentity.oid]!.containsKey(
        'badges',
      ),
      isFalse,
    );

    await harness.dispose(tester);
  });

  testWidgets('the student gets the notice at the next start and by the next '
      'poll, once each, and sees the count in the trophy case', (tester) async {
    final harness = AppHarness(
      extraDocs: {
        'accounts': [
          _student(
            badges: {
              'helloWorld': {'tier': 1, 'earnedAt': '2026-09-01T10:00:00.000Z'},
              'teacher:helpingHand': _given(2, seen: 1),
            },
          ),
        ],
      },
    );
    await harness.boot(tester);

    await pumpUntilFound(
      tester,
      _inToast(find.text('Helping hand')),
      timeout: const Duration(seconds: 30),
    );
    expect(
      _inToast(
        find.text('From your teacher, 2× now · You helped a classmate.'),
      ),
      findsOneWidget,
    );
    // Marked seen on the doc: another laptop does not announce it again.
    await pumpUntil(
      tester,
      () => (_storedBadges(harness)['teacher:helpingHand'] as Map)['seen'] == 2,
      reason: 'the badge was never marked seen',
    );

    await tester.tap(_inToast(find.text('See your trophy case')));
    await pumpUntilFound(tester, find.byType(PrijzenkastPage));
    await pumpUntilGone(tester, _toast());
    final tile = find.byKey(const ValueKey('badge-tile-teacher:helpingHand'));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find
          .descendant(
            of: find.byType(PrijzenkastPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(of: tile, matching: find.text('Received 2×')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('badges-section-teacher')),
        matching: find.text('From your teacher'),
      ),
      findsOneWidget,
    );

    // A poll later: nothing announced again.
    final settle = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(settle)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(_toast(), findsNothing);

    // The teacher gives another one while the app is open: the next poll
    // brings it.
    final doc = harness.cosmos['accounts'].docs[kStudentUid]!;
    (doc['badges'] as Map)['teacher:goodQuestion'] = _given(1);
    await pumpUntilFound(
      tester,
      _inToast(find.text('Good question!')),
      timeout: const Duration(seconds: 15),
    );
    expect(
      _inToast(
        find.text(
          'From your teacher · You asked a question in class that deserved '
          'it.',
        ),
      ),
      findsOneWidget,
    );
    await pumpUntil(
      tester,
      () =>
          (_storedBadges(harness)['teacher:goodQuestion'] as Map)['seen'] == 1,
    );
    await tester.tap(_inToast(find.byTooltip('Close')));
    await pumpUntilGone(tester, _toast());

    await harness.dispose(tester);
  });

  testWidgets('a badge the teacher gives while the student\'s answer is being '
      'written is not lost: the answer is counted and the badge announced '
      '(#223)', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm([
        _mcqReply('Wat drukt print(1 + 1) af?'),
        _mcqGrade('Nee: 1 + 1 is een som.'),
      ]),
      extraDocs: {
        'accounts': [
          _student(
            badges: {
              'helloWorld': {'tier': 1, 'earnedAt': '2026-09-01T10:00:00.000Z'},
            },
          ),
        ],
      },
    );
    await harness.boot(tester);
    final accounts = harness.cosmos['accounts'];

    // The teacher's app: an account service of its own on the same docs. Its
    // badge lands after the student's app read the doc for the write of the
    // answer — the one that counts the oefening — and before that write's
    // replace.
    final teacher = AccountService(container: accounts.container);
    var given = false;
    accounts.beforeReplace = (id, doc) async {
      if (given || id != kStudentUid || doc['oefeningCount'] != 4) return;
      given = true;
      await teacher.awardTeacherBadge(
        uid: kStudentUid,
        badgeId: 'teacher:helpingHand',
      );
    };

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(QuizView));
    await pumpUntilFound(tester, find.text(_mcqWrong));
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
    );
    await tester.tap(find.text(_mcqWrong));
    await pumpUntilFound(
      tester,
      find.textContaining('1 + 1 is een som', findRichText: true),
    );

    // Both on the doc: the oefening counted, and the teacher's badge.
    Map<String, dynamic> doc() => accounts.docs[kStudentUid]!;
    await pumpUntil(
      tester,
      () => given && doc()['oefeningCount'] == 4,
      timeout: const Duration(seconds: 30),
      reason: 'the answer was never written with its oefening counted',
    );
    expect(doc()['calibration'], isA<Map>());
    final entry = _storedBadges(harness)['teacher:helpingHand'] as Map?;
    expect(entry, isNotNull, reason: "the answer's write dropped the badge");
    expect(entry!['count'], 1);
    expect(entry['awardedBy'], 'teacher');
    expect(_storedBadges(harness)['helloWorld'], {
      'tier': 1,
      'earnedAt': '2026-09-01T10:00:00.000Z',
    });

    // So the student's app announces it on a poll, and marks it seen.
    await pumpUntilFound(
      tester,
      _inToast(find.text('Helping hand')),
      timeout: const Duration(seconds: 40),
    );
    expect(
      _inToast(find.text('From your teacher · You helped a classmate.')),
      findsOneWidget,
    );
    await pumpUntil(
      tester,
      () => (_storedBadges(harness)['teacher:helpingHand'] as Map)['seen'] == 1,
      reason: 'the badge was never marked seen',
    );
    expect(doc()['oefeningCount'], 4);

    await harness.dispose(tester);
  });
}
