// Issues #185 and #215 — the teacher's Questions page over an in-memory
// question bank: the curriculum tree with a count and a hidden count per
// subgoal, one subgoal's questions rendered as the student sees them with
// their statistics and who hid them, the "hidden only" filter and the sort
// on the share correct, hide / show again and delete with a confirmation —
// and a clear message, not a crash, while the `questions` container does not
// exist. No "reviewed" and no notes any more (#215). And #216: every card
// shows the question's short ID, and "Find by ID" looks one up.
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
  String? hiddenBy,
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
  'hiddenBy': ?hiddenBy,
  if (status == 'hidden') 'hiddenAt': '2026-09-25T10:00:00.000Z',
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
);

/// Stored before #215 — when it was asked, never answered — and hidden by
/// the teacher back then: no `hiddenBy`.
final _open = _question(
  id: 's1_open',
  questionType: 'explainCodeQuestion',
  payload: {'type': 'explain_code', 'prompt': 'Waarom haakjes?'},
  asked: 1,
  createdAt: '2026-09-23T10:00:00.000Z',
  status: 'hidden',
);

/// Hidden by the bank itself: 3 of 10 correct.
final _variables = _question(
  id: 's2_q',
  subgoalId: 's2',
  questionType: 'writeCodeQuestion',
  payload: {'type': 'write_code', 'prompt': 'Maak een variabele.'},
  asked: 10,
  answered: 10,
  correct: 3,
  status: 'hidden',
  hiddenBy: 'auto',
);

final _orphan = _question(
  id: 'gone_q',
  subgoalId: 'gone',
  questionType: 'writeCodeQuestion',
  payload: {'type': 'write_code', 'prompt': 'Weg.'},
  asked: 1,
  answered: 1,
  correct: 1,
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
    Locale locale = const Locale('en'),
    List<Map<String, dynamic>>? goals,
    // Tall enough that every card of a subgoal is built.
    Size size = const Size(1280, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cosmos = InMemoryCosmosClient({
      'goals': InMemoryCosmos(goals ?? _goals),
      'questions': InMemoryCosmos(
        questions ?? [_mcq, _easy, _open, _variables, _orphan],
      ),
    })..install();
    if (questionsContainer != null) {
      cosmos.route('questions', questionsContainer);
    }
    await tester.pumpWidget(
      ProviderScope(
        child: localizedTestApp(
          const Scaffold(body: QuestionsPage()),
          locale: locale,
        ),
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

  String badgeOf(WidgetTester tester, String id) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(Key('questions-hidden-$id')),
          matching: find.byType(Text),
        ),
      )
      .data!;

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

  testWidgets('the tree counts every subgoal\'s questions and the hidden '
      'ones, and lists questions of a removed subgoal apart', (tester) async {
    await mount(tester);

    expect(subtitleOf(tester, 's1'), '3 questions · 1 hidden');
    expect(subtitleOf(tester, 's2'), '1 question · 1 hidden');
    expect(subtitleOf(tester, 's3'), '0 questions');
    expect(subtitleOf(tester, 'gone'), '1 question');
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
      'their numbers, the answer key, the feedback per option and who hid '
      'them; no review step and no notes', (tester) async {
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
    expect(inCard(find.text('Hide')), findsOneWidget);
    expect(inCard(find.text('Delete')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('questions-card-s1_open')),
        matching: find.text('no answers yet'),
      ),
      findsOneWidget,
    );

    // Hidden by the teacher (before #215: no `hiddenBy`), and still to
    // delete; the active ones carry no badge.
    expect(badgeOf(tester, 's1_open'), 'HIDDEN');
    expect(find.byKey(const Key('questions-unhide-s1_open')), findsOneWidget);
    expect(find.byKey(const Key('questions-delete-s1_open')), findsOneWidget);
    expect(find.byKey(const Key('questions-hidden-s1_mcq')), findsNothing);
    expect(find.text('Mark reviewed'), findsNothing);
    expect(find.text('Note'), findsNothing);
    expect(find.text('REVIEWED'), findsNothing);

    // Hidden by the bank itself, with the rule on hover.
    await open(tester, 's2');
    expect(badgeOf(tester, 's2_q'), 'HIDDEN AUTOMATICALLY');
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(const Key('questions-hidden-s2_q')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, contains('10 or more answers'));
  });

  testWidgets('sorts on the share correct both ways, unanswered last, and '
      'filters to the hidden questions', (tester) async {
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

    await tester.tap(find.byKey(const Key('questions-filter-hidden')));
    await tester.pumpAndSettle();
    expect(find.text('Hidden only'), findsOneWidget);
    expect(cardOrder(tester), ['s1_open']);
  });

  testWidgets('hiding marks the question hidden by the teacher, keeps it on '
      'the page to show again, and moves the hidden count; showing again '
      'a question that hid itself keeps it', (tester) async {
    await mount(tester);
    await open(tester, 's1');

    await tester.tap(find.byKey(const Key('questions-hide-s1_mcq')));
    await tester.pumpAndSettle();

    final stored = cosmos['questions']['s1_mcq']!;
    expect(stored['status'], 'hidden');
    expect(stored['hiddenBy'], 'teacher');
    expect(stored['hiddenAt'], isA<String>());
    expect(stored.containsKey('reviewedAt'), isFalse);
    expect(cosmos['questions'].docs, hasLength(5));
    expect(badgeOf(tester, 's1_mcq'), 'HIDDEN');
    expect(find.byKey(const Key('questions-unhide-s1_mcq')), findsOneWidget);
    expect(subtitleOf(tester, 's1'), '3 questions · 2 hidden');

    await tester.tap(find.byKey(const Key('questions-unhide-s1_mcq')));
    await tester.pumpAndSettle();
    expect(cosmos['questions']['s1_mcq']!['status'], 'active');
    expect(
      cosmos['questions']['s1_mcq']!.containsKey('keptByTeacher'),
      isFalse,
    );
    expect(find.byKey(const Key('questions-hidden-s1_mcq')), findsNothing);
    expect(subtitleOf(tester, 's1'), '3 questions · 1 hidden');

    await open(tester, 's2');
    await tester.tap(find.byKey(const Key('questions-unhide-s2_q')));
    await tester.pumpAndSettle();
    final kept = cosmos['questions']['s2_q']!;
    expect(kept['status'], 'active');
    expect(kept['keptByTeacher'], isTrue);
    expect(kept.containsKey('hiddenBy'), isFalse);
    expect(find.byKey(const Key('questions-hidden-s2_q')), findsNothing);
    expect(subtitleOf(tester, 's2'), '1 question');
  });

  testWidgets('delete asks first, then removes the question from the bank, '
      'the page and the counts — hidden or not', (tester) async {
    await mount(tester);
    await open(tester, 's1');

    // Cancelled: nothing happens.
    await tester.tap(find.byKey(const Key('questions-delete-s1_mcq')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this question?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('first student answers it correctly'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('questions-delete-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(cosmos['questions']['s1_mcq'], isNotNull);
    expect(find.byKey(const Key('questions-card-s1_mcq')), findsOneWidget);

    // Confirmed: gone.
    await tester.tap(find.byKey(const Key('questions-delete-s1_mcq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('questions-delete-confirm')));
    await tester.pumpAndSettle();
    expect(cosmos['questions']['s1_mcq'], isNull);
    expect(find.byKey(const Key('questions-card-s1_mcq')), findsNothing);
    expect(subtitleOf(tester, 's1'), '2 questions · 1 hidden');

    // Clearing out the hidden ones with the filter on.
    await tester.tap(find.byKey(const Key('questions-filter-hidden')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('questions-delete-s1_open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('questions-delete-confirm')));
    await tester.pumpAndSettle();
    expect(cosmos['questions']['s1_open'], isNull);
    expect(subtitleOf(tester, 's1'), '1 question');
    expect(
      tester.widget<Text>(find.byKey(const Key('questions-list-empty'))).data,
      'No hidden questions for this subgoal.',
    );

    // The last question of a subgoal.
    await open(tester, 's2');
    await tester.tap(find.byKey(const Key('questions-delete-s2_q')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('questions-delete-confirm')));
    await tester.pumpAndSettle();
    expect(subtitleOf(tester, 's2'), '0 questions');
    expect(
      tester.widget<Text>(find.byKey(const Key('questions-list-empty'))).data,
      'No questions for this subgoal.',
    );
    expect(
      cosmos['questions'].docs.keys,
      unorderedEquals(['s1_easy', 'gone_q']),
    );
  });

  testWidgets('a delete that fails says so and leaves the question', (
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
    ).thenAnswer((_) async => [Map<String, dynamic>.from(_mcq)]);
    when(() => broken.delete(any(), partitionKey: any(named: 'partitionKey')))
        .thenThrow(CosmosException(503, 'Service Unavailable'));
    await mount(tester, questionsContainer: broken);
    await open(tester, 's1');

    await tester.tap(find.byKey(const Key('questions-delete-s1_mcq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('questions-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('That did not work'), findsOneWidget);
    expect(find.byKey(const Key('questions-card-s1_mcq')), findsOneWidget);
    expect(subtitleOf(tester, 's1'), '1 question');
  });

  testWidgets('in Dutch: the hidden count, the filter, both badges and the '
      'buttons', (tester) async {
    await mount(tester, locale: const Locale('nl'));
    expect(subtitleOf(tester, 's1'), '3 vragen · 1 verborgen');

    await open(tester, 's1');
    expect(find.text('Alleen verborgen'), findsOneWidget);
    expect(badgeOf(tester, 's1_open'), 'VERBORGEN');
    final card = find.byKey(const Key('questions-card-s1_mcq'));
    expect(
      find.descendant(of: card, matching: find.text('Verberg')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Verwijder')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('questions-card-s1_open')),
        matching: find.text('Toon opnieuw'),
      ),
      findsOneWidget,
    );

    await open(tester, 's2');
    expect(badgeOf(tester, 's2_q'), 'AUTOMATISCH VERBORGEN');

    await tester.tap(find.byKey(const Key('questions-delete-s2_q')));
    await tester.pumpAndSettle();
    expect(find.text('Deze vraag verwijderen?'), findsOneWidget);
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
    expect(subtitleOf(tester, 's1'), '3 questions · 1 hidden');
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

  testWidgets('an empty bank says questions appear once a student answers a '
      'new one correctly', (tester) async {
    await mount(tester, questions: const []);
    expect(find.byKey(const Key('questions-tree-empty')), findsOneWidget);
    expect(
      find.textContaining('answers a new question correctly'),
      findsOneWidget,
    );
  });

  group('the short ID (#216)', () {
    const hash = '3fa91c0b5e7d4a2f9c8b1e6d0a4f7c2e';
    const wantedId = 's1_$hash';
    const twinId = 's3_$hash';

    /// The question the teacher saw on a student's screen: the oldest of
    /// its subgoal, so last on "Newest".
    final wanted = _question(
      id: wantedId,
      questionType: 'writeCodeQuestion',
      payload: {'type': 'write_code', 'prompt': 'Gezocht.'},
      createdAt: '2026-09-01T10:00:00.000Z',
    );

    /// The same question, asked on another subgoal: the same short ID.
    final twin = _question(
      id: twinId,
      subgoalId: 's3',
      questionType: 'writeCodeQuestion',
      payload: {'type': 'write_code', 'prompt': 'Gezocht.'},
    );

    Future<void> lookUp(WidgetTester tester, String typed) async {
      await tester.enterText(find.byKey(const Key('questions-lookup')), typed);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    bool selected(WidgetTester tester, String subgoalId) => tester
        .widget<ListTile>(find.byKey(Key('questions-subgoal-$subgoalId')))
        .selected;

    String? miss(WidgetTester tester) {
      final f = find.byKey(const Key('questions-lookup-miss'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    Finder foundBadge(String id) => find.byKey(Key('questions-found-$id'));

    /// The id of the card on top of the list.
    String topCard(WidgetTester tester) {
      const prefix = 'questions-card-';
      final ids = [
        for (final e
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(prefix),
                )
                .evaluate())
          (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
      ];
      double top(String id) =>
          tester.getTopLeft(find.byKey(Key('$prefix$id'))).dy;
      return (ids..sort((a, b) => top(a).compareTo(top(b)))).first;
    }

    testWidgets('every card shows its short ID, small and monospace', (
      tester,
    ) async {
      await mount(tester, questions: [_mcq, wanted]);
      await open(tester, 's1');

      final tag = find.byKey(const Key('questions-id-$wantedId'));
      expect(
        find.descendant(
          of: find.byKey(const Key('questions-card-$wantedId')),
          matching: tag,
        ),
        findsOneWidget,
      );
      final text = tester.widget<Text>(
        find.descendant(of: tag, matching: find.byType(Text)),
      );
      expect(text.data, '#3fa91c');
      expect(text.style!.fontSize, lessThan(13));
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('questions-id-s1_mcq')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '#mcq',
      );
    });

    testWidgets('a short ID — with or without #, in capitals — or the whole '
        'doc id selects the subgoal and puts the card on top, marked, with '
        'the hidden-only filter off; clearing unmarks it', (tester) async {
      await mount(tester, questions: [_mcq, _easy, _open, wanted, _variables]);
      // Elsewhere, with the filter on.
      await open(tester, 's2');
      await tester.tap(find.byKey(const Key('questions-filter-hidden')));
      await tester.pumpAndSettle();

      for (final typed in ['#3FA91C', '3fa91c', ' #3fa91c0b ', wantedId]) {
        await lookUp(tester, typed);
        expect(selected(tester, 's1'), isTrue, reason: typed);
        expect(selected(tester, 's2'), isFalse, reason: typed);
        expect(topCard(tester), wantedId, reason: typed);
        expect(
          find.descendant(
            of: foundBadge(wantedId),
            matching: find.text('FOUND'),
          ),
          findsOneWidget,
          reason: typed,
        );
        expect(miss(tester), isNull, reason: typed);
      }
      // The rest of the subgoal is still there, unmarked.
      expect(find.byKey(const Key('questions-card-s1_mcq')), findsOneWidget);
      expect(foundBadge('s1_mcq'), findsNothing);
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('questions-filter-hidden')),
            )
            .selected,
        isFalse,
      );
      expect(find.byKey(const Key('questions-lookup-several')), findsNothing);

      await tester.tap(find.byKey(const Key('questions-lookup-clear')));
      await tester.pumpAndSettle();
      expect(foundBadge(wantedId), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('questions-lookup')))
            .controller!
            .text,
        isEmpty,
      );
      expect(topCard(tester), 's1_open', reason: 'newest first again');
    });

    testWidgets('no hit says the question is not in the bank — not kept or '
        'deleted since — and what is no ID says what one looks like', (
      tester,
    ) async {
      await mount(tester, questions: [_mcq, wanted]);

      await lookUp(tester, '#abcdef');
      expect(
        miss(tester),
        'This question is not in the bank. Usually the first answer to it '
        'was not (fully) correct, and then a question is not kept. Or it was '
        'deleted.',
      );
      expect(find.text('Pick a subgoal on the left.'), findsOneWidget);

      // Typing on clears it.
      await tester.enterText(find.byKey(const Key('questions-lookup')), '#3f');
      await tester.pump();
      expect(miss(tester), isNull);

      // In the tree's ids, but deleted since the page was loaded.
      cosmos['questions'].delete(wantedId, partitionKey: 's1');
      await lookUp(tester, '#3fa91c');
      expect(miss(tester), startsWith('This question is not in the bank.'));
      expect(foundBadge(wantedId), findsNothing);

      await lookUp(tester, '#3fa9');
      expect(
        miss(tester),
        'That is not a question ID. An ID looks like #3fa91c.',
      );
      await lookUp(tester, 'print');
      expect(miss(tester), startsWith('That is not a question ID.'));
    });

    testWidgets('an ID on two subgoals: both are found, and the subgoals are '
        'named to go from one to the other', (tester) async {
      await mount(tester, questions: [wanted, _mcq, twin]);

      await lookUp(tester, '#3fa91c');
      expect(
        find.descendant(
          of: find.byKey(const Key('questions-lookup-several')),
          matching: find.text('2 questions have this ID:'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('questions-lookup-subgoal-s1')),
          matching: find.text('Print'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('questions-lookup-subgoal-s3')),
          matching: find.text('For'),
        ),
        findsOneWidget,
      );
      expect(selected(tester, 's1'), isTrue);
      expect(foundBadge(wantedId), findsOneWidget);

      await tester.tap(find.byKey(const Key('questions-lookup-subgoal-s3')));
      await tester.pumpAndSettle();
      expect(selected(tester, 's3'), isTrue);
      expect(selected(tester, 's1'), isFalse);
      expect(foundBadge(twinId), findsOneWidget);
      expect(topCard(tester), twinId);

      // The whole doc id names one of them.
      await lookUp(tester, wantedId);
      expect(find.byKey(const Key('questions-lookup-several')), findsNothing);
      expect(selected(tester, 's1'), isTrue);
    });

    testWidgets('the tree scrolls to the subgoal a lookup selects', (
      tester,
    ) async {
      // A long curriculum in a short window: the last subgoal is out of
      // view until the lookup selects it.
      String idOf(int i) => 's${i}_${i.toRadixString(16).padLeft(6, '0')}ffff';
      await mount(
        tester,
        goals: [
          _goal('r1', 'Basics'),
          for (var i = 0; i < 30; i++)
            _goal('s$i', 'Subgoal $i', parentId: 'r1', order: i),
        ],
        size: const Size(1280, 700),
        questions: [
          for (var i = 0; i < 30; i++)
            _question(
              id: idOf(i),
              subgoalId: 's$i',
              questionType: 'writeCodeQuestion',
              payload: {'type': 'write_code', 'prompt': 'Vraag $i.'},
            ),
        ],
      );
      final tree = tester.getRect(find.byKey(const Key('questions-tree')));
      Rect tile() =>
          tester.getRect(find.byKey(const Key('questions-subgoal-s29')));
      expect(tile().top, greaterThan(tree.bottom), reason: 'out of view');

      await lookUp(tester, '#00001d');
      expect(selected(tester, 's29'), isTrue);
      expect(tile().top, greaterThanOrEqualTo(tree.top));
      expect(tile().bottom, lessThanOrEqualTo(tree.bottom));
      expect(foundBadge(idOf(29)), findsOneWidget);
    });

    testWidgets('in Dutch', (tester) async {
      await mount(
        tester,
        questions: [_mcq, wanted],
        locale: const Locale('nl'),
      );
      expect(find.text('Zoek op ID'), findsOneWidget);

      await lookUp(tester, '#abcdef');
      expect(
        miss(tester),
        'Deze vraag zit niet in de bank. Meestal was het eerste antwoord '
        'erop niet (helemaal) juist, en dan wordt een vraag niet bewaard. Of '
        'ze werd verwijderd.',
      );
      await lookUp(tester, 'xyz');
      expect(
        miss(tester),
        'Dat is geen vraag-ID. Een ID ziet eruit als #3fa91c.',
      );
      await lookUp(tester, '#3fa91c');
      expect(
        find.descendant(
          of: foundBadge(wantedId),
          matching: find.text('GEVONDEN'),
        ),
        findsOneWidget,
      );
    });
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
