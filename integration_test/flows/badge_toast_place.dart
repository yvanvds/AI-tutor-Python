// End-to-end (#283): the notice of a new badge never lies over the controls
// the student works with, in a 700 px window or a wide one.
//
// It sat in the top right corner under the top bar, 360 px wide. In a 700 px
// window that is over the row above the editor in Practice — "Send to tutor"
// — and a student handing the next answer in right after the feedback
// clicked the notice instead; with the mouse resting on that spot, the notice
// stayed up. In the 1280 px runner window it lay over the chat's header and
// its restart button. Now, in the session, it lies over the chat's messages,
// under the header and never wider than the chat; in the theory view with
// the chat folded, in the corner beside the strip; in the playground, which
// has no chat and has its buttons where the corner is, it waits until the
// student is back.
//
//   1. 700 px, Practice: the answer handed in with the mouse earns "Effort".
//      The notice is over the chat, under its header, clear of the banner,
//      the row above the editor, the editor and the composer — not under the
//      mouse resting on "Send to tutor". The next answer goes in with a
//      click on the same spot while the notice is still up.
//   2. 1280 px: still over the chat under its header, now at its full
//      width, clear of the restart button and of the exercise.
//   3. 700 px, theory view, the chat folded: a badge from the teacher comes
//      with the next poll, in the corner beside the strip — its "Show chat"
//      button and the footer clear.
//   4. Playground: the next one from the teacher waits — not on screen, its
//      time not running — and shows over the chat back in Practice.
//
// And on the learning path, the page a student picks a subgoal back up from
// (#280), where the notice keeps the corner: at 1280 px and at 700 px it
// leaves every "Finish" and "Review" free, and "Continue" of the goal in
// progress, and a mouse click on the button while the notice is up picks
// the subgoal up.
//
// Real app, real shell, real session layout with the real font, real
// badge service counting a graded answer and polling the account doc; the
// model is scripted (`ScriptedLlm`, raw assistant text through the
// production parser), Cosmos is the in-memory fake.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/badge_toast_place.dart -d windows

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_header.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_continue.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_mcq_disabled.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_thinking.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/playground_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/session_view.dart';
import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/features/session/widgets/output_panel.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/badges/badge_toast_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

/// The narrow window of #258, #259 and #283.
const double _narrow = 700;

const String _first = 'print(___)';
const String _second = 'print(___ + 1)';
const String _third = 'print(___ * 2)';

Map<String, String> _signal() => {
  'subgoalId': 's1',
  'loId': 'lo-print',
  'signal': 'positive',
  'strength': 'moderate',
};

/// [count] oefeningen on "Print" on weekday mornings in September, the one
/// at [wrongAt] wrong: the next answer is the tenth, which earns "Effort".
List<Map<String, dynamic>> _history(int count, {required int wrongAt}) => [
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

/// A badge the teacher gives once, as the Students page writes it (#221).
Map<String, dynamic> _given() => {
  'tier': 1,
  'awardedBy': 'teacher',
  'earnedAt': '2026-10-05T10:00:00.000Z',
  'count': 1,
};

Finder _toast() => find.byKey(const ValueKey('badge-toast'));

Finder _inToast(Finder what) => find.descendant(of: _toast(), matching: what);

Finder _overChat() =>
    find.descendant(of: find.byType(BadgeToastOverChat), matching: _toast());

Finder _panel() => find.byKey(const Key('chat-panel'));

Finder _send() => find.byTooltip('Send to tutor');

Finder _composer() => find.byWidgetPredicate(
  (w) =>
      w is ComposerIdle ||
      w is ComposerThinking ||
      w is ComposerContinue ||
      w is ComposerMcqDisabled,
);

Finder _mode(String label) =>
    find.descendant(of: find.byType(ModeSwitcher), matching: find.text(label));

void _resize(WidgetTester tester, double width) {
  tester.view.physicalSize =
      Size(width, kRunnerWindowSize.height) * tester.view.devicePixelRatio;
}

Rect _window(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

bool _inside(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.01 &&
    inner.top >= outer.top - 0.01 &&
    inner.right <= outer.right + 0.01 &&
    inner.bottom <= outer.bottom + 0.01;

/// The notice whole inside the window, and clear of each of [controls].
void _clearOf(WidgetTester tester, Map<String, Finder> controls, String where) {
  final toast = tester.getRect(_toast());
  expect(
    _inside(_window(tester), toast),
    isTrue,
    reason: '$where: the notice runs out of the window: $toast',
  );
  for (final entry in controls.entries) {
    expect(entry.value, findsWidgets, reason: '$where: no ${entry.key}');
    for (final element in entry.value.evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(
        toast.overlaps(rect),
        isFalse,
        reason: '$where: the notice $toast lies over ${entry.key} $rect',
      );
    }
  }
}

/// Over the chat's messages: inside the panel, under its header, as wide
/// as the panel allows — and clear of the exercise next to it.
void _overTheChat(WidgetTester tester, String where) {
  expect(_overChat(), findsOneWidget, reason: '$where: not over the chat');
  final toast = tester.getRect(_toast());
  final panel = tester.getRect(_panel());
  expect(
    _inside(panel, toast),
    isTrue,
    reason: '$where: the notice $toast is not inside the chat $panel',
  );
  // The header is as wide as the messages: the panel less its border.
  final header = tester.getRect(find.byType(ChatHeader));
  expect(
    toast.top,
    greaterThanOrEqualTo(header.bottom),
    reason: '$where: the notice lies over the chat header',
  );
  expect(toast.right, moreOrLessEquals(header.right - kBadgeToastChatInset));
  final width = header.width - 2 * kBadgeToastChatInset;
  expect(
    toast.width,
    moreOrLessEquals(width < kBadgeToastWidth ? width : kBadgeToastWidth),
    reason: '$where: the notice is not as wide as the chat allows',
  );
  _clearOf(tester, {
    'the objective banner': find.byType(ObjectiveBanner),
    'the row above the editor': find.byType(RunControls),
    'the editor': find.byType(CodeField),
    'the output': find.byType(OutputPanel),
    'the composer': _composer(),
    'the restart button': find.byTooltip('Restart session'),
  }, where);
}

/// Pumps until the chat panel has slid all the way open, to its full width
/// for the window: only then is the exercise next to it laid out where it
/// stays. The slide takes 380 ms, and a scripted exercise can be in the
/// editor before it ends — "Send to tutor" read mid-slide is further right
/// than where it comes to rest, up to past its own right edge and into the
/// chat (CI on #287: the first click still found the button, the second, on
/// the same spot, did not).
///
/// Measured against the window, not the session as last laid out: right
/// after a resize the old layout still matches itself.
Future<void> _untilChatOpen(WidgetTester tester) => pumpUntil(tester, () {
  final session = _window(tester).width - sidebarWidth;
  bool near(double a, double b) => (a - b).abs() < 0.01;
  return near(tester.getSize(find.byType(SessionView)).width, session) &&
      near(tester.getSize(_panel()).width, chatPanelFullWidth(session));
}, reason: 'the chat never slid all the way open');

/// Closes every notice up, as a student would.
Future<void> _closeAll(WidgetTester tester) async {
  while (_toast().evaluate().isNotEmpty) {
    await tester.tap(_inToast(find.byTooltip('Close')));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// The student's mouse, from the window's top left corner.
Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

/// A click with [mouse] at [at]: there, pressed, let go — and the mouse
/// rests there after.
Future<void> _click(WidgetTester tester, TestGesture mouse, Offset at) async {
  await mouse.moveTo(at);
  await tester.pump();
  await mouse.down(at);
  await tester.pump(const Duration(milliseconds: 50));
  await mouse.up();
  await tester.pump();
}

/// The teacher gives [id] once, as the Students page writes it (#221): the
/// student's app brings it with the next poll of the account doc.
void _teacherGives(AppHarness harness, String id) {
  final doc = harness.cosmos['accounts'].docs[kStudentUid]!;
  // A new map: the seeded one is typed by its literal.
  doc['badges'] = <String, dynamic>{
    ...(doc['badges'] as Map).cast<String, dynamic>(),
    id: _given(),
  };
}

// ---- The learning path (#280) ---------------------------------------------

final DateTime _finishedAt = DateTime.utc(2026, 10, 20, 10);

/// The student was moved past [goalId] at [_finishedAt].
Map<String, dynamic> _advancedPast(String goalId, double progress) => {
  'id': '${kStudentUid}_$goalId',
  'uid': kStudentUid,
  'goalId': goalId,
  'progress': progress,
  'updatedAt': _finishedAt.toIso8601String(),
  'lastSessionAt': _finishedAt.toIso8601String(),
  'advancedAt': _finishedAt.toIso8601String(),
};

/// A belief doc last asked three days ago; [stamped] with the mastery stamp
/// of formula 1.1 on two right own questions.
Map<String, dynamic> _belief(
  String subgoalId,
  String loId, {
  required bool stamped,
}) {
  final at = DateTime.now().toUtc().subtract(const Duration(days: 3));
  return {
    'id': '${kStudentUid}_${subgoalId}_$loId',
    'type': 'lo_belief',
    'uid': kStudentUid,
    'subgoalId': subgoalId,
    'loId': loId,
    'alpha': stamped ? 5 : 3,
    'beta': stamped ? 1 : 2,
    'lastUpdatedAt': at.toIso8601String(),
    'lastProbedAt': at.toIso8601String(),
    'lastQuestionType': 'completeCodeQuestion',
    'recentNegativesAtCalibrated': 0,
    'ownQuestions': 3,
    'ownQuestionsRight': stamped ? 2 : 1,
    'ownQuestionsRightNonMcq': stamped ? 2 : 1,
    if (stamped) ...{
      'firstMasteredAt': at.toIso8601String(),
      'lastPositiveAtCalibratedAt': at.toIso8601String(),
      'highestPositiveDifficulty': 'medium',
    },
  };
}

/// "Basics" finished with "Variables" one learning objective short, and
/// "Conditions" in progress: the tiles of "Basics" carry "Review" (Print)
/// and "Finish" (Variables), as in `leerpad_pick_up`.
Map<String, List<Map<String, dynamic>>> _learningPath() => {
  'accounts': [
    {
      ...accountDoc(studentIdentity),
      'oefeningCount': 3,
      'badges': {
        'helloWorld': {'tier': 1, 'earnedAt': '2026-09-15T08:00:00.000Z'},
      },
    },
  ],
  'goals': [
    goalDoc(
      id: 's2',
      title: 'Variables',
      parentId: 'r1',
      order: 2000,
      objectives: [
        objective('lo-var', 'Assign a value to a name'),
        objective('lo-cast', 'Turn text into a number'),
      ],
    ),
    goalDoc(id: 'r2', title: 'Conditions', order: 2000),
    goalDoc(
      id: 's3',
      title: 'Comparisons',
      parentId: 'r2',
      order: 1000,
      objectives: [objective('lo-cmp', 'Compare two values')],
    ),
  ],
  'progress': [_advancedPast('s1', 1.0), _advancedPast('s2', 0.5)],
  'lo_beliefs': [
    _belief('s1', 'lo-print', stamped: true),
    _belief('s2', 'lo-var', stamped: true),
    _belief('s2', 'lo-cast', stamped: false),
  ],
};

Finder _pickUp(String goalId) =>
    find.byKey(ValueKey('leerpad-pick-up-$goalId'));

/// Every "Finish" and "Review" on the page.
Finder _pickUps() => find.byWidgetPredicate((w) {
  final key = w.key;
  return key is ValueKey<String> && key.value.startsWith('leerpad-pick-up-');
});

Finder _card(String rootId) =>
    find.byWidgetPredicate((w) => w is LeerpadCard && w.root.id == rootId);

Finder _inBanner(String text) => find.descendant(
  of: find.byType(ObjectiveBanner),
  matching: find.text(text),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the badge notice lies over the chat\'s messages, clear of '
      '"Send to tutor" and the rest of the exercise at 700 px and 1280 px, '
      'beside the folded chat in the theory view, and waits in the '
      'playground', (tester) async {
    final harness = AppHarness(
      windowSize: Size(_narrow, kRunnerWindowSize.height),
      // A school morning (#235): on a weekend night the same answer earns
      // "Night owl" and "Weekend warrior" too, as one summary.
      turnClockStart: kWeekdayMorning,
      llm: ScriptedLlm([
        completeCodeReply(text: 'Toon de tekst Hallo.', code: _first),
        codeFeedbackReply(
          text: 'Juist: zo toon je de tekst.',
          quality: 'correct',
          loSignals: [_signal()],
        ),
        // The grade asks for the next exercise.
        completeCodeReply(text: 'Nog een.', code: _second),
        codeFeedbackReply(
          text: 'Weer juist.',
          quality: 'correct',
          loSignals: [_signal()],
        ),
        completeCodeReply(text: 'En nog een.', code: _third),
      ]),
      extraDocs: {
        // Nine oefeningen, one wrong among them: nothing waiting at start
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
      },
    );
    await harness.boot(tester);

    // One editor once the mode views have cross-faded.
    bool editorHolds(String code) {
      final editors = find.byType(CodeField).evaluate();
      return editors.length == 1 &&
          (editors.single.widget as CodeField).controller.text == code;
    }

    Future<void> waitForExercise(String code) => pumpUntil(
      tester,
      () => editorHolds(code),
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor:\n$code',
    );
    Future<void> waitForIdle() => pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle',
    );
    Future<void> waitForTurns(int count) => pumpUntil(
      tester,
      () =>
          harness.cosmos['turn_history'].docs.values
              .where((d) => !(d['id'] as String).startsWith('seeded-'))
              .length ==
          count,
      timeout: const Duration(seconds: 30),
      reason: 'answer $count was never handed in',
    );
    void teacherGives(String id) => _teacherGives(harness, id);

    // The student's mouse, which clicks "Send to tutor" and stays there.
    final mouse = await _mouse(tester);
    Future<void> click(Offset at) => _click(tester, mouse, at);

    // 1. 700 px, Practice: the tenth answer earns "Effort".
    await tester.tap(_mode('Practice'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await waitForExercise(_first);
    await waitForIdle();
    expect(_toast(), findsNothing);
    expect(tester.getSize(_panel()).width, lessThan(kBadgeToastWidth));

    // Where "Send to tutor" comes to rest, once the chat has slid open.
    await _untilChatOpen(tester);
    final sendAt = tester.getCenter(_send());
    await click(sendAt);
    await waitForTurns(1);
    await pumpUntilFound(
      tester,
      _inToast(find.text('Effort')),
      timeout: const Duration(seconds: 30),
    );
    await tester.pump(const Duration(milliseconds: 500));
    _overTheChat(tester, '700 px');
    expect(
      tester.getRect(_toast()).contains(sendAt),
      isFalse,
      reason: 'the notice came up under the mouse on "Send to tutor"',
    );
    // Whole inside its card, the words and the buttons.
    for (final part in [
      find.text('Effort'),
      find.text('Tier 1 · Exercises done, right or wrong.'),
      find.text('See your trophy case'),
      find.byTooltip('Close'),
    ]) {
      expect(
        _inside(tester.getRect(_toast()), tester.getRect(_inToast(part))),
        isTrue,
        reason: '700 px: ${part.describeMatch(Plurality.one)} is cut off',
      );
    }

    // Read with the mouse on it, it stays up while the next exercise comes.
    await mouse.moveTo(tester.getCenter(_toast()));
    await tester.pump();
    await waitForExercise(_second);
    await waitForIdle();
    expect(_toast(), findsOneWidget);
    // Back on the spot of "Send to tutor", still under the notice's time —
    // and "Send to tutor" is still there.
    expect(tester.getCenter(_send()), sendAt, reason: 'the button moved');
    await click(sendAt);
    expect(_toast(), findsOneWidget, reason: 'the notice went first');
    await waitForTurns(2);

    // 2. 1280 px: over the chat at its full width, under the header.
    await mouse.moveTo(tester.getCenter(_toast()));
    _resize(tester, kRunnerWindowSize.width);
    await _untilChatOpen(tester);
    expect(tester.getSize(_panel()).width, greaterThan(kBadgeToastWidth));
    expect(_toast(), findsOneWidget);
    _overTheChat(tester, '1280 px');
    expect(tester.getSize(_toast()).width, kBadgeToastWidth);

    await waitForExercise(_third);
    await waitForIdle();
    // The badges the second answer earned, if any, are up by now too.
    await tester.pump(const Duration(seconds: 1));
    await mouse.moveTo(Offset.zero);
    await _closeAll(tester);

    // 3. 700 px, the theory view: the chat folds, and the teacher's badge
    //    comes up beside the strip.
    _resize(tester, _narrow);
    await tester.tap(_mode('Explain'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntil(
      tester,
      () => tester.getSize(_panel()).width < 40,
      reason: 'the chat never folded in the narrow theory view',
    );
    teacherGives('teacher:goodQuestion');
    await pumpUntilFound(
      tester,
      _inToast(find.text('Good question!')),
      timeout: const Duration(seconds: 15),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_overChat(), findsNothing);
    expect(
      tester.getRect(_toast()).right,
      lessThanOrEqualTo(tester.getRect(_panel()).left),
      reason: 'the notice lies over the folded chat',
    );
    expect(tester.getRect(_toast()).top, greaterThanOrEqualTo(topBarHeight));
    _clearOf(tester, {
      'the "Show chat" button': find.byKey(const Key('chat-expand')),
      'the footer': find.byKey(const Key('explain-footer')),
    }, 'theory view, 700 px');
    await _closeAll(tester);

    // 4. The playground: the next one waits, and shows back in Practice.
    await tester.tap(_mode('Playground'));
    await pumpUntilFound(tester, find.byType(PlaygroundView));
    teacherGives('teacher:helpingHand');
    await pumpUntil(
      tester,
      () => harness.container
          .read(badgeAnnouncementsProvider)
          .any((a) => a.badges.any((n) => n.badge.id == 'teacher:helpingHand')),
      timeout: const Duration(seconds: 15),
      reason: 'the poll never brought the teacher\'s badge',
    );
    // Longer than it would have stayed up.
    final waited = DateTime.now().add(
      kBadgeToastDuration + const Duration(seconds: 1),
    );
    while (DateTime.now().isBefore(waited)) {
      expect(_toast(), findsNothing, reason: 'up in the playground');
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(harness.container.read(badgeAnnouncementsProvider), hasLength(1));

    await tester.tap(_mode('Practice'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntilFound(tester, _inToast(find.text('Helping hand')));
    await waitForExercise(_third);
    await _untilChatOpen(tester);
    _overTheChat(tester, 'back in Practice, 700 px');
    await _closeAll(tester);
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });

  testWidgets('on the learning path the notice in the corner leaves the '
      'tiles\' "Finish" and "Review" free: a mouse click on each picks its '
      'subgoal up, at 1280 px and at 700 px', (tester) async {
    final harness = AppHarness(
      llm: ScriptedLlm([
        completeCodeReply(text: 'Zet de invoer om.', code: _first),
        completeCodeReply(text: 'Toon de tekst Hallo.', code: _second),
      ]),
      extraDocs: _learningPath(),
    );
    await harness.boot(tester);
    final mouse = await _mouse(tester);

    Future<void> openLearningPath() async {
      await tester.tap(find.byTooltip('Learning path'));
      await pumpUntilFound(tester, find.byType(LeerpadPage));
      await pumpUntilFound(tester, _card('r2'));
    }

    Future<void> waitForExercise(String code) => pumpUntil(
      tester,
      () {
        final editors = find.byType(CodeField).evaluate();
        return editors.length == 1 &&
            (editors.single.widget as CodeField).controller.text == code;
      },
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor:\n$code',
    );

    /// The teacher's [badge] comes up in the corner, clear of every
    /// "Finish" and "Review" and of the goal in progress' "Continue"; a
    /// mouse click on [goalId]'s button while it is up picks that subgoal
    /// up.
    Future<void> pickUpUnderNotice({
      required String badgeId,
      required String badge,
      required String goalId,
      required String title,
      required String where,
    }) async {
      _teacherGives(harness, badgeId);
      await pumpUntilFound(
        tester,
        _inToast(find.text(badge)),
        timeout: const Duration(seconds: 15),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(_overChat(), findsNothing, reason: '$where: not in the corner');
      expect(tester.getRect(_toast()).top, greaterThanOrEqualTo(topBarHeight));
      _clearOf(tester, {
        'a "Finish" or "Review" button': _pickUps(),
        '"Continue"': find.descendant(
          of: _card('r2'),
          matching: find.text('Continue'),
        ),
      }, where);

      final at = tester.getCenter(_pickUp(goalId));
      expect(_toast(), findsOneWidget, reason: '$where: the notice went first');
      await _click(tester, mouse, at);
      await pumpUntilFound(tester, find.byType(PracticeView));
      await pumpUntilFound(tester, _inBanner('YOUR CHOICE'));
      expect(_inBanner(title), findsOneWidget, reason: where);
      expect(
        harness.container.read(goalSelectionProvider).preferredChild?.id,
        goalId,
        reason: '$where: the click did not pick $goalId up',
      );
    }

    // 1280 px: "Finish" on "Variables".
    await openLearningPath();
    await pumpUntilFound(tester, _pickUp('s2'));
    expect(
      find.descendant(of: _pickUp('s2'), matching: find.text('Finish')),
      findsOneWidget,
    );
    await pickUpUnderNotice(
      badgeId: 'teacher:goodQuestion',
      badge: 'Good question!',
      goalId: 's2',
      title: 'Variables',
      where: '1280 px',
    );
    await waitForExercise(_first);
    await _closeAll(tester);

    // 700 px: "Review" on "Print".
    _resize(tester, _narrow);
    await openLearningPath();
    await pumpUntil(
      tester,
      () => tester.getSize(_card('r1')).width < 760,
      reason: 'the card never narrowed with the window',
    );
    await pumpUntilFound(tester, _pickUp('s1'));
    expect(
      find.descendant(of: _pickUp('s1'), matching: find.text('Review')),
      findsOneWidget,
    );
    await pickUpUnderNotice(
      badgeId: 'teacher:helpingHand',
      badge: 'Helping hand',
      goalId: 's1',
      title: 'Print',
      where: '700 px',
    );
    await waitForExercise(_second);
    await _closeAll(tester);
    expect(harness.llm!.remaining, 0);

    await harness.dispose(tester);
  });
}
