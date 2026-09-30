// #132 — where a message the student types goes. `handleStudentMessage`
// used to route on the follow-up and exercise type in flight only, so a
// question typed on a theory page while a practice question was pending
// was graded as its answer. Now: theory view on screen with a page in it →
// a `content_question` carrying that page, and nothing else moves — the
// pending question is still graded as before when the student comes back
// and answers it. Any other situation routes as it always did.
//
// The page goes out in the language it is shown in (#207): the translation
// into the app language when the lesson has one, else the Dutch text the
// page falls back to.
//
// The real `TutorService` over a scripted connector (canned stream chunks)
// and a mocked conductor; the instruction generator is a stand-in that
// records what it was asked for, so the subgoal the prompt is written for
// can be asserted without assembling a prompt. Translations come from the
// real `TranslationService` over an in-memory `translations` container.

import 'dart:convert';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/session/viewed_content_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide Answer;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/mocks.dart';

/// Replays one canned chunk list per request and keeps every request.
class _RecordingConnector extends OpenaiConnector {
  final List<List<StreamChunk>> scripts = [];
  final List<String> inputs = [];

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
}

/// Records the type and the subgoal override of every prompt asked for.
class _RecordingGenerator extends InstructionGenerator {
  final List<({ChatRequestType type, Goal? override})> asked = [];

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
  }) async {
    asked.add((type: type, override: subgoalOverride));
    return 'system prompt';
  }
}

class _NoInstructions extends InstructionsService {
  @override
  List<Instruction> build() => const [];
}

/// The content cache as the theory view reads it: filled, no polling.
class _FixedContent extends ContentService {
  _FixedContent(this.docs);
  final List<Content> docs;

  @override
  List<Content> build() => docs;
}

class _PresetSelection extends GoalSelectionNotifier {
  _PresetSelection(this.root, this.child);
  final Goal root;
  final Goal child;

  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: root, selectedChild: child);
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

const String kPrintBody =
    '<h2>Print</h2>'
    '<p>Zo toon je iets op het scherm.</p>'
    '<pre class="run"><code>print("Hallo", naam)</code></pre>';

const String kPrintBodyEn =
    '<h2>Printing</h2>'
    '<p>This is how you show something on the screen.</p>'
    '<pre class="run"><code>print("Hello", name)</code></pre>';

final _print = Content(id: 's1', title: 'Print', body: kPrintBody);

/// Stands in for the language picked on the Options page.
final _locale = StateProvider<Locale>((_) => const Locale('nl'));

void main() {
  // The locale the prompt is asked for comes from SharedPreferences.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingConnector connector;
  late _RecordingGenerator generator;
  late MockConductor conductor;
  late MockGoalsService goals;
  late ChatService chat;
  late InMemoryCosmos translations;
  late ProviderContainer pc;

  final root = Goal(id: 'r1', title: 'Basics', order: 0);
  final older = Goal(
    id: 's0',
    title: 'Intro',
    parentId: 'r1',
    order: 500,
    contentId: 's0',
  );
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
    connector = _RecordingConnector();
    generator = _RecordingGenerator();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.planNext()).thenAnswer((_) async => _plan);
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);

    goals = MockGoalsService();
    when(() => goals.streamChildren(any())).thenAnswer((_) => Stream.empty());
    when(() => goals.getChildrenOnce(any()))
        .thenAnswer((_) async => [older, active]);

    final sound = MockSoundService();
    when(() => sound.askQuestion()).thenAnswer((_) async {});

    chat = ChatService();
    translations = InMemoryCosmos.partitioned('language', [
      Translation.content(
        language: 'en',
        contentId: 's1',
        title: 'Printing',
        body: kPrintBodyEn,
        sourceHash: contentSourceHash(_print),
      ).toMap(),
    ]);
    pc = ProviderContainer(
      overrides: [
        appLocaleProvider.overrideWith((ref) => ref.watch(_locale)),
        translationServiceProvider.overrideWithValue(
          TranslationService(container: translations.container),
        ),
        tutorServiceProvider.overrideWith(
          () => TutorService(
            connectorOverride: connector,
            conductorOverride: conductor,
            instructionGeneratorOverride: generator,
          ),
        ),
        chatServiceProvider.overrideWithValue(chat),
        instructionsServiceProvider.overrideWith(_NoInstructions.new),
        goalsServiceProvider.overrideWithValue(goals),
        goalSelectionProvider.overrideWith(
          () => _PresetSelection(root, active),
        ),
        contentServiceProvider.overrideWith(
          () => _FixedContent([
            Content(
              id: 's0',
              title: 'Intro',
              body: '<p>Welkom bij Python.</p>',
            ),
            _print,
          ]),
        ),
        soundServiceProvider.overrideWithValue(sound),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  TutorService tutor() => pc.read(tutorServiceProvider.notifier);

  Map<String, dynamic> request(int i) =>
      jsonDecode(connector.inputs[i]) as Map<String, dynamic>;

  /// The student is in practice with a socratic question waiting for an
  /// answer in the chat — the situation that used to swallow a question
  /// typed on the theory page.
  Future<void> askSocratic() async {
    connector.scripts.add(_question('Wat doet een for-lus?'));
    pc.read(modeProvider.notifier).state = SessionMode.practice;
    await tutor().requestExercise();
    expect(request(0)['request_type'], 'socratic_question');
    expect(tutor().hasInFlightExercise(), isTrue);
  }

  void showPage(String? id) {
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    pc.read(viewedContentIdProvider.notifier).show(Object(), id);
  }

  /// The theory view with page [id] on screen, in [language]: the view
  /// watches the lesson it draws, which keeps the app language's
  /// translations fetched, and it is on screen once they have come back.
  Future<void> viewPage(String id, {required String language}) async {
    pc.read(_locale.notifier).state = Locale(language);
    showPage(id);
    pc.listen(localizedContentProvider(id), (_, _) {});
    await Future<void>.delayed(Duration.zero);
  }

  test('a question typed on the theory page goes out as a content '
      'question carrying the page as text, and comes back as a plain '
      'answer', () async {
    await askSocratic();
    showPage('s1');
    connector.scripts.add(_answer('De komma scheidt de twee waarden.'));

    await tutor().handleStudentMessage('Waarom staat er een komma?');

    final sent = request(1);
    expect(sent['request_type'], 'content_question');
    expect(sent['question'], 'Waarom staat er een komma?');
    expect(sent['content_title'], 'Print');
    expect(
      sent['content'],
      '## Print\n\nZo toon je iets op het scherm.\n\n```\nprint("Hallo", naam)\n```',
    );
    expect(sent.containsKey('target_los'), isFalse);
    expect(sent.containsKey('answer'), isFalse);
    expect(generator.asked.last.type, ChatRequestType.contentQuestion);
    expect(
      generator.asked.last.override,
      isNull,
      reason: 'the page is the active subgoal\'s own',
    );
    expect(tutor().state, TutorState.idle);
    expect(chat.tutorMessageCount.value, 2);
    // Not evidence: the grader was never consulted.
    verifyNever(
      () => conductor.integrateAnswer(
        plan: any(named: 'plan'),
        answer: any(named: 'answer'),
      ),
    );
  });

  test('the pending practice question is untouched: back in practice the '
      'next message is graded against it, with its target LOs', () async {
    await askSocratic();
    showPage('s1');
    connector.scripts.add(_answer('De komma scheidt de twee waarden.'));
    await tutor().handleStudentMessage('Waarom staat er een komma?');
    expect(tutor().hasInFlightExercise(), isTrue);

    pc.read(modeProvider.notifier).state = SessionMode.practice;
    connector.scripts.add(_answer('ok'));
    await tutor().handleStudentMessage('Hij herhaalt iets.');

    final graded = request(2);
    expect(graded['request_type'], 'socratic_feedback');
    expect(graded['answer'], 'Hij herhaalt iets.');
    expect(
      (graded['target_los'] as List).single['id'],
      'lo-1',
      reason: 'the plan in flight survived the content question',
    );
  });

  test('in practice a message routes as before, even with a page id left '
      'behind by the theory view', () async {
    await askSocratic();
    pc.read(viewedContentIdProvider.notifier).show(Object(), 's1');
    connector.scripts.add(_answer('ok'));

    await tutor().handleStudentMessage('Hij herhaalt iets.');

    expect(request(1)['request_type'], 'socratic_feedback');
  });

  test('in the theory view with no page on screen a message routes as '
      'before', () async {
    await askSocratic();
    showPage(null);
    connector.scripts.add(_answer('ok'));

    await tutor().handleStudentMessage('Hij herhaalt iets.');

    expect(request(1)['request_type'], 'socratic_feedback');
  });

  test('a page that is not in the content cache routes as before', () async {
    await askSocratic();
    showPage('s9');
    connector.scripts.add(_answer('ok'));

    await tutor().handleStudentMessage('Wat is dit?');

    expect(request(1)['request_type'], 'socratic_feedback');
  });

  test('with no exercise pending the theory page still gets the question; '
      'without a page it is a plain student question', () async {
    showPage('s1');
    connector.scripts.add(_answer('ok'));
    await tutor().handleStudentMessage('Wat is print?');
    expect(request(0)['request_type'], 'content_question');

    showPage(null);
    connector.scripts.add(_answer('ok'));
    await tutor().handleStudentMessage('Wat is print?');
    expect(request(1)['request_type'], 'student_question');
  });

  test('a page the student paged back to is sent, and the prompt is '
      'written for that older subgoal', () async {
    await askSocratic();
    showPage('s0');
    connector.scripts.add(_answer('Welkom!'));

    await tutor().handleStudentMessage('Waar gaat dit over?');

    final sent = request(1);
    expect(sent['request_type'], 'content_question');
    expect(sent['content_title'], 'Intro');
    expect(sent['content'], 'Welkom bij Python.');
    expect(generator.asked.last.type, ChatRequestType.contentQuestion);
    expect(generator.asked.last.override?.id, 's0');
    // And the socratic question is still the one in flight.
    expect(tutor().hasInFlightExercise(), isTrue);
  });

  group('in the language the page is shown in (#207)', () {
    test('in English a translated page goes out as the translation: its '
        'title and its text', () async {
      await viewPage('s1', language: 'en');
      expect(pc.read(localizedContentProvider('s1'))!.language, 'en');
      connector.scripts.add(_answer('The comma separates the two values.'));

      await tutor().handleStudentMessage('Why is there a comma?');

      final sent = request(0);
      expect(sent['request_type'], 'content_question');
      expect(sent['question'], 'Why is there a comma?');
      expect(sent['content_title'], 'Printing');
      expect(
        sent['content'],
        '## Printing\n\nThis is how you show something on the screen.'
        '\n\n```\nprint("Hello", name)\n```',
      );
    });

    test('in English a page without a translation goes out as the Dutch '
        'text the page shows', () async {
      await viewPage('s0', language: 'en');
      expect(pc.read(localizedContentProvider('s0'))!.isFallback, isTrue);
      connector.scripts.add(_answer('Welcome!'));

      await tutor().handleStudentMessage('What is this about?');

      final sent = request(0);
      expect(sent['request_type'], 'content_question');
      expect(sent['content_title'], 'Intro');
      expect(sent['content'], 'Welkom bij Python.');
    });

    test('in Dutch the page goes out as written, even when it has a '
        'translation', () async {
      await viewPage('s1', language: 'nl');
      connector.scripts.add(_answer('De komma scheidt de twee waarden.'));

      await tutor().handleStudentMessage('Waarom staat er een komma?');

      final sent = request(0);
      expect(sent['content_title'], 'Print');
      expect(sent['content'], contains('Zo toon je iets op het scherm.'));
      expect(sent['content'], isNot(contains('This is how')));
    });

    test('switching to English sends the next question with the English '
        'page', () async {
      await viewPage('s1', language: 'nl');
      connector.scripts.add(_answer('ok'));
      await tutor().handleStudentMessage('Waarom staat er een komma?');
      expect(request(0)['content_title'], 'Print');

      await viewPage('s1', language: 'en');
      connector.scripts.add(_answer('ok'));
      await tutor().handleStudentMessage('Why is there a comma?');
      expect(request(1)['content_title'], 'Printing');
      expect(request(1)['content'], contains('This is how you show'));
    });
  });
}
