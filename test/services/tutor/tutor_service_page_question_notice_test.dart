// #324 — a student has a question open that they answer by typing in the
// chat (an `explain_code` or socratic exercise, or a follow-up the grader
// asked), reads up in the theory view, and types their answer in the chat
// next to the page. Since #132 that message is a question about the page:
// it is not graded and no next question follows. For the student, "back to
// the question" is the chat, so the answer seemed lost.
//
// The message stays a question about the page — a real question about the
// lesson must never count as the answer — but now:
//
// - the chat says, under the reply, that it did not count as the answer
//   (`ChatNoticeKind.pageQuestionNotAnAnswer`; the chat draws it with a
//   button back to the question);
// - the page question carries the instruction not to give the open
//   question's answer away nor grade it there (`openChatQuestionDirective`);
// - neither appears without such a question waiting: no exercise, a code
//   exercise (answered in the editor), or a quiz that waits for its pick
//   (answered by picking) — what the student types next to those is a
//   question in practice too.
//
// Back in practice the answer is graded as before.
//
// The real `TutorService` and the real `InstructionGenerator` (so the
// system prompt each call carries can be read), over a connector that
// replays canned chunks and records what it was sent, and a mocked
// conductor.

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
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/code_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_chat_core/flutter_chat_core.dart';
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
  kind: LoKind.reason,
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

SocraticQuestion _socratic() =>
    SocraticQuestion(type: 'socratic_question', prompt: 'Waarom optellen?');

ExplainCode _explainCode() => ExplainCode(
  type: 'explain_code',
  prompt: 'Wat drukt deze code af?',
  code: 'print(3 + 4)',
);

WriteCode _writeCode() => WriteCode(
  type: 'write_code',
  prompt: 'Schrijf een programma dat de som van 3 en 4 afdrukt.',
);

MultipleChoice _quiz() => MultipleChoice(
  type: 'multiple_choice',
  prompt: 'Wat drukt print(3 + 4) af?',
  code: 'print(3 + 4)',
  options: const ['7', '34', 'Error'],
  correct: '7',
);

Answer _answer(String text) => Answer(type: 'answer', prompt: text);

/// The opening line of [openChatQuestionDirective].
const _guard = 'OPEN QUESTION — STRICT.';

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
        .thenAnswer((_) async => _plan(ChatRequestType.socraticQuestion));
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

  Map<String, dynamic> sent(int i) =>
      jsonDecode(connector.inputs[i]) as Map<String, dynamic>;

  /// Practice asks for an exercise and [exercise] comes up.
  Future<void> openExercise(ChatResponse exercise, ChatRequestType type) async {
    when(() => conductor.planNext()).thenAnswer((_) async => _plan(type));
    connector.reply(exercise);
    await tutor().requestExercise();
    expect(tutor().hasInFlightExercise(), isTrue);
    expect(tutor().state, TutorState.idle);
  }

  final theory = Object();

  /// The student goes to the theory view, which shows the lesson.
  void toTheory() {
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    pc.read(viewedContentIdProvider.notifier).show(theory, 's1');
  }

  /// The student goes back to practice.
  void toPractice() {
    pc.read(viewedContentIdProvider.notifier).hide(theory);
    pc.read(modeProvider.notifier).state = SessionMode.practice;
  }

  /// What the chat shows last.
  Message last() => chat.controller.messages.last;

  bool isNotAnAnswer(Message m) =>
      m is SystemMessage &&
      ChatNotice.fromJson(m.metadata?[ChatNotice.metadataKey])?.kind ==
          ChatNoticeKind.pageQuestionNotAnAnswer;

  /// How often the chat said a message did not count as the answer.
  int notAnAnswerCount() =>
      chat.controller.messages.where(isNotAnAnswer).length;

  for (final (name, exercise, type, practiceType, grade) in [
    (
      'socratic',
      _socratic(),
      ChatRequestType.socraticQuestion,
      'socratic_feedback',
      SocraticFeedback(
        type: 'socratic_feedback',
        quality: AnswerQuality.correct,
        prompt: 'Juist.',
      ),
    ),
    (
      'explain_code',
      _explainCode(),
      ChatRequestType.explainCodeQuestion,
      'explain_answer',
      ExplainFeedback(
        type: 'explain_feedback',
        quality: AnswerQuality.correct,
        prompt: 'Juist.',
      ),
    ),
  ]) {
    test('an answer to a waiting $name question typed next to the page is a '
        'page question, with the instruction not to give that answer away; '
        'the chat says under the reply that it did not count; back in '
        'practice it is graded', () async {
      await openExercise(exercise, type);
      toTheory();

      connector.reply(_answer('Op deze pagina gaat het over print.'));
      await tutor().handleStudentMessage('Het drukt 7 af.');

      expect(sent(1)['request_type'], 'content_question');
      expect(sent(1)['question'], 'Het drukt 7 af.');
      final prompt = connector.instructions[1];
      expect(prompt, contains(openChatQuestionDirective));
      expect(
        prompt.indexOf(_guard),
        greaterThan(prompt.indexOf('### CONTENT QUESTION')),
      );
      expect(
        prompt.indexOf(_guard),
        lessThan(prompt.indexOf('OUTPUT LANGUAGE')),
      );
      // The exercise's own request never had it.
      expect(connector.instructions[0], isNot(contains(_guard)));

      // Under the reply, the last thing in the chat.
      expect(isNotAnAnswer(last()), isTrue);
      final at = chat.controller.messages.indexWhere(isNotAnAnswer);
      expect(chat.controller.messages[at - 1].authorId, 'Teacher');
      expect(notAnAnswerCount(), 1);

      // Nothing graded; the question still waits.
      expect(graded, isEmpty);
      expect(history.records, isEmpty);
      expect(tutor().hasInFlightExercise(), isTrue);
      expect(tutor().state, TutorState.idle);

      // Back in practice the answer goes to the grader, without the
      // instruction and without the notice.
      toPractice();
      connector
        ..reply(grade)
        ..reply(_socratic());
      await tutor().handleStudentMessage('Het drukt 7 af.');

      expect(sent(2)['request_type'], practiceType);
      expect(sent(2)['answer'], 'Het drukt 7 af.');
      expect(connector.instructions[2], isNot(contains(_guard)));
      expect(graded, hasLength(1));
      expect(notAnAnswerCount(), 1);
    });
  }

  test('a follow-up the grader asked is a question that waits in the chat '
      'too: the page question gets the instruction and the notice, next '
      'to the code-exercise one', () async {
    await openExercise(_writeCode(), ChatRequestType.writeCodeQuestion);
    connector.reply(
      CodeFeedback(
        type: 'code_feedback',
        prompt: 'Bijna.',
        suggestion: '',
        quality: AnswerQuality.partial,
        followUp: const FollowUp(question: 'Wat drukt print(3 + 4) af?'),
      ),
    );
    await tutor().submitCode('print(3 + 4)');
    expect(sent(1)['request_type'], 'submit_code');
    toTheory();

    connector.reply(_answer('Print toont wat tussen de haakjes staat.'));
    await tutor().handleStudentMessage('7');

    expect(sent(2)['request_type'], 'content_question');
    expect(connector.instructions[2], contains(_guard));
    expect(connector.instructions[2], contains('OPEN CODE EXERCISE — STRICT.'));
    expect(isNotAnAnswer(last()), isTrue);
    expect(history.records, hasLength(1), reason: 'only the code was graded');

    // Back in practice the follow-up answer is graded.
    toPractice();
    connector
      ..reply(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
        ),
      )
      ..reply(_socratic());
    await tutor().handleStudentMessage('7');
    expect(sent(3)['request_type'], 'follow_up_answer');
    expect(connector.instructions[3], isNot(contains(_guard)));
    expect(history.records, hasLength(2));
    expect(history.records[1].isFollowUp, isTrue);
  });

  test('without an exercise a page question gets neither', () async {
    toTheory();
    connector.reply(_answer('Print toont iets.'));
    await tutor().handleStudentMessage('Wat doet print?');

    expect(sent(0)['request_type'], 'content_question');
    expect(connector.instructions[0], isNot(contains(_guard)));
    expect(notAnAnswerCount(), 0);
  });

  test('a code exercise is answered in the editor: a page question next to '
      'it gets neither', () async {
    await openExercise(_writeCode(), ChatRequestType.writeCodeQuestion);
    toTheory();
    connector.reply(_answer('Print toont iets.'));
    await tutor().handleStudentMessage('Wat doet print?');

    expect(sent(1)['request_type'], 'content_question');
    expect(connector.instructions[1], isNot(contains(_guard)));
    expect(notAnAnswerCount(), 0);
  });

  test('a quiz is answered by picking: a page question while it waits for '
      'its pick gets neither', () async {
    await openExercise(_quiz(), ChatRequestType.mcQuestion);
    toTheory();
    connector.reply(_answer('Print toont iets.'));
    await tutor().handleStudentMessage('7');

    expect(sent(1)['request_type'], 'content_question');
    expect(connector.instructions[1], isNot(contains(_guard)));
    expect(connector.instructions[1], contains('OPEN QUIZ — STRICT.'));
    expect(notAnAnswerCount(), 0);
  });

  test('in practice the answer to a waiting question is graded, with no '
      'notice', () async {
    await openExercise(_socratic(), ChatRequestType.socraticQuestion);
    connector
      ..reply(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
        ),
      )
      ..reply(_socratic());
    await tutor().handleStudentMessage('Omdat + optelt.');

    expect(sent(1)['request_type'], 'socratic_feedback');
    expect(notAnAnswerCount(), 0);
  });
}
