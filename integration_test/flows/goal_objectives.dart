// End-to-end (#313): the goal editor shows and edits the learning objectives
// of a subgoal.
//
// The teacher opens the subgoal "Print" on the Goals page. The editor lists
// its learning objective: the id as plain text, the text, kind, weight and
// optional flag in fields. The teacher rewrites the text, picks another kind
// and saves: `goals` holds the new text and kind under the same id, and the
// rest of the doc — the concept marking included — is as it was. Then, in
// English, the teacher types the translation of the objective and saves:
// `objective_s1.lo-print` lands in `translations`, made from the Dutch text
// as stored, and `goals` is not written again.
//
// Real app, real navigation, real goals page and goal editor in its real
// 420 px panel, real GoalsService / TranslationService polling the
// (in-memory) Cosmos containers.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/goal_objectives.dart -d windows

import 'package:ai_tutor_python/features/goals/editor/goal_form.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

const Key kBlock = Key('goal-objectives');
const Key kSave = Key('goal-objectives-save');
const Key kId = Key('objective-lo-print-id');
const Key kStatement = Key('objective-lo-print-statement');
const Key kKind = Key('objective-lo-print-kind');
const Key kWeight = Key('objective-lo-print-weight');
const Key kOptional = Key('objective-lo-print-optional');
const Key kTranslation = Key('objective-lo-print-translation');
const Key kNone = Key('objective-lo-print-translation-none');

/// A stored doc without Cosmos' own fields (`_etag`).
Map<String, dynamic> plain(Map<String, dynamic> doc) =>
    Map.of(doc)..removeWhere((k, _) => k.startsWith('_'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(GoalForm), matching: finder);

  /// The goal form's own list, not a text field's scroll view inside it —
  /// the list comes first.
  Finder formScrollable() => find
      .descendant(of: find.byType(GoalForm), matching: find.byType(Scrollable))
      .first;

  String text(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<ButtonStyleButton>(button).onPressed != null;

  /// Scrolls the goal form until [finder] is on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120, scrollable: formScrollable());
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the teacher sees the learning objective of a subgoal in the '
      'goal editor, rewrites it and saves: `goals` keeps the id and the rest '
      'of the doc; in English the translation of the text is saved to '
      '`translations`', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    final goals = harness.cosmos['goals'];
    final translations = harness.cosmos['translations'];
    // The concept marking: a save of the objectives must leave it.
    goals.upsert({...goals.read('s1')!, 'kind': 'concept'});
    final before = plain(goals.read('s1')!);

    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));
    await pumpUntilFound(tester, find.text('Print'));
    await tester.tap(find.text('Print').first);
    await pumpUntil(
      tester,
      () =>
          find.byType(GoalForm).evaluate().isNotEmpty &&
          tester.widget<GoalForm>(find.byType(GoalForm)).goal.id == 's1',
      reason: 'the goal editor never opened on "Print"',
    );

    // The objective, as stored.
    await reveal(tester, find.byKey(kStatement));
    expect(inForm(find.byKey(kBlock)), findsOneWidget);
    expect(inForm(find.text('Learning objectives')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(kBlock), matching: find.text('lo-print')),
      findsOneWidget,
    );
    expect(tester.widget(find.byKey(kId)), isNot(isA<TextField>()));
    expect(text(tester, find.byKey(kStatement)), 'Use print() to show text');
    await reveal(tester, find.byKey(kWeight));
    expect(text(tester, find.byKey(kWeight)), '1.0');
    expect(
      tester.widget<DropdownButton<LoKind>>(find.byKey(kKind)).value,
      LoKind.apply,
    );
    expect(tester.widget<Checkbox>(find.byKey(kOptional)).value, isFalse);
    await reveal(tester, find.byKey(kSave));
    expect(enabled(tester, find.byKey(kSave)), isFalse);

    // A new text and another kind.
    await reveal(tester, find.byKey(kStatement));
    await tester.enterText(
      find.byKey(kStatement),
      'Je kan met print() tekst en de waarde van een variabele op het '
      'scherm tonen, ook meerdere waarden in dezelfde regel.',
    );
    await tester.pump();
    await reveal(tester, find.byKey(kKind));
    await tester.tap(find.byKey(kKind));
    await pumpUntilFound(tester, find.text('Predict'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Predict').last);
    await pumpUntil(
      tester,
      () =>
          tester.widget<DropdownButton<LoKind>>(find.byKey(kKind)).value ==
          LoKind.predict,
      reason: 'the kind was never picked',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(plain(goals.read('s1')!), before, reason: 'not written before Save');

    await reveal(tester, find.byKey(kSave));
    expect(enabled(tester, find.byKey(kSave)), isTrue);
    await tester.tap(find.byKey(kSave));
    await pumpUntilFound(
      tester,
      find.textContaining('Learning objectives saved.'),
    );
    // The long text wraps in the panel: no overflow on the way.
    expect(tester.takeException(), isNull);

    final after = plain(goals.read('s1')!);
    expect(after['objectives'], [
      {
        'id': 'lo-print',
        'statement':
            'Je kan met print() tekst en de waarde van een variabele op het '
            'scherm tonen, ook meerdere waarden in dezelfde regel.',
        'kind': 'predict',
        'weight': 1.0,
        'optional': false,
      },
    ]);
    expect(after['kind'], 'concept');
    expect(
      Map.of(after)..remove('objectives'),
      Map.of(before)..remove('objectives'),
      reason: 'only `objectives` is written',
    );
    expect(translations.docs, isEmpty);

    // The next poll brings the stored objective back: the field keeps it.
    await tester.pump(const Duration(seconds: 6));
    expect(
      text(tester, find.byKey(kStatement)),
      startsWith('Je kan met print() tekst'),
    );
    expect(enabled(tester, find.byKey(kSave)), isFalse);

    // English: the translation of the text.
    // The language picker is at the top of the form.
    tester.state<ScrollableState>(formScrollable()).position.jumpTo(0);
    await pumpUntilFound(tester, inForm(find.text('English')));
    await tester.tap(inForm(find.text('English')));
    await pumpUntilGone(tester, find.byKey(kStatement));
    await reveal(tester, find.byKey(kTranslation));
    await pumpUntilFound(tester, find.byKey(kNone));
    expect(text(tester, find.byKey(kTranslation)), '');
    expect(
      tester.widget<TextField>(find.byKey(kTranslation)).decoration!.hintText,
      startsWith('Je kan met print() tekst'),
    );
    await tester.enterText(
      find.byKey(kTranslation),
      'You can show text and the value of a variable with print().',
    );
    await tester.pump();
    await reveal(tester, find.byKey(kSave));
    await tester.tap(find.byKey(kSave));
    await pumpUntilFound(
      tester,
      find.text('English learning objectives saved'),
    );

    final stored = translations.read(
      'objective_s1.lo-print',
      partitionKey: 'en',
    );
    expect(stored, isNotNull);
    expect(
      stored!['statement'],
      'You can show text and the value of a variable with print().',
    );
    expect(
      stored['sourceHash'],
      objectiveSourceHash(Goal.fromCosmos(goals.read('s1')!).objectives.single),
    );
    expect(plain(goals.read('s1')!), after, reason: '`goals` is not written');
    await pumpUntilGone(tester, find.byKey(kNone));
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
}
