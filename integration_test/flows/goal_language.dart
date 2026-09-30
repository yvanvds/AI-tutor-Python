// End-to-end (#210): goal titles and descriptions in the student's
// language, and per language in the goal editor.
//
// The teacher picks English in the goal editor, types the goal's English
// title and description and saves: `goal_${id}` lands in `translations`,
// made from the Dutch goal as stored, and `goals` is not written. The
// editor's badge says the translation is up to date; the goals tree, a
// teacher page, keeps the Dutch title. A Dutch edit afterwards makes the
// translation stale, which the badge and the English notice then say.
//
// Sam's app runs in English (the harness pins an en-US desktop). With English
// translations of the root goal and the first subgoal, the learning path,
// the header above the theory page, the "Current goal" banner in practice
// and the goal picker behind "Reset one goal…" all name them in English; the
// untranslated subgoal keeps its Dutch title, without a notice. Switching to
// Nederlands brings the Dutch titles back.
//
// Real app, real navigation, real goals page and goal editor, real leerpad,
// theory, practice and Options pages, real GoalsService / TranslationService
// polling the (in-memory) Cosmos containers. Only the model and the lesson
// runner are scripted.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/goal_language.dart -d windows

import 'package:ai_tutor_python/features/goals/child_row.dart';
import 'package:ai_tutor_python/features/goals/editor/goal_form.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_card.dart';
import 'package:ai_tutor_python/features/progress/widgets/leerpad_child_chip.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/lesson/lesson_code_runner.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

const Key kTitle = Key('goal-translation-title');
const Key kDescription = Key('goal-translation-description');
const Key kSave = Key('goal-translation-save');
const Key kNone = Key('goal-translation-none');
const Key kStaleNotice = Key('goal-translation-stale');
const Key kCurrent = Key('goal-text-translation-status-en-current');
const Key kStale = Key('goal-text-translation-status-en-stale');

/// A seeded goal as the app reads it from `goals`.
Goal seededGoal(String id, String title, {String? parentId}) =>
    Goal.fromCosmos(goalDoc(id: id, title: title, parentId: parentId));

/// The English translation of a seeded goal, made from its Dutch text as
/// seeded.
Map<String, dynamic> englishGoal(
  Goal goal, {
  required String title,
  required String description,
}) => Translation.goal(
  language: 'en',
  goalId: goal.id,
  title: title,
  description: description,
  sourceHash: goalSourceHash(goal),
).toMap();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(GoalForm), matching: finder);

  String text(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;

  testWidgets('the teacher saves a goal in English: only `translations` is '
      'written, the badge says up to date, the goals tree stays Dutch, and a '
      'Dutch edit makes the translation stale', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    final goals = harness.cosmos['goals'];
    final translations = harness.cosmos['translations'];
    final dutchDoc = goals.read('s1')!;

    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));
    await pumpUntilFound(tester, find.text('Print'));
    await tester.tap(find.text('Print').first);
    // The editor on "Print" — not one still open on another goal, nor the
    // spinner the panel shows while it loads the goal just picked.
    await pumpUntil(
      tester,
      () =>
          find.byType(GoalForm).evaluate().isNotEmpty &&
          tester.widget<GoalForm>(find.byType(GoalForm)).goal.id == 's1',
      reason: 'the goal editor never opened on "Print"',
    );
    await pumpUntilFound(tester, inForm(find.text('English')));
    expect(inForm(find.byKey(kCurrent)), findsNothing);

    await tester.tap(inForm(find.text('English')));
    await pumpUntilFound(tester, find.byKey(kNone));
    expect(text(tester, find.byKey(kTitle)), '');

    await tester.enterText(find.byKey(kTitle), 'Printing');
    await tester.enterText(
      find.byKey(kDescription),
      'Putting text on the screen.',
    );
    await tester.pump();
    await tester.tap(find.byKey(kSave));
    await pumpUntilFound(tester, find.text('English translation saved'));

    final stored = translations.read('goal_s1', partitionKey: 'en');
    expect(stored, isNotNull);
    expect(stored!['title'], 'Printing');
    expect(stored['description'], 'Putting text on the screen.');
    expect(stored['sourceHash'], goalSourceHash(Goal.fromCosmos(dutchDoc)));
    expect(goals.read('s1'), dutchDoc, reason: '`goals` is not written');
    await pumpUntilFound(tester, inForm(find.byKey(kCurrent)));
    expect(find.byKey(kNone), findsNothing);

    // The goals tree is a teacher page: Dutch, whatever the app language.
    // Its next poll comes and goes without the English title.
    await tester.pump(const Duration(seconds: 6));
    expect(
      find.descendant(of: find.byType(ChildRow), matching: find.text('Print')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ChildRow),
        matching: find.text('Printing'),
      ),
      findsNothing,
    );

    // Back to Dutch, and a Dutch edit: the translation goes stale.
    await tester.tap(inForm(find.text('Nederlands (source)')));
    await pumpUntilGone(tester, find.byKey(kTitle));
    final dutchTitle = inForm(find.widgetWithText(TextField, 'Title'));
    expect(text(tester, dutchTitle), 'Print');
    await tester.enterText(dutchTitle, 'Printen');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpUntil(
      tester,
      () => goals.read('s1')!['title'] == 'Printen',
      reason: 'the Dutch title was never saved',
    );
    expect(
      translations.read('goal_s1', partitionKey: 'en'),
      stored,
      reason: 'a Dutch edit leaves the translation as it is',
    );
    await pumpUntilFound(tester, inForm(find.byKey(kStale)));
    expect(inForm(find.byKey(kCurrent)), findsNothing);

    await tester.tap(inForm(find.text('English')));
    await pumpUntilFound(tester, find.byKey(kStaleNotice));
    expect(text(tester, find.byKey(kTitle)), 'Printing');

    await harness.dispose(tester);
  });

  testWidgets('in English the student sees translated goals in English on '
      'the learning path, above the theory, in the practice banner and in '
      'the reset picker, the untranslated one in Dutch; Nederlands brings '
      'the Dutch titles back', (tester) async {
    final root = seededGoal('r1', 'Basics');
    final print = seededGoal('s1', 'Print', parentId: 'r1');
    final harness = AppHarness(
      extraDocs: {
        'translations': [
          englishGoal(
            root,
            title: 'The basics',
            description: 'Your first steps in Python.',
          ),
          englishGoal(
            print,
            title: 'Printing',
            description: 'Putting text on the screen.',
          ),
        ],
      },
      lessonResults: {
        kLessonExampleCode: const LessonRunResult(stdout: 'Hallo Mira'),
      },
    );
    await harness.boot(tester);

    Finder onPath(Finder finder) =>
        find.descendant(of: find.byType(LeerpadPage), matching: finder);
    Finder chip(String goalId) => find.byWidgetPredicate(
      (w) => w is LeerpadChildChip && w.goal.id == goalId,
    );

    // The learning path.
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(LeerpadCard),
        matching: find.text('The basics'),
      ),
    );
    expect(onPath(find.text('Your first steps in Python.')), findsOneWidget);
    expect(
      find.descendant(of: chip('s1'), matching: find.text('Printing')),
      findsOneWidget,
    );
    // No translation: the Dutch title, and nothing that says so.
    expect(
      find.descendant(of: chip('s2'), matching: find.text('Variables')),
      findsOneWidget,
    );
    expect(onPath(find.text('Basics')), findsNothing);
    expect(onPath(find.text('Print')), findsNothing);
    expect(onPath(find.textContaining('Dutch')), findsNothing);

    // The header above the theory page.
    await tester.tap(find.text('Continue'));
    await pumpUntilFound(tester, find.byType(ExplainView));
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(ExplainView),
        matching: find.text('THE BASICS'),
      ),
    );

    // The "Current goal" banner in practice.
    await tester.tap(find.text('Try it yourself'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    Finder banner(Finder finder) =>
        find.descendant(of: find.byType(ObjectiveBanner), matching: finder);
    await pumpUntilFound(tester, banner(find.text('Printing')));
    expect(banner(find.text('Putting text on the screen.')), findsOneWidget);
    expect(banner(find.text('Print')), findsNothing);

    // The goal picker behind "Reset one goal…".
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    final resetOne = find.text('Reset one goal…');
    await tester.scrollUntilVisible(
      resetOne,
      120,
      scrollable: optionsScrollable(),
    );
    await tester.ensureVisible(resetOne);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(resetOne);
    await pumpUntilFound(tester, find.text('Reset progress for a goal'));
    await pumpUntilFound(tester, find.widgetWithText(ListTile, 'The basics'));
    expect(find.widgetWithText(ListTile, 'Printing'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Variables'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Basics'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await pumpUntilGone(tester, find.text('Reset progress for a goal'));

    // Nederlands: the goals as written.
    tester.state<ScrollableState>(optionsScrollable()).position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));
    await tester.tap(find.byTooltip('Leerpad'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(
      tester,
      find.descendant(
        of: find.byType(LeerpadCard),
        matching: find.text('Basics'),
      ),
    );
    expect(
      find.descendant(of: chip('s1'), matching: find.text('Print')),
      findsOneWidget,
    );
    expect(onPath(find.text('The basics')), findsNothing);
    expect(onPath(find.text('Printing')), findsNothing);

    await harness.dispose(tester);
  });
}
