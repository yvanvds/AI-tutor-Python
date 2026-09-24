// Issue #183 — what an exercise's LLM calls cost lands on its turn record.
//
// The connector reports what each call cost; the tutor adds the calls up
// until a graded turn is written and puts the sum on that record, split
// per kind of call (question, grading, hint, ...) with the model. What
// happened in between without a record of its own — a status report, a
// reply the connector refused — rides along with the next one. Sign-out
// drops what a student left pending.
//
// The real `TutorService` over a connector that replays canned chunks with
// a usage on them; the conductor is mocked and the turn history records
// what it is handed.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/core/token_usage.dart';
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
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mocks.dart';

const _model = 'gpt-5-mini';

CallUsage _cost(int prompt, int cached, int completion) => CallUsage(
  model: _model,
  tokens: TokenUsage(
    promptTokens: prompt,
    cachedTokens: cached,
    completionTokens: completion,
  ),
);

/// Replays one canned chunk list per streamed request and answers a
/// non-streamed one with [reply].
class _Connector extends OpenaiConnector {
  final List<List<StreamChunk>> scripts = [];
  ConnectorResult reply = const ConnectorOk(
    '<TEXT>Goed bezig.</TEXT><META>{"type":"answer"}</META>',
  );

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
  }) => _next();

  @override
  Stream<StreamChunk> resendRequestStream() => _next();

  @override
  Future<ConnectorResult> sendRequest({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) async => reply;
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

/// Keeps every record it is handed instead of writing it to Cosmos.
class _RecordingHistory extends TurnHistoryService {
  _RecordingHistory() : super(getUid: () => 'u1');

  final List<PersistedTurnRecord> records = [];

  @override
  Future<void> append(PersistedTurnRecord record) async => records.add(record);
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

const _outcome = TurnOutcome(
  overallQuality: AnswerQuality.correct,
  subgoalAdvanced: false,
  degraded: false,
  loSignals: [],
  appliedSignals: [],
  loStatusAfter: [],
  subgoalProgressAfter: 0.2,
  calibrationBefore: QuestionDifficulty.medium,
  calibrationAfter: QuestionDifficulty.medium,
  hadFallback: false,
);

List<StreamChunk> _question(String text, CallUsage? usage) => [
  StreamTextDelta(text),
  StreamCompleted(
    SocraticQuestion(type: 'socratic_question', prompt: text),
    usage: usage,
  ),
];

List<StreamChunk> _hint(String text, CallUsage usage) => [
  StreamTextDelta(text),
  StreamCompleted(
    Hint(type: 'hint', prompt: text),
    usage: usage,
  ),
];

List<StreamChunk> _grade(String text, CallUsage? usage) => [
  StreamTextDelta(text),
  StreamCompleted(
    SocraticFeedback(
      type: 'socratic_feedback',
      quality: AnswerQuality.correct,
      prompt: text,
    ),
    usage: usage,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connector connector;
  late MockConductor conductor;
  late _RecordingHistory history;
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
    connector = _Connector();
    history = _RecordingHistory();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.planNext()).thenAnswer((_) async => _plan);
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);
    when(
      () => conductor.integrateAnswer(
        plan: any(named: 'plan'),
        answer: any(named: 'answer'),
      ),
    ).thenAnswer((_) async => _outcome);

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
        turnHistoryServiceProvider.overrideWithValue(history),
      ],
    );
    pc.read(modeProvider.notifier).state = SessionMode.practice;
    pc.read(tutorServiceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  TutorService tutor() => pc.read(tutorServiceProvider.notifier);

  test("a graded turn carries what its exercise's calls cost, split per "
      'call, with the model; the next record starts over', () async {
    connector.scripts.add(
      _question('Wat doet een for-lus?', _cost(1200, 1024, 150)),
    );
    await tutor().requestExercise();
    connector.scripts.add(_hint('Kijk naar de teller.', _cost(400, 0, 40)));
    await tutor().requestHint('for i in range(3):\n    pass');
    connector.scripts
      ..add(_grade('Juist.', _cost(1500, 1024, 300)))
      // The grade asks for the next exercise at once.
      ..add(_question('Wat telt range(3)?', _cost(1300, 1152, 160)));
    await tutor().handleStudentMessage('Hij herhaalt iets.');

    expect(history.records, hasLength(1));
    final usage = history.records.single.usage!;
    expect(usage.model, _model);
    expect(usage.byCall, {
      UsageCallKind.question: _cost(1200, 1024, 150).tokens,
      UsageCallKind.hint: _cost(400, 0, 40).tokens,
      UsageCallKind.grading: _cost(1500, 1024, 300).tokens,
    }, reason: 'the next question was asked after the record was written');
    expect(
      usage.total,
      const TokenUsage(
        promptTokens: 3100,
        cachedTokens: 2048,
        completionTokens: 490,
      ),
    );

    connector.scripts
      ..add(_grade('Goed.', _cost(1400, 1024, 280)))
      ..add(_question('Wanneer stopt een while-lus?', null));
    await tutor().handleStudentMessage('Drie keer.');

    expect(history.records, hasLength(2));
    expect(history.records[1].usage!.byCall, {
      UsageCallKind.question: _cost(1300, 1152, 160).tokens,
      UsageCallKind.grading: _cost(1400, 1024, 280).tokens,
    });
  });

  test('a status report and a refused reply ride along with the next '
      'record', () async {
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn('s1');
    connector.reply = ConnectorOk(
      '<TEXT>Goed bezig.</TEXT><META>{"type":"answer"}</META>',
      usage: _cost(6000, 0, 500),
    );
    connector.scripts
      // The question comes back garbled first: refused, and re-sent.
      ..add([
        StreamFailed(
          StateError('off-script run'),
          StackTrace.current,
          const ChatNotice(ChatNoticeKind.replyGarbled),
          usage: _cost(1200, 1024, 150),
        ),
      ])
      ..add(_question('Wat doet een for-lus?', _cost(1200, 1024, 140)));
    await tutor().requestExercise();

    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);
    connector.scripts
      ..add(_grade('Juist.', _cost(1500, 1024, 300)))
      ..add(_question('Wat telt range(3)?', null));
    await tutor().handleStudentMessage('Hij herhaalt iets.');

    final usage = history.records.single.usage!;
    expect(usage.byCall, {
      UsageCallKind.status: _cost(6000, 0, 500).tokens,
      UsageCallKind.question:
          _cost(1200, 1024, 150).tokens + _cost(1200, 1024, 140).tokens,
      UsageCallKind.grading: _cost(1500, 1024, 300).tokens,
    });
  });

  test('calls that report nothing leave the field off', () async {
    connector.scripts.add(_question('Wat doet een for-lus?', null));
    await tutor().requestExercise();
    connector.scripts
      ..add(_grade('Juist.', null))
      ..add(_question('Wat telt range(3)?', null));
    await tutor().handleStudentMessage('Hij herhaalt iets.');

    expect(history.records.single.usage, isNull);
    expect(
      history.records.single.toMap(uid: 'u1').containsKey('usage'),
      isFalse,
    );
  });

  test('sign-out drops what the student left pending', () async {
    connector.scripts.add(
      _question('Wat doet een for-lus?', _cost(1200, 0, 150)),
    );
    await tutor().requestExercise();

    await pc.read(authServiceProvider.notifier).signOut();
    connector.scripts
      ..add(_grade('Juist.', _cost(1500, 0, 300)))
      ..add(_question('Wat telt range(3)?', null));
    await tutor().handleStudentMessage('Hij herhaalt iets.');

    expect(history.records.single.usage!.byCall, {
      UsageCallKind.grading: _cost(1500, 0, 300).tokens,
    });
  });
}
