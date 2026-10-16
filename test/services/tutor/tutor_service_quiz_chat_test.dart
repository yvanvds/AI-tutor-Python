// #271 — the chat stays open while a multiple-choice question (a quiz) is
// open, so what the student types there has to go somewhere sensible. It
// used to be unreachable: the chat was hidden with a quiz pending (#122), and
// `handleStudentMessage` routed anything typed while the exercise was a quiz
// to the grader as its answer.
//
// Now a quiz is answered by the option the student picks and by nothing
// else:
//
// - Next to a quiz that waits for its pick, a message is a question, as
//   during any other exercise: a `student_question` carrying the quiz as it
//   is on screen (`open_quiz`, its options under the letters the student
//   sees), with the open-quiz instruction not to give the answer away.
//   Nothing is graded, and the quiz, its plan and the exercise in flight are
//   as they were: the pick that follows is graded as always.
// - In the theory view with the page on screen it is a question about the
//   page (#132), with the same instruction: the quiz waits behind it.
// - The `?` hint next to a quiz is about the quiz, not about the code left
//   in the editor from the exercise before.
// - After the pick, a follow-up the grader asked under the feedback is
//   answered in the chat and graded as that follow-up, as for any exercise;
//   the next exercise then takes the quiz's place. A follow-up left over
//   from an exercise before the quiz does not take a message typed next to
//   it.
// - The quiz takes no pick while the tutor is still answering a question.
//
// The real `TutorService` and the real `InstructionGenerator` (so the
// system prompt each call carries can be read), over a connector that
// replays canned chunks and records what it was sent, and a mocked
// conductor.

import 'dart:async';
import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/session/viewed_content_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/question_bank/question_bank_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_content_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:ai_tutor_python/services/tutor/responses/mcq_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/mocks.dart';

/// Replays one canned stream per request and keeps what each one carried.
class _Connector extends OpenaiConnector {
  final List<Stream<StreamChunk>> scripts = [];
  final List<String> inputs = [];
  final List<String> instructions = [];

  void reply(ChatResponse response) => scripts.add(
    Stream.fromIterable([
      const StreamTextDelta('…'),
      StreamCompleted(response),
    ]),
  );

  @override
  Stream<StreamChunk> sendRequestStream({
    required String instructions,
    required String input,
    PreviousInputs inputs = PreviousInputs.includeSession,
  }) {
    this.inputs.add(input);
    this.instructions.add(instructions);
    return _next();
  }

  @override
  Stream<StreamChunk> resendRequestStream() => _next();

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
    return scripts.removeAt(0);
  }
}

/// No teacher docs: the prompt is the app's own parts only.
class _NoInstructions extends InstructionsService {
  @override
  List<Instruction> build() => const [];

  @override
  Future<List<Instruction>> getAll() async => const [];
}

class _PresetSelection extends GoalSelectionNotifier {
  _PresetSelection(this.root, this.child);
  final Goal root;
  final Goal child;

  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: root, selectedChild: child);
}

class _FixedContent extends ContentService {
  _FixedContent(this.docs);
  final List<Content> docs;

  @override
  List<Content> build() => docs;
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

const _lo = LearningObjective(
  id: 'lo-1',
  statement: 'print a sum',
  kind: LoKind.predict,
);

const _reason = TurnSelectionReason(
  candidateLOs: [],
  chosenReason: 'test',
  notchDropFired: false,
);

QuestionPlan _plan(ChatRequestType type) => QuestionPlan(
  type: type,
  difficulty: QuestionDifficulty.medium,
  targetLOs: const [_lo],
  reason: _reason,
);

const _prompt = 'Wat drukt print(1 + 1) af?';
const _code = 'print(1 + 1)';
const _key = '2';

MultipleChoice _quiz({String prompt = _prompt}) => MultipleChoice(
  type: 'multiple_choice',
  prompt: prompt,
  code: _code,
  options: const [_key, '11', 'Error'],
  correct: _key,
);

McqFeedback _grade({
  AnswerQuality quality = AnswerQuality.wrong,
  String text = 'Nee: + telt hier op.',
  FollowUp? followUp,
}) => McqFeedback(
  type: 'mcq_feedback',
  quality: quality,
  prompt: text,
  followUp: followUp,
);

Answer _answer(String text) => Answer(type: 'answer', prompt: text);

/// The opening line of [openQuizDirective].
const _guard = 'OPEN QUIZ — STRICT.';

/// The opening line of [answerKeyDirective].
const _keyGuard = 'ANSWER KEY — STRICT.';

const String _pageBody =
    '<h2>Print</h2>'
    '<p>Zo toon je iets op het scherm.</p>'
    '<pre class="run"><code>print("Hallo")</code></pre>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Connector connector;
  late MockConductor conductor;
  late _RecordingHistory history;
  late ChatService chat;
  late ProviderContainer pc;
  final graded = <GradedAnswer>[];

  final root = Goal(id: 'r1', title: 'Basics', order: 0);
  final active = Goal(
    id: 's1',
    title: 'Print',
    parentId: 'r1',
    order: 1000,
    contentId: 's1',
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    connector = _Connector();
    history = _RecordingHistory();
    chat = ChatService();
    graded.clear();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);
    when(() => conductor.planNext())
        .thenAnswer((_) async => _plan(ChatRequestType.mcQuestion));
    when(
      () => conductor.integrateAnswer(
        plan: any(named: 'plan'),
        answer: any(named: 'answer'),
      ),
    ).thenAnswer((inv) async {
      final answer = inv.namedArguments[#answer] as GradedAnswer;
      graded.add(answer);
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
            instructionGeneratorOverride: InstructionGenerator(),
          ),
        ),
        appLocaleProvider.overrideWith((_) => const Locale('nl')),
        authServiceProvider.overrideWith(_SignedIn.new),
        chatServiceProvider.overrideWithValue(chat),
        instructionsServiceProvider.overrideWith(_NoInstructions.new),
        goalsServiceProvider.overrideWithValue(goals),
        goalSelectionProvider.overrideWith(
          () => _PresetSelection(root, active),
        ),
        contentServiceProvider.overrideWith(
          () => _FixedContent([
            Content(id: 's1', title: 'Print', body: _pageBody),
          ]),
        ),
        translationServiceProvider.overrideWithValue(
          TranslationService(
            container: InMemoryCosmos.partitioned('language', []).container,
          ),
        ),
        soundServiceProvider.overrideWithValue(sound),
        turnHistoryServiceProvider.overrideWithValue(history),
        questionBankServiceProvider.overrideWithValue(
          QuestionBankService(container: InMemoryCosmos().container),
        ),
        turnContentServiceProvider.overrideWithValue(
          TurnContentService(
            container: InMemoryCosmos().container,
            getUid: () => 'u1',
          ),
        ),
        globalConfigServiceProvider.overrideWith(_Config.new),
      ],
    );
    pc.read(globalConfigServiceProvider);
    pc.read(modeProvider.notifier).state = SessionMode.practice;
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  TutorService tutor() => pc.read(tutorServiceProvider.notifier);
  ActiveMcq? quiz() => pc.read(activeMcqProvider);

  Map<String, dynamic> sent(int i) =>
      jsonDecode(connector.inputs[i]) as Map<String, dynamic>;

  /// Practice asks for an exercise and the quiz comes up, waiting for its
  /// pick.
  Future<void> openQuiz({String prompt = _prompt}) async {
    connector.reply(_quiz(prompt: prompt));
    await tutor().requestExercise();
    expect(quiz()?.prompt, prompt);
    expect(quiz()?.selected, isNull);
  }

  /// The options as the quiz shows them: shuffled, under A, B, C.
  Map<String, String> onScreen() => {
    for (var i = 0; i < quiz()!.options.length; i++)
      'ABC'[i]: quiz()!.options[i],
  };

  test('a message next to a quiz that waits for its pick is a question: it '
      'carries the quiz as on screen and the instruction not to give the '
      'answer away, nothing is graded, and the quiz is as it was', () async {
    await openQuiz();
    final before = quiz();

    connector.reply(_answer('Kijk naar wat + doet met twee getallen.'));
    // Even what reads like an answer: the answer is the pick.
    await tutor().handleStudentMessage('Is het B?');

    final asked = sent(1);
    expect(asked['request_type'], 'student_question');
    expect(asked['question'], 'Is het B?');
    expect(asked['open_quiz'], {
      'question': _prompt,
      'code': _code,
      'options': onScreen(),
    });
    expect(asked.containsKey('answer'), isFalse);
    expect(asked.containsKey('correct_option'), isFalse);
    expect(connector.inputs[1], isNot(contains('"correct"')));
    expect(connector.instructions[1], contains(_guard));
    expect(connector.instructions[1], isNot(contains(_keyGuard)));
    // Before the language directive, which stays last (#117).
    expect(
      connector.instructions[1].indexOf(_guard),
      lessThan(connector.instructions[1].indexOf('OUTPUT LANGUAGE')),
    );

    expect(graded, isEmpty, reason: 'a question is not graded');
    expect(history.records, isEmpty);
    expect(quiz(), same(before), reason: 'the quiz must be untouched');
    expect(tutor().hasInFlightExercise(), isTrue);
    expect(tutor().state, TutorState.idle);
    expect(chat.tutorMessageCount.value, 1);
  });

  test('the pick that follows is graded as always: its key goes to the '
      'grader, without the open-quiz instruction', () async {
    await openQuiz();
    connector.reply(_answer('Kijk naar de +.'));
    await tutor().handleStudentMessage('Wat betekent print?');

    connector.reply(_grade(quality: AnswerQuality.correct, text: 'Juist.'));
    await tutor().submitMcqAnswer(_key);

    final pick = sent(2);
    expect(pick['request_type'], 'mcq_answer');
    expect(pick['answer'], _key);
    expect(pick['correct_option'], _key);
    expect(pick.containsKey('open_quiz'), isFalse);
    expect(connector.instructions[2], contains(_keyGuard));
    expect(connector.instructions[2], isNot(contains(_guard)));
    expect(graded.single.overallQuality, AnswerQuality.correct);
    expect(history.records, hasLength(1));
    expect(quiz()?.feedback, 'Juist.');
  });

  test('a question after the pick names the letter picked, and still gets '
      'the instruction', () async {
    await openQuiz();
    connector.reply(_grade());
    await tutor().submitMcqAnswer('11');
    final letter = onScreen().entries.firstWhere((e) => e.value == '11').key;

    connector.reply(_answer('Een + tussen getallen telt op.'));
    await tutor().handleStudentMessage('Waarom is dat fout?');

    final asked = sent(2);
    expect(asked['request_type'], 'student_question');
    expect((asked['open_quiz'] as Map)['picked'], letter);
    expect(connector.instructions[2], contains(_guard));
    expect(graded, hasLength(1), reason: 'only the pick was graded');
  });

  test('in the theory view with the page on screen it is a question about '
      'the page, with the instruction: the quiz waits behind it', () async {
    await openQuiz();
    final before = quiz();
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    pc.read(viewedContentIdProvider.notifier).show(Object(), 's1');

    connector.reply(_answer('Met print toon je iets.'));
    await tutor().handleStudentMessage('Wat doet print?');

    final asked = sent(1);
    expect(asked['request_type'], 'content_question');
    expect(asked['content_title'], 'Print');
    expect(asked.containsKey('open_quiz'), isFalse);
    expect(connector.instructions[1], contains('### CONTENT QUESTION'));
    expect(connector.instructions[1], contains(_guard));
    expect(graded, isEmpty);
    expect(quiz(), same(before));
  });

  test(
    'in the theory view without a page it is a question about the quiz',
    () async {
      await openQuiz();
      pc.read(modeProvider.notifier).state = SessionMode.explain;

      connector.reply(_answer('Kijk naar de +.'));
      await tutor().handleStudentMessage('Ik snap de vraag niet.');

      expect(sent(1)['request_type'], 'student_question');
      expect(sent(1)['open_quiz'], isNotNull);
      expect(connector.instructions[1], contains(_guard));
      expect(graded, isEmpty);
    },
  );

  test('without a quiz a question gets no quiz and no instruction', () async {
    connector.reply(_answer('Daarom.'));
    await tutor().handleStudentMessage('Hoe zit dat?');

    expect(sent(0)['request_type'], 'student_question');
    expect(sent(0).containsKey('open_quiz'), isFalse);
    expect(connector.instructions[0], isNot(contains(_guard)));
  });

  test('the ? hint next to a quiz is about the quiz: no leftover editor code, '
      'the quiz, and the instruction', () async {
    await openQuiz();

    connector.reply(Hint(type: 'hint', prompt: 'Denk aan wat + doet.'));
    await tutor().requestHint('naam = "oud"');

    final hint = sent(1);
    expect(hint['request_type'], 'request_hint');
    expect(hint['current_code'], '');
    expect(hint['open_quiz'], {
      'question': _prompt,
      'code': _code,
      'options': onScreen(),
    });
    expect(connector.instructions[1], contains(_guard));
    expect(quiz()?.selected, isNull);
  });

  test('after the pick, the follow-up asked under the feedback is answered in '
      'the chat and graded as that follow-up; the next exercise takes the '
      'quiz\'s place', () async {
    await openQuiz();
    connector.reply(
      _grade(followUp: const FollowUp(question: 'En print("1" + "1")?')),
    );
    await tutor().submitMcqAnswer('11');
    expect(quiz()?.feedback, isNotNull);

    when(() => conductor.planNext())
        .thenAnswer((_) async => _plan(ChatRequestType.socraticQuestion));
    connector
      ..reply(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.partial,
          prompt: 'Bijna: dat wordt 11.',
        ),
      )
      ..reply(SocraticQuestion(type: 'socratic_question', prompt: 'Waarom?'));
    await tutor().handleStudentMessage('Ook 2.');

    expect(sent(2)['request_type'], 'follow_up_answer');
    expect(sent(2)['answer'], 'Ook 2.');
    expect(connector.instructions[2], isNot(contains(_guard)));
    expect(history.records, hasLength(2));
    expect(history.records[1].isFollowUp, isTrue);
    expect(sent(3)['request_type'], 'socratic_question');
    expect(
      quiz(),
      isNull,
      reason: 'the answered quiz must not stay over the next exercise',
    );
    expect(connector.scripts, isEmpty);
  });

  test('a follow-up left over from before the quiz does not take a message '
      'typed next to it: that is a question about the quiz', () async {
    // A quiz answered with a follow-up the student left for "Volgende".
    await openQuiz(prompt: 'Eerste');
    connector.reply(
      _grade(followUp: const FollowUp(question: 'En print("1" + "1")?')),
    );
    await tutor().submitMcqAnswer('11');
    connector.reply(_quiz(prompt: 'Tweede'));
    await tutor().advanceFromMcq();
    expect(quiz()?.prompt, 'Tweede');

    connector.reply(_answer('Kijk naar de +.'));
    await tutor().handleStudentMessage('Wat vraagt deze?');

    expect(sent(3)['request_type'], 'student_question');
    expect((sent(3)['open_quiz'] as Map)['question'], 'Tweede');
    expect(history.records, hasLength(1), reason: 'only the first pick');
    expect(quiz()?.prompt, 'Tweede');
    expect(quiz()?.selected, isNull);
  });

  test('the quiz takes no pick while the tutor is still answering a '
      'question: it would not be graded', () async {
    await openQuiz();
    final reply = StreamController<StreamChunk>();
    connector.scripts.add(reply.stream);
    final asking = tutor().handleStudentMessage('Wat is print?');
    await Future<void>.delayed(Duration.zero);
    expect(tutor().state, TutorState.working);

    await tutor().submitMcqAnswer(_key);
    expect(quiz()?.selected, isNull, reason: 'a pick that cannot be graded');

    reply
      ..add(const StreamTextDelta('…'))
      ..add(StreamCompleted(_answer('Print toont iets.')));
    await reply.close();
    await asking;
    expect(tutor().state, TutorState.idle);

    connector.reply(_grade(quality: AnswerQuality.correct, text: 'Juist.'));
    await tutor().submitMcqAnswer(_key);
    expect(quiz()?.selected, _key);
    expect(sent(2)['request_type'], 'mcq_answer');
    expect(quiz()?.feedback, 'Juist.');
  });
}
