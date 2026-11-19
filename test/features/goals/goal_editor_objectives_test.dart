// Issue #313 — the goal editor shows the learning objectives of a subgoal,
// in the order of `objectives`: the id read-only (beliefs, stamps,
// `turn_history`, milestones and translations are keyed on it); the text,
// kind, weight and optional flag editable, stored together with the block's
// Save button. Saving writes `objectives` and leaves the rest of the doc —
// the concept marking, fields this build does not know — as it was. In
// another language the block edits the translation of each text
// (`objective_${subgoal}.${lo}` in `translations`), with the Dutch text as
// the hint. The description field grows with its text, and `allowChains`
// has a switch.
//
// Mounts the real EditGoalPanel (the goals page's side panel) over the real
// GoalsService / ContentService / TranslationService on in-memory Cosmos,
// with the editor selection set the way a click on a subgoal row sets it.
// The end-to-end version lives in `integration_test/flows/goal_objectives.dart`.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/goals/editor/edit_goal_panel.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

const _longDescription =
    'Je leert de vaste patronen waarmee je een lijst doorloopt: tellen, '
    'optellen, het grootste zoeken en filteren. Bij elk patroon hoort een '
    'variabele die je voor de lus een beginwaarde geeft en in de lus '
    'bijwerkt. Wie die vier patronen herkent, kan de meeste oefeningen met '
    'lijsten oplossen zonder telkens opnieuw te moeten beginnen.';

const _loop = 'Je kan een lijst doorlopen met een for-lus.';
const _count = 'Je kan voorspellen hoe vaak een lus loopt.';

Map<String, dynamic> _goal({
  required String id,
  required String title,
  String? description,
  String? parentId,
  List<Map<String, dynamic>> objectives = const [],
  Map<String, dynamic> extra = const {},
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'description': description,
  'parentId': parentId,
  'order': 1000,
  'optional': false,
  'teachingTips': const <String>['Begin met een voorbeeld.'],
  'allowChains': false,
  'objectives': objectives,
  'contentId': null,
  'moduleId': 'python-basics',
  ...extra,
};

/// A stored doc without Cosmos' own fields (`_etag`).
Map<String, dynamic> _plain(Map<String, dynamic> doc) =>
    Map.of(doc)..removeWhere((k, _) => k.startsWith('_'));

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos translations;
  late ProviderContainer container;

  setUp(() {
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Lussen'),
      _goal(
        id: 's1',
        title: 'Lijstpatronen',
        description: _longDescription,
        parentId: 'r1',
        // The concept marking and a field this build does not know: a save
        // of the objectives must leave both.
        extra: const {'kind': 'concept', 'authoringNote': 'v3'},
        objectives: [
          {
            'id': 'lo-loop',
            'statement': _loop,
            'kind': 'apply',
            'weight': 1.0,
            'optional': false,
            // Not a field this build knows either.
            'since': '2026-09',
          },
          {
            'id': 'lo-count',
            'statement': _count,
            'kind': 'predict',
            'weight': 0.5,
            'optional': true,
          },
        ],
      ),
    ]);
    translations = InMemoryCosmos.partitioned('language');
  });

  Goal stored(String id) => Goal.fromCosmos(goals[id]!);

  List<Map<String, dynamic>> storedObjectives() => [
    for (final o in goals['s1']!['objectives'] as List)
      Map<String, dynamic>.from(o as Map),
  ];

  Map<String, dynamic>? english(String loId) => translations.read(
    Translation.objectiveDocId('s1', loId),
    partitionKey: 'en',
  );

  Future<void> mount(WidgetTester tester, String goalId) async {
    container = ProviderContainer(
      overrides: [
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
        contentServiceProvider.overrideWith(
          () => ContentService(container: InMemoryCosmos().container),
        ),
        translationServiceProvider.overrideWithValue(
          TranslationService(container: translations.container),
        ),
      ],
    );
    // Tall enough for the whole form: nothing to scroll to.
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container
        .read(goalSelectionProvider.notifier)
        .setEditorSelectedGoal(stored(goalId));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(
          const Scaffold(
            // Same slot the goals page gives the panel.
            body: Row(children: [SizedBox(width: 720, child: EditGoalPanel())]),
          ),
        ),
      ),
    );
    // Panel animation, then the goal and translation polls.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  Finder field(String loId, String part) =>
      find.byKey(Key('objective-$loId-$part'));
  final save = find.byKey(const Key('goal-objectives-save'));

  String fieldText(WidgetTester tester, Finder f) =>
      tester.widget<TextField>(f).controller!.text;

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<ButtonStyleButton>(button).onPressed != null;

  Future<void> pickLanguage(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  testWidgets('a subgoal shows its learning objectives in order: the id as '
      'plain text, the text, kind, weight and optional flag in fields, and '
      'Save off until something changes', (tester) async {
    await mount(tester, 's1');

    expect(find.text('Learning objectives'), findsOneWidget);
    // The id is shown, and is not a field.
    expect(find.text('lo-loop'), findsOneWidget);
    expect(find.text('lo-count'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'lo-loop'), findsNothing);
    expect(
      tester.getTopLeft(field('lo-loop', 'id')).dy,
      lessThan(tester.getTopLeft(field('lo-count', 'id')).dy),
    );

    expect(fieldText(tester, field('lo-loop', 'statement')), _loop);
    expect(fieldText(tester, field('lo-count', 'statement')), _count);
    expect(fieldText(tester, field('lo-loop', 'weight')), '1.0');
    expect(fieldText(tester, field('lo-count', 'weight')), '0.5');
    expect(
      tester.widget<DropdownButton<LoKind>>(field('lo-loop', 'kind')).value,
      LoKind.apply,
    );
    expect(
      tester.widget<DropdownButton<LoKind>>(field('lo-count', 'kind')).value,
      LoKind.predict,
    );
    expect(
      tester.widget<Checkbox>(field('lo-loop', 'optional')).value,
      isFalse,
    );
    expect(
      tester.widget<Checkbox>(field('lo-count', 'optional')).value,
      isTrue,
    );
    expect(enabled(tester, save), isFalse);

    // The text wraps inside the 420 px panel instead of running out of it.
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('saving writes the edited text, kind, weight and optional flag '
      'to `objectives`, keeps ids and order, and leaves the rest of the doc — '
      'the concept marking and unknown fields — as it was', (tester) async {
    await mount(tester, 's1');
    final before = _plain(goals['s1']!);

    await tester.enterText(
      field('lo-loop', 'statement'),
      'Je kan elk element van een lijst bezoeken met een for-lus.',
    );
    await tester.enterText(field('lo-loop', 'weight'), '1,5');
    await tester.tap(field('lo-loop', 'optional'));
    await tester.tap(field('lo-count', 'kind'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reason').last);
    await tester.pumpAndSettle();
    expect(enabled(tester, save), isTrue);
    expect(_plain(goals['s1']!), before, reason: 'nothing written before Save');

    await tester.tap(save);
    await settle(tester);

    expect(storedObjectives(), [
      {
        'id': 'lo-loop',
        'statement':
            'Je kan elk element van een lijst bezoeken met een for-lus.',
        'kind': 'apply',
        'weight': 1.5,
        'optional': true,
        'since': '2026-09',
      },
      {
        'id': 'lo-count',
        'statement': _count,
        'kind': 'reason',
        'weight': 0.5,
        'optional': true,
      },
    ]);
    final after = _plain(goals['s1']!);
    expect(after['kind'], 'concept');
    expect(after['authoringNote'], 'v3');
    expect(
      after..remove('objectives'),
      Map.of(before)..remove('objectives'),
      reason: 'only `objectives` is written',
    );
    expect(goals.docs, hasLength(2));
    expect(translations.docs, isEmpty);

    expect(
      find.text(
        'Learning objectives saved. Change the goal\'s JSON file too: a '
        'replace import overwrites what you changed here.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, save), isFalse, reason: 'nothing left to save');

    // The next poll brings the stored objectives back: the fields stay.
    await tester.pump(kCosmosPollInterval);
    await settle(tester);
    expect(
      fieldText(tester, field('lo-loop', 'statement')),
      'Je kan elk element van een lijst bezoeken met een for-lus.',
    );
    expect(fieldText(tester, field('lo-loop', 'weight')), '1.5');
    expect(enabled(tester, save), isFalse);

    await unmount(tester);
  });

  testWidgets('an empty text or a weight that is not a number above 0 keeps '
      'Save off and writes nothing', (tester) async {
    await mount(tester, 's1');
    final before = _plain(goals['s1']!);

    await tester.enterText(field('lo-loop', 'weight'), 'veel');
    await tester.pump();
    expect(find.text('The weight is a number above 0.'), findsOneWidget);
    expect(enabled(tester, save), isFalse);

    await tester.enterText(field('lo-loop', 'weight'), '0');
    await tester.pump();
    expect(enabled(tester, save), isFalse);

    await tester.enterText(field('lo-loop', 'weight'), '2');
    await tester.pump();
    expect(find.text('The weight is a number above 0.'), findsNothing);
    expect(enabled(tester, save), isTrue);

    await tester.enterText(field('lo-count', 'statement'), '   ');
    await tester.pump();
    expect(find.text('A learning objective needs a text.'), findsOneWidget);
    expect(enabled(tester, save), isFalse);
    expect(_plain(goals['s1']!), before);

    await unmount(tester);
  });

  testWidgets('a poll never overwrites what the teacher typed, and brings a '
      'change made elsewhere into untouched fields', (tester) async {
    await mount(tester, 's1');

    // Changed elsewhere, nothing typed here: the fields follow.
    final doc = goals['s1']!;
    goals.upsert({
      ..._plain(doc),
      'objectives': [
        {...storedObjectives()[0], 'statement': 'Je kan een lijst doorlopen.'},
        storedObjectives()[1],
      ],
    });
    await tester.pump(kCosmosPollInterval);
    await settle(tester);
    expect(
      fieldText(tester, field('lo-loop', 'statement')),
      'Je kan een lijst doorlopen.',
    );
    expect(enabled(tester, save), isFalse);

    // Typed, not saved: the next poll leaves it.
    await tester.enterText(field('lo-loop', 'statement'), 'Half getypt');
    await tester.pump();
    await tester.pump(kCosmosPollInterval);
    await settle(tester);
    expect(fieldText(tester, field('lo-loop', 'statement')), 'Half getypt');
    expect(enabled(tester, save), isTrue);

    await unmount(tester);
  });

  testWidgets('in English the block edits the translation of each text, with '
      'the Dutch text as the hint; saving writes `translations` only, and a '
      'Dutch change afterwards makes that translation stale', (tester) async {
    await mount(tester, 's1');
    final before = _plain(goals['s1']!);

    await pickLanguage(tester, 'English');

    // Kind, weight and optional do not depend on the language.
    expect(field('lo-loop', 'statement'), findsNothing);
    expect(field('lo-loop', 'weight'), findsNothing);
    expect(find.text('lo-loop'), findsOneWidget);
    expect(fieldText(tester, field('lo-loop', 'translation')), '');
    expect(
      tester
          .widget<TextField>(field('lo-loop', 'translation'))
          .decoration!
          .hintText,
      _loop,
    );
    expect(field('lo-loop', 'translation-none'), findsOneWidget);
    expect(field('lo-count', 'translation-none'), findsOneWidget);
    expect(find.text('No English translation yet.'), findsNWidgets(2));
    expect(enabled(tester, save), isFalse);

    await tester.enterText(
      field('lo-loop', 'translation'),
      'You can go through a list with a for loop.',
    );
    await tester.pump();
    expect(enabled(tester, save), isTrue);
    await tester.tap(save);
    await settle(tester);

    final doc = english('lo-loop');
    expect(doc, isNotNull);
    expect(doc!['kind'], 'objective');
    expect(doc['refId'], 's1.lo-loop');
    expect(doc['statement'], 'You can go through a list with a for loop.');
    expect(doc['sourceHash'], objectiveSourceHash(stored('s1').objectives[0]));
    expect(english('lo-count'), isNull, reason: 'only what was typed');
    expect(_plain(goals['s1']!), before, reason: '`goals` is not written');
    expect(find.text('English learning objectives saved'), findsOneWidget);
    expect(field('lo-loop', 'translation-none'), findsNothing);
    expect(field('lo-loop', 'translation-stale'), findsNothing);
    expect(field('lo-count', 'translation-none'), findsOneWidget);
    expect(enabled(tester, save), isFalse);

    // The Dutch text changes: the translation is stale, and says what the
    // Dutch text is now.
    goals.upsert({
      ...before,
      'objectives': [
        {...storedObjectives()[0], 'statement': 'Je kan een lijst doorlopen.'},
        storedObjectives()[1],
      ],
    });
    await tester.pump(kCosmosPollInterval);
    await settle(tester);
    expect(field('lo-loop', 'translation-stale'), findsOneWidget);
    expect(
      find.text('Outdated. The Dutch text is now: Je kan een lijst doorlopen.'),
      findsOneWidget,
    );

    // Still right as it stands: stamped with the new Dutch text.
    await tester.tap(field('lo-loop', 'translation-confirm'));
    await settle(tester);
    expect(
      english('lo-loop')!['statement'],
      'You can go through a list with a for loop.',
    );
    expect(
      english('lo-loop')!['sourceHash'],
      objectiveSourceHash(stored('s1').objectives[0]),
    );
    expect(field('lo-loop', 'translation-stale'), findsNothing);

    // Emptied and saved: the translation is gone, the student reads Dutch.
    await tester.enterText(field('lo-loop', 'translation'), '');
    await tester.pump();
    await tester.tap(save);
    await settle(tester);
    expect(english('lo-loop'), isNull);
    expect(field('lo-loop', 'translation-none'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a stored translation fills its field; switching language '
      'with an unsaved objective translation asks first, and the Dutch '
      'fields keep what was typed there', (tester) async {
    translations.upsert(
      Translation.objective(
        language: 'en',
        subgoalId: 's1',
        loId: 'lo-count',
        statement: 'You can predict how often a loop runs.',
        sourceHash: objectiveSourceHash(stored('s1').objectives[1]),
      ).toMap(),
      partitionKey: 'en',
    );
    await mount(tester, 's1');

    // Typed in Dutch, not saved.
    await tester.enterText(field('lo-loop', 'statement'), 'Nog niet klaar');
    await tester.pump();

    await pickLanguage(tester, 'English');
    expect(
      fieldText(tester, field('lo-count', 'translation')),
      'You can predict how often a loop runs.',
    );
    expect(field('lo-count', 'translation-none'), findsNothing);
    expect(field('lo-count', 'translation-stale'), findsNothing);

    await tester.enterText(field('lo-count', 'translation'), 'Something else');
    await tester.pump();
    await pickLanguage(tester, 'Nederlands (source)');
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    expect(
      find.text(
        'The English texts, learning objectives included, have changes that '
        'are not saved. Switching to Nederlands discards them.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Discard and switch'));
    await tester.pumpAndSettle();

    expect(fieldText(tester, field('lo-loop', 'statement')), 'Nog niet klaar');
    expect(
      english('lo-count')!['statement'],
      'You can predict how often a loop runs.',
    );

    // Back in English the discarded text is gone.
    await pickLanguage(tester, 'English');
    expect(
      fieldText(tester, field('lo-count', 'translation')),
      'You can predict how often a loop runs.',
    );

    await unmount(tester);
  });

  testWidgets('a long description shows in full: the field grows with the '
      'text', (tester) async {
    await mount(tester, 's1');

    final description = find.widgetWithText(TextField, _longDescription);
    expect(description, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: description, matching: find.byType(EditableText)),
    );
    expect(editable.maxLines, isNull);
    // Every line is laid out inside the field: more than the three lines
    // it used to stop at, and nothing to scroll to.
    final render = tester
        .state<EditableTextState>(
          find.descendant(of: description, matching: find.byType(EditableText)),
        )
        .renderEditable;
    expect(render.size.height, greaterThan(render.preferredLineHeight * 3.5));
    expect(render.maxScrollExtent, 0);

    await unmount(tester);
  });

  testWidgets('the follow-up chains switch writes `allowChains`', (
    tester,
  ) async {
    await mount(tester, 's1');
    final before = _plain(goals['s1']!);

    await tester.tap(find.byKey(const Key('goal-allow-chains')));
    await settle(tester);

    expect(goals['s1']!['allowChains'], isTrue);
    expect(
      _plain(goals['s1']!)..remove('allowChains'),
      Map.of(before)..remove('allowChains'),
    );

    await unmount(tester);
  });

  testWidgets('a root goal has no learning objectives block', (tester) async {
    await mount(tester, 'r1');

    expect(find.byKey(const Key('goal-objectives')), findsNothing);
    expect(find.text('Learning objectives'), findsNothing);

    await unmount(tester);
  });
}

/// The goal, content and translation polls, and the writes after a tap.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}
