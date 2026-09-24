// Issue #185 — the teacher's Questions page over an in-memory question bank:
// the curriculum tree with a count per subgoal, one subgoal's questions
// rendered as the student sees them with their statistics, the filter and
// the sort on the share correct, the review actions — and a clear message,
// not a crash, while the `questions` container does not exist.
//
// The end-to-end run (integration_test/flows/question_bank.dart) drives the
// same page in the real shell; this pins the details per widget.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/features/questions/questions_page.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';
import '../../helpers/mocks.dart';
import '../../helpers/unprovisioned_cosmos.dart';

Map<String, dynamic> _goal(
  String id,
  String title, {
  String? parentId,
  int order = 0,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': order,
  'optional': false,
  'teachingTips': <String>[],
  'allowChains': false,
  'objectives': [
    {
      'id': 'lo-$id',
      'statement': 'Objective of $title',
      'kind': 'apply',
      'weight': 1.0,
      'optional': false,
    },
  ],
  'moduleId': 'python-basics',
};

final _goals = [
  _goal('r1', 'Basics', order: 1000),
  _goal('s1', 'Print', parentId: 'r1', order: 100),
  _goal('s2', 'Variables', parentId: 'r1', order: 200),
  _goal('r2', 'Loops'),
  _goal('s3', 'For', parentId: 'r2', order: 100),
];

Map<String, dynamic> _question({
  required String id,
  String subgoalId = 's1',
  String questionType = 'mcQuestion',
  required Map<String, dynamic> payload,
  int asked = 0,
  int answered = 0,
  int correct = 0,
  String createdAt = '2026-09-20T10:00:00.000Z',
  List<Map<String, String>> feedback = const [],
  String status = 'active',
  String? reviewedAt,
}) => {
  'id': id,
  'type': 'question',
  'subgoalId': subgoalId,
  'rootGoalId': 'r1',
  'targetLOIds': ['lo-$subgoalId'],
  'questionType': questionType,
  'difficulty': 'medium',
  'language': 'nl',
  'payload': payload,
  'model': 'gpt-5-mini',
  'createdAt': createdAt,
  'createdByUid': 'u1',
  'askedCount': asked,
  'answeredCount': answered,
  'correctCount': correct,
  'optionFeedback': feedback,
  'status': status,
  'reviewedAt': ?reviewedAt,
};

final _mcq = _question(
  id: 's1_mcq',
  payload: {
    'type': 'multiple_choice',
    'prompt': 'Wat drukt dit af?',
    'code': 'print(1 + 1)',
    'options': [
      {'option': '2'},
      {'option': '11'},
    ],
    'correct': '2',
  },
  asked: 5,
  answered: 4,
  correct: 1,
  createdAt: '2026-09-21T10:00:00.000Z',
  feedback: [
    {'option': '11', 'text': 'Nee, het is een som.', 'quality': 'wrong'},
  ],
);

final _easy = _question(
  id: 's1_easy',
  questionType: 'completeCodeQuestion',
  payload: {
    'type': 'complete_code',
    'prompt': 'Toon een groet.',
    'code': 'print(___)',
  },
  asked: 2,
  answered: 2,
  correct: 2,
  createdAt: '2026-09-22T10:00:00.000Z',
  reviewedAt: '2026-09-23T10:00:00.000Z',
);

final _open = _question(
  id: 's1_open',
  questionType: 'socraticQuestion',
  payload: {'type': 'socratic_question', 'prompt': 'Waarom haakjes?'},
  asked: 1,
  createdAt: '2026-09-23T10:00:00.000Z',
);

final _variables = _question(
  id: 's2_q',
  subgoalId: 's2',
  questionType: 'writeCodeQuestion',
  payload: {'type': 'write_code', 'prompt': 'Maak een variabele.'},
);

final _orphan = _question(
  id: 'gone_q',
  subgoalId: 'gone',
  questionType: 'writeCodeQuestion',
  payload: {'type': 'write_code', 'prompt': 'Weg.'},
);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    registerFallbackValue(<String, Object?>{});
  });

  late InMemoryCosmosClient cosmos;

  Future<void> mount(
    WidgetTester tester, {
    List<Map<String, dynamic>>? questions,
    CosmosContainer? questionsContainer,
  }) async {
    // Tall enough that every card of a subgoal is built.
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cosmos = InMemoryCosmosClient({
      'goals': InMemoryCosmos(_goals),
      'questions': InMemoryCosmos(
        questions ?? [_mcq, _easy, _open, _variables, _orphan],
      ),
    })..install();
    if (questionsContainer != null) {
      cosmos.route('questions', questionsContainer);
    }
    await tester.pumpWidget(
      ProviderScope(
        child: localizedTestApp(const Scaffold(body: QuestionsPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  String subtitleOf(WidgetTester tester, String subgoalId) => tester
      .widget<Text>(find.byKey(Key('questions-subgoal-count-$subgoalId')))
      .data!;

  Future<void> open(WidgetTester tester, String subgoalId) async {
    await tester.tap(find.byKey(Key('questions-subgoal-$subgoalId')));
    await tester.pumpAndSettle();
  }

  /// The ids of the cards on screen, top to bottom.
  List<String> cardOrder(WidgetTester tester) {
    final ids = [
      for (final id in ['s1_mcq', 's1_easy', 's1_open'])
        if (find.byKey(Key('questions-card-$id')).evaluate().isNotEmpty) id,
    ];
    double top(String id) =>
        tester.getTopLeft(find.byKey(Key('questions-card-$id'))).dy;
    return ids..sort((a, b) => top(a).compareTo(top(b)));
  }

  testWidgets('the tree counts every subgoal\'s questions and the ones not '
      'reviewed yet, and lists questions of a removed subgoal apart', (
    tester,
  ) async {
    await mount(tester);

    expect(subtitleOf(tester, 's1'), '3 questions · 2 new');
    expect(subtitleOf(tester, 's2'), '1 question · 1 new');
    expect(subtitleOf(tester, 's3'), '0 questions');
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('questions-subgoal-s3')))
          .enabled,
      isFalse,
    );
    expect(find.text('Removed subgoal (gone)'), findsOneWidget);
    expect(find.text('NO LONGER IN THE CURRICULUM'), findsOneWidget);
    // Roots in curriculum order.
    expect(
      tester.getTopLeft(find.text('LOOPS')).dy,
      lessThan(tester.getTopLeft(find.text('BASICS')).dy),
    );
  });

  testWidgets('a subgoal\'s questions render as the student gets them, with '
      'their numbers, the answer key and the feedback per option', (
    tester,
  ) async {
    await mount(tester);
    await open(tester, 's1');

    final card = find.byKey(const Key('questions-card-s1_mcq'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);
    expect(inCard(find.text('MULTIPLE CHOICE')), findsOneWidget);
    expect(inCard(find.text('medium')), findsOneWidget);
    expect(inCard(find.text('LO lo-s1')), findsOneWidget);
    expect(inCard(find.text('asked 5×')), findsOneWidget);
    expect(inCard(find.text('25% correct (1/4)')), findsOneWidget);
    expect(
      inCard(find.textContaining('Wat drukt dit af?', findRichText: true)),
      findsOneWidget,
    );
    expect(inCard(find.text('Nee, het is een som.')), findsOneWidget);
    expect(inCard(find.byIcon(Icons.check_circle)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('questions-card-s1_open')),
        matching: find.text('no answers yet'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('questions-reviewed-s1_easy')), findsOneWidget);
  });

  testWidgets('sorts on the share correct both ways, unanswered last, and '
      'filters to the questions not reviewed yet', (tester) async {
    await mount(tester);
    await open(tester, 's1');

    expect(cardOrder(tester), ['s1_open', 's1_easy', 's1_mcq']);

    await tester.tap(find.byKey(const Key('questions-sort-shareAsc')));
    await tester.pumpAndSettle();
    expect(cardOrder(tester), ['s1_mcq', 's1_easy', 's1_open']);

    await tester.tap(find.byKey(const Key('questions-sort-shareDesc')));
    await tester.pumpAndSettle();
    expect(cardOrder(tester), ['s1_easy', 's1_mcq', 's1_open']);

    await tester.tap(find.byKey(const Key('questions-sort-mostAsked')));
    await tester.pumpAndSettle();
    expect(cardOrder(tester), ['s1_mcq', 's1_easy', 's1_open']);

    await tester.tap(find.byKey(const Key('questions-filter-unreviewed')));
    await tester.pumpAndSettle();
    expect(cardOrder(tester), ['s1_mcq', 's1_open']);
  });

  testWidgets('hiding marks the question hidden in the bank, keeps it on the '
      'page to show again, and takes it off the "new" count', (tester) async {
    await mount(tester);
    await open(tester, 's1');

    await tester.tap(find.byKey(const Key('questions-hide-s1_mcq')));
    await tester.pumpAndSettle();

    final stored = cosmos['questions']['s1_mcq']!;
    expect(stored['status'], 'hidden');
    expect(stored['reviewedAt'], isA<String>());
    expect(cosmos['questions'].docs, hasLength(5), reason: 'never deleted');
    expect(find.byKey(const Key('questions-hidden-s1_mcq')), findsOneWidget);
    expect(find.byKey(const Key('questions-unhide-s1_mcq')), findsOneWidget);
    expect(subtitleOf(tester, 's1'), '3 questions · 1 new');

    await tester.tap(find.byKey(const Key('questions-unhide-s1_mcq')));
    await tester.pumpAndSettle();
    expect(cosmos['questions']['s1_mcq']!['status'], 'active');
    expect(find.byKey(const Key('questions-hidden-s1_mcq')), findsNothing);

    await tester.tap(find.byKey(const Key('questions-review-s1_open')));
    await tester.pumpAndSettle();
    expect(cosmos['questions']['s1_open']!['reviewedAt'], isA<String>());
    expect(subtitleOf(tester, 's1'), '3 questions');
  });

  testWidgets('a note is written from its dialog and shown on the card', (
    tester,
  ) async {
    await mount(tester);
    await open(tester, 's1');

    await tester.tap(find.byKey(const Key('questions-note-s1_open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('questions-note-field')),
      'Te vaag: welke haakjes?',
    );
    await tester.tap(find.byKey(const Key('questions-note-save')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      cosmos['questions']['s1_open']!['teacherNote'],
      'Te vaag: welke haakjes?',
    );
    expect(
      find.byKey(const Key('questions-note-text-s1_open')),
      findsOneWidget,
    );
    expect(find.text('Note: Te vaag: welke haakjes?'), findsOneWidget);
  });

  testWidgets('a key the grading called wrong (#198) is warned about apart '
      'from a grade against the key and from a missing key', (tester) async {
    Map<String, dynamic> mcq(
      String id, {
      String? key = '2',
      List<Map<String, String>> feedback = const [],
      int disputed = 0,
    }) => {
      ..._question(
        id: id,
        payload: {
          'type': 'multiple_choice',
          'prompt': 'Wat drukt dit af? ($id)',
          'code': 'print(1 + 1)',
          'options': [
            {'option': '2'},
            {'option': '11'},
            {'option': 'Error'},
          ],
          'correct': ?key,
        },
        feedback: feedback,
      ),
      if (disputed > 0) 'keyDisputedCount': disputed,
      if (disputed > 0) 'keyDisputedAt': '2026-09-24T10:00:00.000Z',
    };
    await mount(
      tester,
      questions: [
        // Every pick graded as the key says, yet the grader called the key
        // wrong twice: only the dispute shows it.
        mcq(
          's1_disputed',
          feedback: [
            {'option': 'Error', 'text': 'Nee.', 'quality': 'wrong'},
          ],
          disputed: 2,
        ),
        mcq('s1_once', disputed: 1),
        mcq(
          's1_against',
          feedback: [
            {'option': '11', 'text': 'Juist!', 'quality': 'correct'},
          ],
        ),
        mcq('s1_nokey', key: null),
        mcq('s1_fine'),
      ],
    );
    await open(tester, 's1');

    String warning(String id) =>
        tester.widget<Text>(find.byKey(Key('questions-warning-$id'))).data!;
    expect(
      warning('s1_disputed'),
      'The grading called the answer key wrong 2 times.',
    );
    expect(warning('s1_once'), 'The grading called the answer key wrong once.');
    expect(
      warning('s1_against'),
      'The grading disagreed with the answer key at least once.',
    );
    expect(
      warning('s1_nokey'),
      'No answer key: the model did not name the correct option.',
    );
    expect(find.byKey(const Key('questions-warning-s1_fine')), findsNothing);
  });

  testWidgets('without a `questions` container the page says what to create '
      'instead of failing', (tester) async {
    final missing = UnprovisionedCosmos('questions');
    await mount(tester, questionsContainer: missing.container);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('questions-container-missing')),
      findsOneWidget,
    );
    expect(
      find.text('The question bank has not been set up yet'),
      findsOneWidget,
    );
    expect(find.textContaining('/subgoalId'), findsOneWidget);
    expect(find.byKey(const Key('questions-tree')), findsNothing);

    // Created in the meantime: "Try again" picks it up.
    cosmos.route('questions', null);
    await tester.tap(find.byKey(const Key('questions-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('questions-container-missing')), findsNothing);
    expect(subtitleOf(tester, 's1'), '3 questions · 2 new');
  });

  testWidgets('any other failure is named, with a way to try again', (
    tester,
  ) async {
    final broken = MockCosmosContainer();
    when(
      () => broken.query(
        any(),
        parameters: any(named: 'parameters'),
        partitionKey: any(named: 'partitionKey'),
        crossPartition: any(named: 'crossPartition'),
      ),
    ).thenThrow(CosmosException(503, 'Service Unavailable'));
    await mount(tester, questionsContainer: broken);

    expect(find.byKey(const Key('questions-load-error')), findsOneWidget);
    expect(find.textContaining('Service Unavailable'), findsOneWidget);
    expect(find.byKey(const Key('questions-retry')), findsOneWidget);
  });

  testWidgets('an empty bank says questions appear as students practise', (
    tester,
  ) async {
    await mount(tester, questions: const []);
    expect(find.byKey(const Key('questions-tree-empty')), findsOneWidget);
  });

  test('sortQuestions leaves unanswered questions last on either share '
      'order', () {
    final qs = [
      for (final d in [_mcq, _easy, _open]) BankQuestion.tryFromCosmos(d)!,
    ];
    expect(sortQuestions(qs, QuestionSort.shareAsc).map((q) => q.id), [
      's1_mcq',
      's1_easy',
      's1_open',
    ]);
    expect(sortQuestions(qs, QuestionSort.shareDesc).map((q) => q.id), [
      's1_easy',
      's1_mcq',
      's1_open',
    ]);
  });
}
