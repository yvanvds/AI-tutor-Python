// Issue #184 — what history each tutor call carries, and the recent
// questions a question request names instead.
//
// A question request goes out on `newSession` (no history) with a
// `recent_questions` block: the questions asked earlier this session, one
// line each, under the LO they were asked for. Grading, hints and the rest
// of the dialogue go out on `exercise` — the current exercise's own
// exchange. The status report keeps `includeAll`. Sign-out drops the list.
//
// The real `TutorService` over a connector that replays canned chunks and
// records the input and the scope of every call; the conductor is mocked
// and the instruction generator is a stand-in.

import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mocks.dart';

/// Replays one canned chunk list per streamed request, answers a
/// non-streamed one with [reply], and keeps the input and scope of every
/// request.
class _RecordingConnector extends OpenaiConnector {
  final List<List<StreamChunk>> scripts = [];
  final List<({String input, PreviousInputs scope})> sent = [];
  String reply = '<TEXT>Goed bezig.</TEXT><META>{"type":"answer"}</META>';

  Stream<StreamChunk> _next() {
    if (scripts.isEmpty) {
      return Stream.value(
        StreamFailed(
          StateError('script exhausted'),
          StackTrace.current,
          ChatNotice.raw('script exhausted'),
        ),
      );
    }
    return Stream.fromIterable(scripts.removeAt(0));
  }

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    sent.add((input: input, scope: inputs));
    return _next();
  }

  @override
  Stream<StreamChunk> resendRequestStream() => _next();

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async {
    sent.add((input: input, scope: inputs));
    return ConnectorOk(reply);
  }
}

class _Generator extends InstructionGenerator {
  @override
  Future<String> generateInstructions(
    ChatRequestType type, {
    required GoalSelectionState goalSelection,
    required List<Instruction> cachedInstructions,
    required Future<List<Instruction>> Function() fetchInstructions,
    required Future<List<Goal>> Function() fetchRootGoals,
    required String languageCode,
    List<LearningObjective> targetLOs = const [],
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
    Goal? subgoalOverride,
  }) async => 'system prompt';
}

class _NoInstructions extends InstructionsService {
  @override
  List<Instruction> build() => const [];
}

class _PresetSelection extends GoalSelectionNotifier {
  _PresetSelection(this.root, this.child);
  final Goal root;
  final Goal child;

  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: root, selectedChild: child);
}

/// Signed in from the start; [signOut] drops the identity the way the real
/// service does.
class _SignedIn extends AuthService {
  @override
  AccountIdentity? build() => const AccountIdentity(
    oid: 'u1',
    displayName: 'Sam Student',
    email: 'sam@example.com',
    firstName: 'Sam',
    lastName: 'Student',
    isTeacher: false,
  );

  @override
  Future<void> signOut() async => state = null;
}

const _lo = LearningObjective(
  id: 'lo-1',
  statement: 'loops',
  kind: LoKind.recall,
);

final _plan = QuestionPlan(
  type: ChatRequestType.socraticQuestion,
  difficulty: QuestionDifficulty.medium,
  targetLOs: const [_lo],
  reason: const TurnSelectionReason(
    candidateLOs: [],
    chosenReason: 'test',
    notchDropFired: false,
  ),
);

List<StreamChunk> _question(String text) => [
  StreamTextDelta(text),
  StreamCompleted(SocraticQuestion(type: 'socratic_question', prompt: text)),
];

List<StreamChunk> _answer(String text) => [
  StreamTextDelta(text),
  StreamCompleted(Answer(type: 'answer', prompt: text)),
];

List<StreamChunk> _hint(String text) => [
  StreamTextDelta(text),
  StreamCompleted(Hint(type: 'hint', prompt: text)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingConnector connector;
  late MockConductor conductor;
  late ChatService chat;
  late ProviderContainer pc;

  final root = Goal(id: 'r1', title: 'Basics', order: 0);
  final active = Goal(
    id: 's1',
    title: 'Loops',
    parentId: 'r1',
    order: 1000,
    objectives: const [_lo],
  );

  setUpAll(() {
    registerFallbackValue(QuestionPlan.noResult);
    registerFallbackValue(
      const GradedAnswer(
        overallQuality: AnswerQuality.wrong,
        signals: [],
        hadFallback: true,
      ),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    connector = _RecordingConnector();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.planNext()).thenAnswer((_) async => _plan);
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);

    final goals = MockGoalsService();
    when(() => goals.streamChildren(any())).thenAnswer((_) => Stream.empty());
    when(() => goals.getChildrenOnce(any())).thenAnswer((_) async => [active]);

    final sound = MockSoundService();
    when(() => sound.askQuestion()).thenAnswer((_) async {});

    chat = ChatService();
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(
          () => TutorService(
            connectorOverride: connector,
            conductorOverride: conductor,
            instructionGeneratorOverride: _Generator(),
          ),
        ),
        authServiceProvider.overrideWith(_SignedIn.new),
        chatServiceProvider.overrideWithValue(chat),
        instructionsServiceProvider.overrideWith(_NoInstructions.new),
        goalsServiceProvider.overrideWithValue(goals),
        goalSelectionProvider.overrideWith(
          () => _PresetSelection(root, active),
        ),
        soundServiceProvider.overrideWithValue(sound),
      ],
    );
    pc.read(modeProvider.notifier).state = SessionMode.practice;
    // Let the sign-in's session start run before the test drives anything.
    pc.read(tutorServiceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  TutorService tutor() => pc.read(tutorServiceProvider.notifier);

  Map<String, dynamic> request(int i) =>
      jsonDecode(connector.sent[i].input) as Map<String, dynamic>;

  Future<void> ask(String question) async {
    connector.scripts.add(_question(question));
    await tutor().requestExercise();
  }

  test('a question request carries no history, and from the second one on '
      'names the questions asked before under their LO', () async {
    await ask('Wat doet een for-lus?');
    connector.scripts.add(_answer('Bijna.'));
    await tutor().handleStudentMessage('Hij herhaalt iets.');
    await ask('Wanneer stopt een while-lus?');
    await ask('Wat telt range(3)?');

    expect(request(0)['request_type'], 'socratic_question');
    expect(connector.sent[0].scope, PreviousInputs.newSession);
    expect(request(0).containsKey('recent_questions'), isFalse);

    expect(connector.sent[2].scope, PreviousInputs.newSession);
    expect(request(2)['recent_questions'], [
      'socratic_question | lo-1 | Wat doet een for-lus?',
    ]);
    expect(request(3)['recent_questions'], [
      'socratic_question | lo-1 | Wat doet een for-lus?',
      'socratic_question | lo-1 | Wanneer stopt een while-lus?',
    ], reason: 'oldest first; the grade in between is not a question');
  });

  test('grading, a hint and the status report: the exercise for the first '
      'two, everything for the report', () async {
    await ask('Wat doet een for-lus?');
    connector.scripts.add(_hint('Kijk naar de teller.'));
    await tutor().requestHint('for i in range(3):\n    pass');
    connector.scripts.add(_answer('Bijna.'));
    await tutor().handleStudentMessage('Hij herhaalt iets.');

    when(() => conductor.takePendingStatusReportGoalId()).thenReturn('s1');
    connector.scripts.add(_question('Wat telt range(3)?'));
    await tutor().requestExercise();

    expect(request(1)['request_type'], 'request_hint');
    expect(connector.sent[1].scope, PreviousInputs.exercise);
    expect(request(2)['request_type'], 'socratic_feedback');
    expect(connector.sent[2].scope, PreviousInputs.exercise);
    expect(request(3)['request_type'], 'status');
    expect(connector.sent[3].scope, PreviousInputs.includeAll);
    expect(request(4)['request_type'], 'socratic_question');
    expect(connector.sent[4].scope, PreviousInputs.newSession);
    expect(request(4)['recent_questions'], [
      'socratic_question | lo-1 | Wat doet een for-lus?',
    ], reason: 'the hint and the report are not questions');
  });

  test('sign-out drops the recent questions', () async {
    await ask('Wat doet een for-lus?');

    await pc.read(authServiceProvider.notifier).signOut();
    await ask('Wat telt range(3)?');

    expect(request(1).containsKey('recent_questions'), isFalse);
  });
}
