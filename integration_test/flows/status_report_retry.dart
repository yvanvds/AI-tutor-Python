// End-to-end (#139): a status report that failed on a dropped socket is
// re-sent once, and the report the re-send brings back is the one the
// teacher gets.
//
// The status report is the one non-streamed turn the tutor makes: the
// moment a subgoal is mastered, the app asks the model for a short report
// on it before the next exercise, and writes it to `status_reports` — where
// the teacher's student drawer and the grade proposal (#99) read it. The
// tutor re-sends a failed request once, and on the streamed turns it always
// did; on this turn the re-send waited for the tutor to be `idle`, and the
// turn that had just failed still held `working`, so nothing ever went out
// again: a report that failed on a timeout or a dropped socket was lost.
//
// Real app, real navigation, real practice view and editor, real
// TutorService → grader → conductor → mastery → status turn → report
// service → Cosmos. The *production* connector is in place and only the
// socket underneath is replaced (`AppHarness.openaiClient`), so the drop is
// a real `SocketException` out of a real request and the re-send is the
// connector's own. The socket drops exactly once, on the status request.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/status_report_retry.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/goal_splash_overlay.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_openai.dart';
import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

const String _exercise = 'naam = ___\nprint("Hallo, " + naam)';
const String _nextExercise = 'stad = ___\nprint("Welkom in " + stad)';

/// The report the model writes on "Print" once it is mastered.
const String _report = 'Sam gebruikt print() vlot en zonder hulp.';

/// The pill the student sees for the dropped socket — once.
const String _unreachablePill =
    'Something went wrong with the tutor: No connection to the tutor.';

/// The streamed turns, in order: the exercise on mount, the grade for the
/// submitted code (a clean strong positive on the seeded LO), and the next
/// subgoal's first exercise, which the app asks for right after the report.
List<String> _streamedScript() => [
  completeCodeReply(text: 'Vul de naam in.', code: _exercise),
  codeFeedbackReply(
    text: 'Helemaal juist.',
    quality: 'correct',
    loSignals: const [
      {
        'subgoalId': 's1',
        'loId': 'lo-print',
        'signal': 'positive',
        'strength': 'strong',
      },
    ],
  ),
  completeCodeReply(text: 'Nu de stad.', code: _nextExercise),
];

/// The status turn's reply, in the envelope the instructions demand: the
/// report itself is the TEXT section.
String _statusReply() => llmEnvelope(
  text: _report,
  meta:
      '{"type":"status_summary","stats":{"hints_used":0,'
      '"common_issues":[],"last_exercise_type":"complete_code"}}',
);

/// The belief on `lo-print` one strong positive short of mastery. (3, 1)
/// reads mean 0.75 on evidence 4; the grade adds 2.0 to α at medium, and
/// (5, 1) reads mean 0.83 on evidence 6 — past both mastery thresholds
/// (CONDUCTOR_POLICY §4), with the calibrated positive already on record.
/// Written just now, so no decay moves it first.
Map<String, dynamic> _almostMastered(DateTime now) => {
  'id': '${kStudentUid}_s1_lo-print',
  'type': 'lo_belief',
  'uid': kStudentUid,
  'subgoalId': 's1',
  'loId': 'lo-print',
  'alpha': 3.0,
  'beta': 1.0,
  'lastUpdatedAt': now.toIso8601String(),
  'lastQuestionType': 'completeCodeQuestion',
  'lastPositiveAtCalibratedAt': now.toIso8601String(),
  'highestPositiveDifficulty': 'medium',
  'recentNegativesAtCalibrated': 0,
};

http.Response _ok(String body) => http.Response(
  body,
  200,
  headers: const {'content-type': 'application/json'},
);

/// The user turn of a request as the app put it on the wire: the last
/// message of the chat body.
String _userTurn(http.Request req) {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
  return messages.last['content'] as String;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String editorText(WidgetTester tester) =>
      tester.widget<CodeField>(find.byType(CodeField)).controller.text;

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  /// Opens the practice editor on "Print" and waits for the first exercise.
  Future<void> openPractice(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntil(
      tester,
      () => editorText(tester) == _exercise,
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
  }

  testWidgets('a status report that failed on a dropped socket is re-sent '
      'once, and the report it brings back is written', (tester) async {
    final openai = FakeOpenAi();
    final streamed = _streamedScript();
    var statusRequests = 0;
    openai.answer = (req) {
      if (FakeOpenAi.wantsStream(req)) {
        if (streamed.isEmpty) throw StateError('streamed script exhausted');
        return _ok(FakeOpenAi.streamed(streamed.removeAt(0)));
      }
      // The one non-streamed turn: the status report. The socket drops on
      // the first request and the second is answered.
      if (++statusRequests == 1) {
        throw const SocketException('Connection reset by peer');
      }
      return _ok(FakeOpenAi.completion(_statusReply()));
    };

    final harness = AppHarness(
      openaiClient: openai.client,
      extraDocs: {
        'lo_beliefs': [_almostMastered(DateTime.now().toUtc())],
      },
    );
    await harness.boot(tester);
    await openPractice(tester);

    await tester.tap(find.byTooltip('Send to tutor'));

    // The grade masters "Print" — which is what asks for the report — and
    // the app celebrates it. The student taps the celebration away, as
    // they would; that is also what keeps its 10 s auto-dismiss from
    // reaching into a container this test has already torn down.
    await pumpUntil(
      tester,
      () =>
          harness.cosmos['progress'].docs['${kStudentUid}_s1']?['progress'] ==
          1.0,
      timeout: const Duration(seconds: 30),
      reason: 'the grade never mastered the subgoal',
    );
    final celebration = find.descendant(
      of: find.byType(GoalSplashOverlay),
      matching: find.text('Goal reached!'),
    );
    await pumpUntilFound(tester, celebration);
    expect(
      find.descendant(
        of: find.byType(GoalSplashOverlay),
        matching: find.text('Print'),
      ),
      findsOneWidget,
    );
    await tester.tap(celebration);
    await pumpUntilGone(tester, celebration);

    // The report the re-send brought back is the one on record.
    await pumpUntil(
      tester,
      () => harness.cosmos['status_reports'].docs.containsKey(
        '${kStudentUid}_s1',
      ),
      timeout: const Duration(seconds: 30),
      reason:
          'no status report was written: the dropped request was not '
          're-sent',
    );
    expect(
      harness
          .cosmos['status_reports']
          .docs['${kStudentUid}_s1']!['statusReport'],
      _report,
    );

    // And the turn went on: the next subgoal's exercise reached the editor
    // and the tutor is idle again.
    await pumpUntil(
      tester,
      () => editorText(tester) == _nextExercise,
      timeout: const Duration(seconds: 30),
      reason: 'the next exercise never reached the editor',
    );
    await pumpUntil(
      tester,
      () => harness.container.read(tutorServiceProvider) == TutorState.idle,
      timeout: const Duration(seconds: 30),
      reason: 'the tutor never went idle after the report',
    );

    // Exactly two status requests went out — the one the socket dropped
    // and its one re-send — both asking for the report, on the school's
    // key; nothing else was re-sent.
    final statusOnWire = openai.requests
        .where((r) => !FakeOpenAi.wantsStream(r))
        .toList();
    expect(statusRequests, 2);
    expect(statusOnWire, hasLength(2));
    for (final r in statusOnWire) {
      expect(_userTurn(r), contains('"request_type":"status"'));
      expect(r.headers['Authorization'], 'Bearer $kSchoolApiKey');
    }
    expect(openai.requests, hasLength(5), reason: 'three streamed turns');
    expect(streamed, isEmpty);

    // The student was told about the drop once; the re-send was silent.
    expect(pills(tester).where((p) => p == _unreachablePill), hasLength(1));

    await harness.dispose(tester);
  });
}
