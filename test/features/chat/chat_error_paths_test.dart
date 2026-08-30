// Issue #7 — what the student sees when a tutor turn fails, driven through
// the real `ChatWidget` (composer, bubbles, system pills) over the real
// `TutorService` and `ChatService`. Only the two edges are scripted: the
// OpenAI connector (a subclass replaying canned stream chunks) and the
// conductor (a mock whose Cosmos-backed `integrateAnswer` can be made to
// fail). Everything in between — request building, stream handling, retry,
// response dispatch, in-flight plan bookkeeping — is the production code.
//
// Issue #23 — the service layer emits typed `ChatNotice`s and the chat
// widget localizes them, so every scenario runs under both locales and one
// scenario switches the locale while the pills are on screen.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo (#28).

import 'dart:io';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_thinking.dart';
import 'package:ai_tutor_python/features/chat/widgets/tutor_bubble.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
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
import 'package:ai_tutor_python/services/tutor/responses/socratic_feedback.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';
import 'package:mocktail/mocktail.dart' hide Answer;

import '../../helpers/mocks.dart';

/// Replays one canned chunk list per stream request, in order.
class _ScriptedConnector extends OpenaiConnector {
  final List<List<StreamChunk>> scripts = [];
  int sends = 0;
  int resends = 0;

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
    sends++;
    return _next();
  }

  @override
  Stream<StreamChunk> resendRequestStream() {
    resends++;
    return _next();
  }
}

class _FakeInstructionGenerator extends InstructionGenerator {
  @override
  Future<String> generateInstructions(
    ChatRequestType type, {
    required GoalSelectionState goalSelection,
    required List<Instruction> cachedInstructions,
    required Future<List<Instruction>> Function() fetchInstructions,
    required Future<List<Goal>> Function() fetchRootGoals,
    List<LearningObjective> targetLOs = const [],
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
  }) async => 'system prompt';
}

/// Keeps the real `InstructionsService` off Cosmos (its build() starts a
/// polling stream).
class _NoInstructions extends InstructionsService {
  @override
  List<Instruction> build() => const [];
}

const _testProfile = Profile(
  name: 'Sam',
  topic: '',
  level: 1,
  xp: 0,
  xpNext: 1500,
  streak: 0,
  role: Role.student,
);

final _plan = QuestionPlan(
  type: ChatRequestType.socraticQuestion,
  difficulty: QuestionDifficulty.medium,
  targetLOs: const [
    LearningObjective(id: 'lo-1', statement: 'loops', kind: LoKind.recall),
  ],
  reason: const TurnSelectionReason(
    candidateLOs: [],
    chosenReason: 'test',
    notchDropFired: false,
  ),
);

/// What the real connector yields for a socket reset: a typed notice, so
/// the pill text below comes from the ARB files, not from this test.
StreamFailed _cut() => StreamFailed(
  const SocketException('reset by peer'),
  StackTrace.current,
  OpenaiConnector.describeTransportError(
    const SocketException('reset by peer'),
  ),
);

List<StreamChunk> _answer(String text) => [
  StreamTextDelta(text),
  StreamCompleted(Answer(type: 'answer', prompt: text)),
];

List<StreamChunk> _question(String text) => [
  StreamTextDelta(text),
  StreamCompleted(SocraticQuestion(type: 'socratic_question', prompt: text)),
];

List<StreamChunk> _feedback(String text) => [
  StreamTextDelta(text),
  StreamCompleted(
    SocraticFeedback(
      type: 'socratic_feedback',
      quality: AnswerQuality.correct,
      prompt: text,
    ),
  ),
];

/// The strings each locale is expected to show, keyed by language code.
class _Expected {
  const _Expected({
    required this.unreachable,
    required this.databaseUnavailable,
    required this.sessionStartFailed,
  });
  final String unreachable;
  final String databaseUnavailable;
  final String sessionStartFailed;
}

const _expected = {
  'en': _Expected(
    unreachable: 'No connection to the tutor',
    databaseUnavailable: 'The connection to the database dropped',
    sessionStartFailed: 'The session could not start',
  ),
  'nl': _Expected(
    unreachable: 'Geen verbinding met de tutor',
    databaseUnavailable: 'De verbinding met de database is even weg',
    sessionStartFailed: 'De sessie kon niet starten',
  ),
};

void main() {
  late _ScriptedConnector connector;
  late MockConductor conductor;
  late ChatService chat;
  late MockSoundService sound;
  late ProviderContainer pc;

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
    connector = _ScriptedConnector();
    conductor = MockConductor();
    when(() => conductor.setTarget()).thenAnswer((_) async {});
    when(() => conductor.planNext()).thenAnswer((_) async => _plan);
    when(() => conductor.notePlannedQuestion(any())).thenReturn(null);
    when(() => conductor.takePendingStatusReportGoalId()).thenReturn(null);
    when(() => conductor.hintProvided()).thenReturn(null);

    sound = MockSoundService();
    when(() => sound.askQuestion()).thenAnswer((_) async {});
    when(() => sound.correctAnswer()).thenAnswer((_) async {});
    when(() => sound.playGoalReached()).thenAnswer((_) async {});

    chat = ChatService();
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(
          () => TutorService(
            connectorOverride: connector,
            conductorOverride: conductor,
            instructionGeneratorOverride: _FakeInstructionGenerator(),
          ),
        ),
        chatServiceProvider.overrideWithValue(chat),
        instructionsServiceProvider.overrideWith(_NoInstructions.new),
        goalsServiceProvider.overrideWithValue(MockGoalsService()),
        soundServiceProvider.overrideWithValue(sound),
        profileProvider.overrideWithValue(_testProfile),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  Widget buildApp(Locale locale) => UncontrolledProviderScope(
    container: pc,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ChatWidget()),
    ),
  );

  /// Lets the async tutor flow (microtasks, stream chunks, chat list
  /// animations) run to completion without `pumpAndSettle`, which the
  /// composer's typing indicator would keep alive forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> mount(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp(locale));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> send(WidgetTester tester, String text) async {
    final field = find.descendant(
      of: find.byType(ComposerIdle),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await settle(tester);
  }

  Iterable<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text);

  for (final MapEntry(key: code, value: expected) in _expected.entries) {
    final locale = Locale(code);

    group('[$code]', () {
      testWidgets('a reply cut off mid-stream is withdrawn, explained, and '
          'retried once', (tester) async {
        connector.scripts.addAll([
          [const StreamTextDelta('Een lus herhaalt '), _cut()],
          _answer('Een lus herhaalt code.'),
        ]);
        await mount(tester, locale);

        await send(tester, 'Wat is een lus?');

        // The half-streamed placeholder is gone; the retry's full answer is
        // the only tutor bubble.
        expect(find.byType(FlyerChatTextStreamMessage), findsNothing);
        expect(find.byType(TutorBubble), findsOneWidget);
        expect(
          find.textContaining('Een lus herhaalt code.', findRichText: true),
          findsOneWidget,
        );
        expect(pills(tester), contains(contains(expected.unreachable)));
        // Never the other language, never an empty pill.
        for (final other in _expected.values) {
          if (other == expected) continue;
          expect(pills(tester), isNot(contains(contains(other.unreachable))));
        }
        expect(pills(tester), isNot(contains('')));
        expect(connector.sends, 1);
        expect(connector.resends, 1);
        expect(find.byType(ComposerIdle), findsOneWidget);
        expect(find.byType(ComposerThinking), findsNothing);

        await unmount(tester);
      });

      testWidgets('a Cosmos failure while integrating a grade is reported as '
          'a transient problem and the next answer starts clean', (
        tester,
      ) async {
        when(
          () => conductor.integrateAnswer(
            plan: any(named: 'plan'),
            answer: any(named: 'answer'),
          ),
        ).thenThrow(CosmosException(503, 'Service Unavailable'));

        connector.scripts.addAll([
          _question('Wat doet een for-lus?'),
          _feedback('Goed uitgelegd!'),
          // Third turn: the stale plan must be gone, so this feedback must
          // not reach the conductor and the flow continues into a fresh
          // question.
          _feedback('Ook goed.'),
          _question('Wat doet een while-lus?'),
        ]);
        await mount(tester, locale);

        // What PracticeView does on mount.
        await pc.read(tutorServiceProvider.notifier).requestExercise();
        await settle(tester);
        expect(
          find.textContaining('Wat doet een for-lus?', findRichText: true),
          findsOneWidget,
        );

        await send(tester, 'Hij herhaalt iets een aantal keer.');

        // The raw CosmosException never reaches the student.
        expect(pills(tester), contains(contains(expected.databaseUnavailable)));
        expect(pills(tester), isNot(contains(contains('CosmosException'))));
        expect(find.byType(ComposerIdle), findsOneWidget);

        await send(tester, 'Nog een antwoord.');

        verify(
          () => conductor.integrateAnswer(
            plan: any(named: 'plan'),
            answer: any(named: 'answer'),
          ),
        ).called(1);
        expect(
          find.textContaining('Wat doet een while-lus?', findRichText: true),
          findsOneWidget,
        );
        expect(find.byType(ComposerIdle), findsOneWidget);

        await unmount(tester);
      });

      testWidgets('a Cosmos failure during session start is reported instead '
          'of leaving an empty chat', (tester) async {
        when(() => conductor.setTarget())
            .thenThrow(CosmosException(kCosmosNetworkStatus, 'no route'));

        await mount(tester, locale);

        expect(pills(tester), contains(contains(expected.sessionStartFailed)));
        expect(pills(tester), contains(contains(expected.databaseUnavailable)));
        expect(find.byType(ComposerIdle), findsOneWidget);

        await unmount(tester);
      });
    });
  }

  testWidgets('switching the language re-renders the pills already in the '
      'chat', (tester) async {
    when(() => conductor.setTarget())
        .thenThrow(CosmosException(kCosmosNetworkStatus, 'no route'));

    await mount(tester, const Locale('en'));
    expect(
      pills(tester),
      contains(contains(_expected['en']!.sessionStartFailed)),
    );

    // Same container, same chat history — only the app locale changes, as
    // it does when the user picks a language on the Options page.
    await tester.pumpWidget(buildApp(const Locale('nl')));
    await settle(tester);

    expect(
      pills(tester),
      contains(contains(_expected['nl']!.sessionStartFailed)),
    );
    expect(
      pills(tester),
      isNot(contains(contains(_expected['en']!.sessionStartFailed))),
    );

    await unmount(tester);
  });

  testWidgets('an unknown exception is shown verbatim inside the localized '
      'wrapper', (tester) async {
    when(() => conductor.setTarget()).thenThrow(StateError('boom-42'));

    await mount(tester, const Locale('en'));

    expect(
      pills(tester),
      contains(
        allOf(contains('The session could not start'), contains('boom-42')),
      ),
    );

    await unmount(tester);
  });
}
