// Issue #340 — a follow-up that is still open when the next question comes
// lapses: the answer to that question is the answer to it, not the
// follow-up's.
//
// A follow-up is answered in the chat. "Volgende" under a quiz whose grade
// asked a follow-up (`advanceFromMcq` → `requestExercise`) puts a new
// question up before that, and the follow-up used to stay open through it.
// So did code sent from the editor next to a follow-up of a code exercise,
// until #349: its grade had no plan to be recorded on and asked for the
// next exercise.
//
// The answer to the new question was then graded and recorded as the
// follow-up: `isFollowUp`, capped at weak, no `questionId`, the follow-up's
// `askedAt`, the follow-up's text as its question in `turn_content`, never
// into the bank — and an answer typed in the chat went out as the
// follow-up's answer, on the old question's plan. Now the new question
// keeps its own plan, ID, moment and place in the bank; a follow-up
// answered in the chat while it is open stays a follow-up.
//
// #349 — code sent from the editor while a follow-up is open is the answer
// to that follow-up, as the chat's is: a `follow_up_answer` with the
// follow-up and the code, on the question's plan, recorded as the
// follow-up with the code as its answer and the cost of its grading. It
// was graded as `submit_code` without a plan: recorded nowhere, its cost
// on the next exercise's record.
//
// The real `TutorService`, the real `TurnContentService` and
// `QuestionBankService` over in-memory containers; the connector replays
// canned chunks and records what it was sent, the conductor is mocked and
// the turn history records what it is handed. The turn clock is set by the
// test, so each moment can be told apart.

import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/question_bank/question_bank_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_content_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/mocks.dart';

/// Replays one canned chunk list per streamed request and keeps what each
/// request carried.
class _Connector extends OpenaiConnector {
  final List<List<StreamChunk>> scripts = [];
  final List<String> inputs = [];

  void reply(ChatResponse response, {CallUsage? usage}) => scripts.add([
    const StreamTextDelta('…'),
    StreamCompleted(response, usage: usage),
  ]);

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
    this.inputs.add(input);
    return _next();
  }

  @override
  Stream<StreamChunk> resendRequestStream() => _next();

  /// What request [i] carried.
  Map<String, dynamic> sent(int i) =>
      jsonDecode(inputs[i]) as Map<String, dynamic>;

  /// The `request_type` of request [i].
  String requestType(int i) => sent(i)['request_type'] as String;
}

TokenUsage _tokens(int prompt) =>
    TokenUsage(promptTokens: prompt, completionTokens: prompt ~/ 10);

/// What a call cost, told apart by its size.
CallUsage _cost(int prompt) =>
    CallUsage(model: 'gpt-5-mini', tokens: _tokens(prompt));

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
    Goal? goalOverride,
    bool quizOpen = false,
    bool codeExerciseOpen = false,
    bool chatQuestionOpen = false,
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
}

class _Config extends GlobalConfigService {
  @override
  GlobalConfig? build() => const GlobalConfig(model: 'gpt-5-mini', apiKey: '');
}

class _RecordingHistory extends TurnHistoryService {
  _RecordingHistory() : super(getUid: () => 'u1');

  final List<PersistedTurnRecord> records = [];

  @override
  Future<void> append(PersistedTurnRecord record) async => records.add(record);
}

const _loA = LearningObjective(
  id: 'lo-a',
  statement: 'pick the first colour with an a',
  kind: LoKind.apply,
);
const _loB = LearningObjective(
  id: 'lo-b',
  statement: 'find the warmest temperature',
  kind: LoKind.apply,
);

const _reason = TurnSelectionReason(
  candidateLOs: [],
  chosenReason: 'test',
  notchDropFired: false,
);

QuestionPlan _plan(
  ChatRequestType type,
  LearningObjective lo, {
  QuestionDifficulty difficulty = QuestionDifficulty.medium,
}) => QuestionPlan(
  type: type,
  difficulty: difficulty,
  targetLOs: [lo],
  reason: _reason,
);

/// The follow-up the grader asks under the first question's grade.
const _followUp = FollowUp(
  question:
      'Hoe pas je de code aan zodat je de laatste kleur met een a bewaart?',
);

MultipleChoice _quiz(String prompt, String key) => MultipleChoice(
  type: 'multiple_choice',
  prompt: prompt,
  code: '',
  options: [key, 'iets anders', 'Error'],
  correct: key,
);

McqFeedback _pickGrade(AnswerQuality quality, {FollowUp? followUp}) =>
    McqFeedback(
      type: 'mcq_feedback',
      quality: quality,
      prompt: quality == AnswerQuality.correct ? 'Juist.' : 'Nee.',
      followUp: followUp,
    );

CodeFeedback _codeGrade(AnswerQuality quality, {FollowUp? followUp}) =>
    CodeFeedback(
      type: 'code_feedback',
      quality: quality,
      prompt: quality == AnswerQuality.correct ? 'Juist.' : 'Bijna.',
      suggestion: '',
      followUp: followUp,
    );

final _colours = CompleteCode(
  type: 'complete_code',
  prompt: 'Bewaar de eerste kleur met een a.',
  code: 'for kleur in kleuren:\n    if ___ in kleur:\n        break',
);
final _warmest = CompleteCode(
  type: 'complete_code',
  prompt: 'Zoek de warmste temperatuur.',
  code: 'warmste = temps[0]\nfor t in temps:\n    ___',
);
final _afterThat = CompleteCode(
  type: 'complete_code',
  prompt: 'Nog een.',
  code: 'print(___)',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connector connector;
  late MockConductor conductor;
  late _RecordingHistory history;
  late InMemoryCosmos contentStore;
  late InMemoryCosmos bankStore;
  late TurnContentService contents;
  late QuestionBankService bank;
  late ChatService chat;
  late ProviderContainer pc;
  final graded = <({QuestionPlan plan, GradedAnswer answer})>[];

  // The turn clock, set by each step: when a question comes in, when an
  // answer is graded, when a follow-up goes up.
  var now = DateTime.utc(2026, 10, 14, 9);
  DateTime at(int minute) => now = DateTime.utc(2026, 10, 14, 9, minute);

  final root = Goal(id: 'r1', title: 'Lussen', order: 0);
  final active = Goal(
    id: 's1',
    title: 'Zoeken in een lijst',
    parentId: 'r1',
    order: 1000,
    objectives: const [_loA, _loB],
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
    contentStore = InMemoryCosmos();
    bankStore = InMemoryCosmos();
    contents = TurnContentService(
      container: contentStore.container,
      getUid: () => 'u1',
    );
    bank = QuestionBankService(container: bankStore.container);
    chat = ChatService();
    graded.clear();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);
    // What the session start plans; each test plans its own questions.
    when(() => conductor.planNext())
        .thenAnswer((_) async => _plan(ChatRequestType.mcQuestion, _loA));
    when(
      () => conductor.integrateAnswer(
        plan: any(named: 'plan'),
        answer: any(named: 'answer'),
      ),
    ).thenAnswer((inv) async {
      final answer = inv.namedArguments[#answer] as GradedAnswer;
      graded.add((
        plan: inv.namedArguments[#plan] as QuestionPlan,
        answer: answer,
      ));
      return TurnOutcome(
        overallQuality: answer.overallQuality,
        subgoalAdvanced: false,
        degraded: false,
        loSignals: const [],
        appliedSignals: const [],
        loStatusAfter: const [],
        subgoalProgressAfter: 0.2,
        calibrationBefore: QuestionDifficulty.medium,
        calibrationAfter: QuestionDifficulty.medium,
        hadFallback: answer.hadFallback,
      );
    });

    final goals = MockGoalsService();
    when(() => goals.streamChildren(any())).thenAnswer((_) => Stream.empty());
    when(() => goals.getChildrenOnce(any())).thenAnswer((_) async => [active]);
    final sound = MockSoundService();
    when(() => sound.askQuestion()).thenAnswer((_) async {});

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
        questionBankServiceProvider.overrideWithValue(bank),
        turnContentServiceProvider.overrideWithValue(contents),
        globalConfigServiceProvider.overrideWith(_Config.new),
        turnClockProvider.overrideWithValue(() => now),
      ],
    );
    pc.read(globalConfigServiceProvider);
    pc.read(modeProvider.notifier).state = SessionMode.practice;
    pc.read(tutorServiceProvider.notifier);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  TutorService tutor() => pc.read(tutorServiceProvider.notifier);

  void planNext(QuestionPlan plan) =>
      when(() => conductor.planNext()).thenAnswer((_) async => plan);

  String? bankIdOf(ChatResponse question) =>
      's1_${BankQuestion.contentHashOf(question)}';

  /// The follow-up is up in the chat.
  void expectFollowUpInChat() => expect(
    chat.controller.messages.whereType<TextMessage>().map((m) => m.text),
    contains(_followUp.question),
  );

  test('"Volgende" under a quiz whose follow-up is open: the follow-up '
      'lapses, and the pick on the next quiz is that quiz\'s answer — no '
      'follow-up, its own plan, ID and moment, its own question in '
      'turn_content, and into the bank', () async {
    final first = _quiz('Welke kleur wordt bewaard?', 'rood');
    final next = _quiz('Wat is de warmste temperatuur?', '31');

    at(0);
    planNext(_plan(ChatRequestType.mcQuestion, _loA));
    connector.reply(first);
    await tutor().requestExercise();

    at(2);
    connector.reply(_pickGrade(AnswerQuality.correct, followUp: _followUp));
    await tutor().submitMcqAnswer('rood');
    expect(history.records, hasLength(1));
    expectFollowUpInChat();

    // The student leaves the follow-up and clicks "Volgende".
    at(5);
    final nextPlan = _plan(
      ChatRequestType.mcQuestion,
      _loB,
      difficulty: QuestionDifficulty.hard,
    );
    planNext(nextPlan);
    connector.reply(next);
    await tutor().advanceFromMcq();
    expect(pc.read(activeMcqProvider)?.prompt, next.prompt);

    at(7);
    connector.reply(_pickGrade(AnswerQuality.correct));
    await tutor().submitMcqAnswer('31');
    await contents.idle;
    await bank.idle;

    expect(connector.requestType(3), 'mcq_answer');
    expect(history.records, hasLength(2));
    final record = history.records[1];
    expect(record.isFollowUp, isFalse);
    expect(record.chainDepth, 0);
    expect(record.targetLOIds, ['lo-b']);
    expect(record.difficulty, QuestionDifficulty.hard);
    expect(record.questionId, bankIdOf(next));
    expect(record.askedAt, DateTime.utc(2026, 10, 14, 9, 5));
    expect(graded[1].answer.isFollowUp, isFalse);
    expect(graded[1].plan, same(nextPlan));

    final doc = contentStore[record.id]!;
    expect(doc['isFollowUp'], isFalse);
    expect((doc['question'] as Map)['text'], next.prompt);
    expect((doc['question'] as Map)['questionId'], record.questionId);
    expect(doc['answer'], {'picked': '31'});

    expect(
      bankStore[record.questionId!],
      isNotNull,
      reason: 'a new question answered right goes into the bank',
    );
  });

  test('code sent from the editor while the follow-up of a code exercise is '
      'open is the answer to that follow-up (#349): out as follow_up_answer '
      'with the follow-up and the code, on the question\'s plan; the '
      'follow-up\'s record has the code as its answer and the cost of its '
      'grading; then the next exercise comes, and the code handed in on it '
      'is its own answer', () async {
    at(0);
    final plan = _plan(ChatRequestType.completeCodeQuestion, _loA);
    planNext(plan);
    connector.reply(_colours, usage: _cost(100));
    await tutor().requestExercise();

    at(2);
    connector.reply(
      _codeGrade(AnswerQuality.partial, followUp: _followUp),
      usage: _cost(200),
    );
    await tutor().submitCode('for kleur in kleuren:\n    if "a" in kleur:');
    expect(history.records, hasLength(1));
    expectFollowUpInChat();

    // The student changes the code in the editor and sends it, instead of
    // answering in the chat.
    at(5);
    final nextPlan = _plan(ChatRequestType.completeCodeQuestion, _loB);
    planNext(nextPlan);
    const followUpCode =
        'for kleur in kleuren:\n    if "a" in kleur:\n        laatste = kleur';
    connector
      ..reply(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist: zonder break.',
        ),
        usage: _cost(40),
      )
      ..reply(_warmest, usage: _cost(300));
    await tutor().submitCode(followUpCode);
    await contents.idle;

    final sent = connector.sent(2);
    expect(sent['request_type'], 'follow_up_answer');
    expect(sent['follow_up_question'], _followUp.question);
    expect(sent['code'], followUpCode);
    expect(sent.containsKey('answer'), isFalse);
    expect(sent['chain_depth'], 1);
    expect((sent['target_los'] as List).single['id'], 'lo-a');

    expect(history.records, hasLength(2));
    final followUp = history.records[1];
    expect(followUp.isFollowUp, isTrue);
    expect(followUp.chainDepth, 1);
    expect(followUp.targetLOIds, ['lo-a']);
    expect(followUp.questionId, isNull);
    expect(followUp.askedAt, DateTime.utc(2026, 10, 14, 9, 2));
    expect(followUp.usage?.byCall, {UsageCallKind.followUp: _tokens(40)});
    expect(graded[1].answer.isFollowUp, isTrue);
    expect(graded[1].plan, same(plan));
    final doc = contentStore[followUp.id]!;
    expect(doc['isFollowUp'], isTrue);
    expect(doc['question'], {'text': _followUp.question});
    expect(doc['answer'], {'code': followUpCode});
    expect(doc['feedback'], 'Juist: zonder break.');

    // The next exercise comes, as after a follow-up answered in the chat.
    expect(connector.requestType(3), 'complete_code');

    at(8);
    const answer =
        'warmste = temps[0]\nfor t in temps:\n    warmste = max(t, warmste)';
    connector
      ..reply(_codeGrade(AnswerQuality.correct), usage: _cost(60))
      ..reply(_afterThat);
    await tutor().submitCode(answer);
    await contents.idle;
    await bank.idle;

    expect(connector.requestType(4), 'submit_code');
    expect(history.records, hasLength(3));
    final record = history.records[2];
    expect(record.isFollowUp, isFalse);
    expect(record.chainDepth, 0);
    expect(record.targetLOIds, ['lo-b']);
    expect(record.questionId, bankIdOf(_warmest));
    expect(record.askedAt, DateTime.utc(2026, 10, 14, 9, 5));
    // Its own question and grading — not the follow-up's grading as well.
    expect(record.usage?.byCall, {
      UsageCallKind.question: _tokens(300),
      UsageCallKind.grading: _tokens(60),
    });
    expect(graded[2].answer.isFollowUp, isFalse);
    expect(graded[2].plan, same(nextPlan));

    final next = contentStore[record.id]!;
    expect(next['isFollowUp'], isFalse);
    expect(next['question'], {
      'text': _warmest.prompt,
      'code': _warmest.code,
      'questionId': record.questionId,
    });
    expect(next['answer'], {'code': answer});
    expect(bankStore[record.questionId!], isNotNull);
  });

  test('an answer typed in the chat next to the exercise after "Volgende" '
      'goes out as that exercise\'s answer, on its plan — not as the lapsed '
      'follow-up\'s, on the quiz\'s', () async {
    final explain = ExplainCode(
      type: 'explain_code',
      prompt: 'Wat doet deze lus?',
      code: 'for t in temps:\n    print(t)',
    );

    at(0);
    planNext(_plan(ChatRequestType.mcQuestion, _loA));
    connector.reply(_quiz('Welke kleur wordt bewaard?', 'rood'));
    await tutor().requestExercise();
    at(2);
    connector.reply(_pickGrade(AnswerQuality.wrong, followUp: _followUp));
    await tutor().submitMcqAnswer('iets anders');

    at(5);
    final nextPlan = _plan(ChatRequestType.explainCodeQuestion, _loB);
    planNext(nextPlan);
    connector.reply(explain);
    await tutor().advanceFromMcq();

    at(9);
    connector
      ..reply(
        ExplainFeedback(
          type: 'explain_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
        ),
      )
      ..reply(_afterThat);
    await tutor().handleStudentMessage('Ze toont elke temperatuur.');
    await contents.idle;

    expect(connector.requestType(3), 'explain_answer');
    final record = history.records[1];
    expect(record.isFollowUp, isFalse);
    expect(record.targetLOIds, ['lo-b']);
    expect(record.questionType, 'explainCodeQuestion');
    expect(record.askedAt, DateTime.utc(2026, 10, 14, 9, 5));
    expect(graded[1].plan, same(nextPlan));
    final doc = contentStore[record.id]!;
    expect((doc['question'] as Map)['text'], explain.prompt);
    expect(doc['answer'], {'text': 'Ze toont elke temperatuur.'});
  });

  test(
    'a follow-up answered in the chat while it is open stays a follow-up: '
    'the follow-up\'s moment and text, the question\'s plan, no ID',
    () async {
      at(0);
      final plan = _plan(ChatRequestType.completeCodeQuestion, _loA);
      planNext(plan);
      connector.reply(_colours);
      await tutor().requestExercise();

      at(2);
      connector.reply(_codeGrade(AnswerQuality.partial, followUp: _followUp));
      await tutor().submitCode('for kleur in kleuren:\n    if "a" in kleur:');

      at(6);
      planNext(_plan(ChatRequestType.completeCodeQuestion, _loB));
      connector
        ..reply(
          SocraticFeedback(
            type: 'socratic_feedback',
            quality: AnswerQuality.correct,
            prompt: 'Juist: zonder break.',
          ),
        )
        ..reply(_warmest);
      await tutor().handleStudentMessage('Ik laat de break weg.');
      await contents.idle;

      expect(connector.requestType(2), 'follow_up_answer');
      expect(history.records, hasLength(2));
      final record = history.records[1];
      expect(record.isFollowUp, isTrue);
      expect(record.chainDepth, 1);
      expect(record.targetLOIds, ['lo-a']);
      expect(record.questionId, isNull);
      expect(record.askedAt, DateTime.utc(2026, 10, 14, 9, 2));
      expect(graded[1].answer.isFollowUp, isTrue);
      expect(graded[1].plan, same(plan));
      final doc = contentStore[record.id]!;
      expect(doc['isFollowUp'], isTrue);
      expect(doc['question'], {'text': _followUp.question});
      expect(doc['answer'], {'text': 'Ik laat de break weg.'});
    },
  );
}
