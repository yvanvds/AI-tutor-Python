// #273 — a message typed in the chat during a code exercise (`write_code`,
// `complete_code`) is a question: the student hands in their code through
// the editor. The question's system prompt is the teacher's
// `studentQuestion` doc plus the app's own parts, and nothing in it said not
// to hand over the solution — the exercise is in the history the call
// carries, so "write the code for me" could get the code.
//
// Now the app appends its own instruction (`openCodeExerciseDirective`)
// while a code exercise is in flight:
//
// - to a question typed next to the exercise (`student_question`), and to a
//   question about the theory page while the exercise waits behind it
//   (`content_question`);
// - never to a grading call: the code handed in, a follow-up answer after
//   its grade, or the answer to an `explain_code` or socratic exercise,
//   which is what the student types in the chat there;
// - not once the exercise is gone: the next exercise decides.
//
// Nothing is graded and nothing on the conductor side moves for a
// question, as before.
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
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/grader_payload.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';
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

/// The teacher's question doc as it is: explain, freely. The guard has to
/// hold against it.
class _TeacherDocs extends InstructionsService {
  static final _docs = [
    Instruction(
      id: 'studentQuestion',
      sections: const {
        'main': 'If question is about Python → give a clear explanation.',
      },
      updatedAt: DateTime.utc(2026, 10, 16),
    ),
  ];

  @override
  List<Instruction> build() => _docs;

  @override
  Future<List<Instruction>> getAll() async => _docs;
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
  kind: LoKind.apply,
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

WriteCode _writeCode() => WriteCode(
  type: 'write_code',
  prompt: 'Schrijf een programma dat de som van 3 en 4 afdrukt.',
);

CompleteCode _completeCode() => CompleteCode(
  type: 'complete_code',
  prompt: 'Vul het ontbrekende stuk in.',
  code: 'som = 3 + 4\nprint(___)',
);

CodeFeedback _codeGrade({
  AnswerQuality quality = AnswerQuality.correct,
  FollowUp? followUp,
}) => CodeFeedback(
  type: 'code_feedback',
  prompt: 'Goed zo.',
  suggestion: '',
  quality: quality,
  followUp: followUp,
);

Answer _answer(String text) => Answer(type: 'answer', prompt: text);

/// The opening line of [openCodeExerciseDirective].
const _guard = 'OPEN CODE EXERCISE — STRICT.';

/// The opening line of [openQuizDirective].
const _quizGuard = 'OPEN QUIZ — STRICT.';

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
        .thenAnswer((_) async => _plan(ChatRequestType.writeCodeQuestion));
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
        instructionsServiceProvider.overrideWith(_TeacherDocs.new),
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

  for (final (name, exercise, type) in [
    ('write_code', _writeCode(), ChatRequestType.writeCodeQuestion),
    ('complete_code', _completeCode(), ChatRequestType.completeCodeQuestion),
  ]) {
    test('a message during a $name exercise is a question: it carries the '
        'instruction not to hand over the solution, after the teacher\'s doc, '
        'and nothing is graded', () async {
      await openExercise(exercise, type);

      connector.reply(_answer('Welke functie toont iets op het scherm?'));
      await tutor().handleStudentMessage('Schrijf de code voor mij.');

      expect(sent(1)['request_type'], 'student_question');
      expect(sent(1)['question'], 'Schrijf de code voor mij.');
      final prompt = connector.instructions[1];
      expect(prompt, contains(openCodeExerciseDirective));
      expect(
        prompt.indexOf(_guard),
        greaterThan(prompt.indexOf('give a clear explanation')),
      );
      // Before the language directive, which stays last (#117).
      expect(
        prompt.indexOf(_guard),
        lessThan(prompt.indexOf('OUTPUT LANGUAGE')),
      );
      expect(prompt, isNot(contains(_quizGuard)));
      // The exercise's own request never had it.
      expect(connector.instructions[0], isNot(contains(_guard)));

      expect(graded, isEmpty, reason: 'a question is not graded');
      expect(history.records, isEmpty);
      expect(tutor().hasInFlightExercise(), isTrue);
      expect(tutor().state, TutorState.idle);
    });
  }

  test('in the theory view with the page on screen it is a question about '
      'the page, with the instruction: the exercise waits behind it; the code '
      'handed in afterwards is graded without it', () async {
    await openExercise(_completeCode(), ChatRequestType.completeCodeQuestion);
    final theory = Object();
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    pc.read(viewedContentIdProvider.notifier).show(theory, 's1');

    connector.reply(_answer('Met print toon je iets.'));
    await tutor().handleStudentMessage('Wat moet er op de lijn?');

    expect(sent(1)['request_type'], 'content_question');
    expect(sent(1)['content_title'], 'Print');
    expect(connector.instructions[1], contains('### CONTENT QUESTION'));
    expect(connector.instructions[1], contains(_guard));
    expect(graded, isEmpty);

    // Back in practice the exercise is still the one in flight, and the
    // code handed in goes to the grader as always — without the guard.
    pc.read(viewedContentIdProvider.notifier).hide(theory);
    pc.read(modeProvider.notifier).state = SessionMode.practice;
    when(() => conductor.planNext())
        .thenAnswer((_) async => _plan(ChatRequestType.writeCodeQuestion));
    connector
      ..reply(_codeGrade())
      ..reply(_writeCode());
    await tutor().submitCode('som = 3 + 4\nprint(som)');

    expect(sent(2)['request_type'], 'submit_code');
    expect(connector.instructions[2], isNot(contains(_guard)));
    expect(graded.single.overallQuality, AnswerQuality.correct);
    expect(sent(3)['request_type'], 'write_code');
    expect(connector.instructions[3], isNot(contains(_guard)));
  });

  test('a follow-up the grader asked about the code is answered in the chat '
      'and graded without the instruction', () async {
    await openExercise(_writeCode(), ChatRequestType.writeCodeQuestion);
    connector.reply(
      _codeGrade(
        quality: AnswerQuality.partial,
        followUp: const FollowUp(question: 'Wat drukt print(3 + 4) af?'),
      ),
    );
    await tutor().submitCode('print(3 + 4)');
    expect(sent(1)['request_type'], 'submit_code');

    when(() => conductor.planNext())
        .thenAnswer((_) async => _plan(ChatRequestType.socraticQuestion));
    connector
      ..reply(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
        ),
      )
      ..reply(SocraticQuestion(type: 'socratic_question', prompt: 'Waarom?'));
    await tutor().handleStudentMessage('7');

    expect(sent(2)['request_type'], 'follow_up_answer');
    expect(sent(2)['answer'], '7');
    expect(connector.instructions[2], isNot(contains(_guard)));
    expect(history.records, hasLength(2));
    expect(history.records[1].isFollowUp, isTrue);
  });

  test('an explain_code or socratic exercise is answered in the chat: the '
      'message goes to its grader, without the instruction', () async {
    await openExercise(
      ExplainCode(
        type: 'explain_code',
        prompt: 'Wat doet deze code?',
        code: 'print(3 + 4)',
      ),
      ChatRequestType.explainCodeQuestion,
    );
    when(() => conductor.planNext())
        .thenAnswer((_) async => _plan(ChatRequestType.socraticQuestion));
    connector
      ..reply(
        ExplainFeedback(
          type: 'explain_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
        ),
      )
      ..reply(SocraticQuestion(type: 'socratic_question', prompt: 'Waarom?'));
    await tutor().handleStudentMessage('Het drukt 7 af.');

    expect(sent(1)['request_type'], 'explain_answer');
    expect(connector.instructions[1], isNot(contains(_guard)));
    expect(sent(2)['request_type'], 'socratic_question');

    connector
      ..reply(
        SocraticFeedback(
          type: 'socratic_feedback',
          quality: AnswerQuality.correct,
          prompt: 'Juist.',
        ),
      )
      ..reply(SocraticQuestion(type: 'socratic_question', prompt: 'En nu?'));
    await tutor().handleStudentMessage('Omdat + optelt.');

    expect(sent(3)['request_type'], 'socratic_feedback');
    expect(connector.instructions[3], isNot(contains(_guard)));
    expect(graded, hasLength(2));
  });

  test(
    'once the code is graded the next exercise decides: a question next '
    'to the quiz that follows gets the quiz instruction, not this one',
    () async {
      await openExercise(_writeCode(), ChatRequestType.writeCodeQuestion);
      when(() => conductor.planNext())
          .thenAnswer((_) async => _plan(ChatRequestType.mcQuestion));
      connector
        ..reply(_codeGrade())
        ..reply(
          MultipleChoice(
            type: 'multiple_choice',
            prompt: 'Wat drukt print(3 + 4) af?',
            code: 'print(3 + 4)',
            options: const ['7', '34', 'Error'],
            correct: '7',
          ),
        );
      await tutor().submitCode('print(3 + 4)');
      expect(sent(2)['request_type'], 'multiple_choice');

      connector.reply(_answer('Kijk naar de +.'));
      await tutor().handleStudentMessage('Wat betekent +?');

      expect(sent(3)['request_type'], 'student_question');
      expect(connector.instructions[3], contains(_quizGuard));
      expect(connector.instructions[3], isNot(contains(_guard)));
    },
  );

  test('without an exercise a question gets no instruction', () async {
    connector.reply(_answer('Daarom.'));
    await tutor().handleStudentMessage('Hoe zit dat?');

    expect(sent(0)['request_type'], 'student_question');
    expect(connector.instructions[0], isNot(contains(_guard)));
  });
}
