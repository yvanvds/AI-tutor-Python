// Issue #210 — the goal editor edits a goal's title and description per
// language. The picker chooses Nederlands (the source, the `goals` doc) or a
// translation language; in a translation language the fields hold the
// goal's translation and Save writes `goal_${id}` to `translations`, made
// from the Dutch text as stored, without touching `goals`. A badge per
// language says which translations the goal has and which are stale —
// keyed apart from the Lesinhoud row's badges for the subgoal's lesson; a
// notice above the fields says when the chosen language has none, or when
// its translation is stale. Switching language with unsaved changes asks
// first.
//
// Mounts the real EditGoalPanel (the goals page's side panel) over the real
// GoalsService / ContentService / TranslationService on in-memory Cosmos,
// with the editor selection set the way a click on a goal row sets it. The
// end-to-end version lives in `integration_test/flows/goal_language.dart`.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/goals/editor/edit_goal_panel.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';
import '../../helpers/unprovisioned_cosmos.dart';

Map<String, dynamic> _goal({
  required String id,
  required String title,
  String? description,
  String? parentId,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'description': description,
  'parentId': parentId,
  'order': 1000,
  'optional': false,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': null,
  'moduleId': 'python-basics',
};

const Key _titleKey = Key('goal-translation-title');
const Key _descKey = Key('goal-translation-description');
const Key _saveKey = Key('goal-translation-save');
const Key _noneKey = Key('goal-translation-none');
const Key _staleKey = Key('goal-translation-stale');
const Key _current = Key('goal-text-translation-status-en-current');
const Key _stale = Key('goal-text-translation-status-en-stale');

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos translations;
  late ProviderContainer container;

  setUp(() {
    goals = InMemoryCosmos([
      _goal(
        id: 'r1',
        title: 'Basis',
        description: 'Je eerste stappen in Python.',
      ),
      _goal(
        id: 's1',
        title: 'Printen',
        description: 'Tekst op het scherm zetten.',
        parentId: 'r1',
      ),
    ]);
    translations = InMemoryCosmos.partitioned('language');
  });

  Goal stored(String id) => Goal.fromCosmos(goals[id]!);

  Map<String, dynamic>? english(String goalId) =>
      translations.read(Translation.goalDocId(goalId), partitionKey: 'en');

  Future<void> mount(
    WidgetTester tester,
    String goalId, {
    CosmosContainer? translationsContainer,
    InMemoryCosmos? content,
  }) async {
    container = ProviderContainer(
      overrides: [
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
        contentServiceProvider.overrideWith(
          () => ContentService(
            container: (content ?? InMemoryCosmos()).container,
          ),
        ),
        translationServiceProvider.overrideWithValue(
          TranslationService(
            container: translationsContainer ?? translations.container,
          ),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1400, 900);
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

  Future<void> pickLanguage(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  String fieldText(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<ButtonStyleButton>(button).onPressed != null;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(_saveKey));
    await settle(tester);
  }

  testWidgets('English without a translation: no badge, a notice, empty '
      'fields that hint at the Dutch text, and Save off until something is '
      'typed', (tester) async {
    await mount(tester, 'r1');

    expect(find.text('Nederlands (source)'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.byKey(_current), findsNothing);
    expect(find.byKey(_stale), findsNothing);
    // Dutch: the goal as stored, no notice.
    expect(fieldText(tester, find.widgetWithText(TextField, 'Title')), 'Basis');
    expect(find.byKey(_noneKey), findsNothing);
    expect(find.byKey(_saveKey), findsNothing);

    await pickLanguage(tester, 'English');

    expect(find.byKey(_noneKey), findsOneWidget);
    expect(
      find.text(
        'This goal has no English translation yet. Students who use the app '
        'in English see the Dutch title and description.',
      ),
      findsOneWidget,
    );
    expect(fieldText(tester, find.byKey(_titleKey)), '');
    expect(fieldText(tester, find.byKey(_descKey)), '');
    expect(
      tester.widget<TextField>(find.byKey(_titleKey)).decoration!.hintText,
      'Basis',
    );
    expect(
      tester.widget<TextField>(find.byKey(_descKey)).decoration!.hintText,
      'Je eerste stappen in Python.',
    );
    expect(enabled(tester, find.byKey(_saveKey)), isFalse);

    await tester.enterText(find.byKey(_titleKey), 'Basics');
    await tester.pump();
    expect(enabled(tester, find.byKey(_saveKey)), isTrue);

    await unmount(tester);
  });

  testWidgets('saving in English writes the translation, made from the '
      'Dutch goal as stored, and leaves `goals` untouched', (tester) async {
    await mount(tester, 'r1');
    final before = Map<String, dynamic>.of(goals['r1']!);

    await pickLanguage(tester, 'English');
    await tester.enterText(find.byKey(_titleKey), 'Basics');
    await tester.enterText(find.byKey(_descKey), 'Your first steps in Python.');
    await tester.pump();
    await save(tester);

    final doc = english('r1');
    expect(doc, isNotNull);
    expect(doc!['kind'], 'goal');
    expect(doc['refId'], 'r1');
    expect(doc['title'], 'Basics');
    expect(doc['description'], 'Your first steps in Python.');
    expect(doc['sourceHash'], goalSourceHash(stored('r1')));
    expect(goals['r1'], before, reason: '`goals` is not written');
    expect(goals.docs, hasLength(2));

    expect(find.text('English translation saved'), findsOneWidget);
    expect(find.byKey(_current), findsOneWidget);
    expect(find.byKey(_noneKey), findsNothing);
    expect(find.byKey(_staleKey), findsNothing);
    expect(
      enabled(tester, find.byKey(_saveKey)),
      isFalse,
      reason: 'nothing left to save',
    );

    // Back to Dutch: the Dutch fields, as they were.
    await pickLanguage(tester, 'Nederlands (source)');
    expect(find.byKey(_titleKey), findsNothing);
    expect(fieldText(tester, find.widgetWithText(TextField, 'Title')), 'Basis');
    expect(find.text('Discard unsaved changes?'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a stored translation fills the fields; a Dutch change on a '
      'later poll makes it stale, and saving it again brings it up to date', (
    tester,
  ) async {
    translations.upsert(
      Translation.goal(
        language: 'en',
        goalId: 's1',
        title: 'Printing',
        description: 'Putting text on the screen.',
        sourceHash: goalSourceHash(stored('s1')),
      ).toMap(),
      partitionKey: 'en',
    );
    await mount(tester, 's1');
    expect(find.byKey(_current), findsOneWidget);

    await pickLanguage(tester, 'English');
    expect(fieldText(tester, find.byKey(_titleKey)), 'Printing');
    expect(
      fieldText(tester, find.byKey(_descKey)),
      'Putting text on the screen.',
    );
    expect(find.byKey(_noneKey), findsNothing);
    expect(find.byKey(_staleKey), findsNothing);
    expect(enabled(tester, find.byKey(_saveKey)), isFalse);

    // The Dutch description changes elsewhere; the next poll brings it in.
    goals.upsert({...goals['s1']!, 'description': 'Tekst tonen met print().'});
    await tester.pump(kCosmosPollInterval);
    await settle(tester);

    expect(find.byKey(_stale), findsOneWidget);
    expect(find.byKey(_current), findsNothing);
    expect(find.byKey(_staleKey), findsOneWidget);
    expect(
      find.text(
        'Outdated: the Dutch title or description changed after this English '
        'translation was made. Update it and save it again.',
      ),
      findsOneWidget,
    );
    // Stale is reason enough to save, even without an edit.
    expect(enabled(tester, find.byKey(_saveKey)), isTrue);

    final before = Map<String, dynamic>.of(goals['s1']!);
    await tester.enterText(find.byKey(_descKey), 'Showing text with print().');
    await tester.pump();
    await save(tester);

    expect(english('s1')!['description'], 'Showing text with print().');
    expect(english('s1')!['sourceHash'], goalSourceHash(stored('s1')));
    expect(goals['s1'], before);
    expect(find.byKey(_current), findsOneWidget);
    expect(find.byKey(_stale), findsNothing);
    expect(find.byKey(_staleKey), findsNothing);

    await unmount(tester);
  });

  testWidgets('switching language with unsaved changes asks first; '
      'discarding writes nothing', (tester) async {
    await mount(tester, 's1');
    await pickLanguage(tester, 'English');
    await tester.enterText(find.byKey(_titleKey), 'Printing');
    await tester.pump();

    await pickLanguage(tester, 'Nederlands (source)');
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    expect(
      find.text(
        'The English title and description have changes that are not saved. '
        'Switching to Nederlands discards them.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(fieldText(tester, find.byKey(_titleKey)), 'Printing');

    await pickLanguage(tester, 'Nederlands (source)');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and switch'));
    await tester.pumpAndSettle();

    expect(find.byKey(_titleKey), findsNothing);
    expect(
      fieldText(tester, find.widgetWithText(TextField, 'Title')),
      'Printen',
    );
    expect(translations.docs, isEmpty);

    // Back in English the discarded text is gone.
    await pickLanguage(tester, 'English');
    expect(fieldText(tester, find.byKey(_titleKey)), '');

    await unmount(tester);
  });

  testWidgets('a translation stored elsewhere reaches untouched fields on the '
      'next poll, but never overwrites what the teacher typed', (tester) async {
    await mount(tester, 's1');
    await pickLanguage(tester, 'English');
    expect(fieldText(tester, find.byKey(_titleKey)), '');

    Map<String, dynamic> printing(String title) => Translation.goal(
      language: 'en',
      goalId: 's1',
      title: title,
      description: 'Putting text on the screen.',
      sourceHash: goalSourceHash(stored('s1')),
    ).toMap();

    translations.upsert(printing('Printing'), partitionKey: 'en');
    await tester.pump(kCosmosPollInterval);
    await settle(tester);
    expect(fieldText(tester, find.byKey(_titleKey)), 'Printing');
    expect(find.byKey(_current), findsOneWidget);
    expect(find.byKey(_noneKey), findsNothing);

    await tester.enterText(find.byKey(_titleKey), 'Print things');
    await tester.pump();
    translations.upsert(printing('Output'), partitionKey: 'en');
    await tester.pump(kCosmosPollInterval);
    await settle(tester);
    expect(fieldText(tester, find.byKey(_titleKey)), 'Print things');

    await unmount(tester);
  });

  testWidgets('an empty title falls back on the Dutch title', (tester) async {
    await mount(tester, 's1');
    await pickLanguage(tester, 'English');
    await tester.enterText(find.byKey(_descKey), 'Putting text on the screen.');
    await tester.pump();
    await save(tester);

    expect(english('s1')!['title'], 'Printen');
    expect(english('s1')!['description'], 'Putting text on the screen.');
    expect(fieldText(tester, find.byKey(_titleKey)), 'Printen');

    await unmount(tester);
  });

  testWidgets('the goal badge and the Lesinhoud row\'s lesson badge are '
      'keyed apart: an up-to-date goal translation next to a stale lesson '
      'translation', (tester) async {
    final lesson = Content(id: 's1', title: 'Printen', body: '<p>Zo.</p>');
    final content = InMemoryCosmos([
      {...lesson.toMap(), 'type': 'content'},
    ]);
    goals.upsert({...goals['s1']!, 'contentId': 's1'});
    translations
      ..upsert(
        Translation.goal(
          language: 'en',
          goalId: 's1',
          title: 'Printing',
          description: 'Putting text on the screen.',
          sourceHash: goalSourceHash(stored('s1')),
        ).toMap(),
        partitionKey: 'en',
      )
      ..upsert(
        Translation.content(
          language: 'en',
          contentId: 's1',
          title: 'Printing',
          body: '<p>Like this.</p>',
          // Made from an older Dutch lesson.
          sourceHash: contentSourceHash(
            Content(id: 's1', title: 'Printen', body: '<p>Eerder.</p>'),
          ),
        ).toMap(),
        partitionKey: 'en',
      );
    await mount(tester, 's1', content: content);

    expect(find.byKey(_current), findsOneWidget);
    expect(find.byKey(_stale), findsNothing);
    expect(
      find.byKey(const Key('translation-status-en-stale')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('translation-status-en-current')),
      findsNothing,
      reason: 'the goal badge must not pass for the lesson badge',
    );

    await unmount(tester);
  });

  testWidgets('without a translations container, saving says what to do and '
      'writes nothing', (tester) async {
    final missing = UnprovisionedCosmos('translations');
    await mount(tester, 's1', translationsContainer: missing.container);
    final before = Map<String, dynamic>.of(goals['s1']!);

    await pickLanguage(tester, 'English');
    await tester.enterText(find.byKey(_titleKey), 'Printing');
    await tester.pump();
    await save(tester);

    expect(
      find.text(
        'Translations cannot be saved yet: the Cosmos container '
        '`translations` does not exist. Create it with partition key '
        '`/language` (README, step 3).',
      ),
      findsOneWidget,
    );
    expect(goals['s1'], before);
    // Still unsaved.
    expect(fieldText(tester, find.byKey(_titleKey)), 'Printing');
    expect(enabled(tester, find.byKey(_saveKey)), isTrue);

    await unmount(tester);
  });
}

/// The goal, content and translation polls, and the writes after a tap.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}
