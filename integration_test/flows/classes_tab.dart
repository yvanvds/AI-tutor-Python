// End-to-end (#218): the teacher's Classes tab, and the class of a student
// chosen from it on the Students page.
//
// Before #218 a class existed only as free text on the accounts: the
// teacher typed it for every new student, and a typo ("6 WEWI") made an
// extra class in the Students and Reports filters. Now the classes are a
// list — one `classes` doc in the `config` container — each with its weekly
// lessons in local clock time, which #219 and #220 read through
// `classLessonsProvider`.
//
// The flow, against the real app (rail navigation, the real ClassesPage and
// AccountsPage over the harness's in-memory Cosmos, real 5 s polls, the real
// time picker in the real font):
//   1. the class names already on accounts (6EWI, 6WEWI) are offered and
//      taken into the list with one click each; the typo is left out;
//   2. 6EWI gets a lesson: weekday from the list, start typed into the time
//      picker, the 50-minute length kept — and the app's own provider
//      answers "the lessons of 6EWI" with it;
//   3. a class with students cannot be deleted; renaming it moves both its
//      students along and keeps the lesson;
//   4. a new class without students can be deleted;
//   5. on the Students page the account with the typo shows its class with
//      a warning, and picking 6WEWI from the class list fixes it.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/classes_tab.dart -d windows

import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/classes/classes_page.dart';
import 'package:ai_tutor_python/services/classes/classes_service.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

Map<String, dynamic> _studentDoc(
  String uid,
  String first, {
  required String className,
}) => {
  'id': uid,
  'uid': uid,
  'email': '$uid@example.com',
  'firstName': first,
  'lastName': 'Student',
  'targetGoal': '',
  'mayUseGlobalKey': true,
  'createdAt': '2026-09-02T10:00:00Z',
  'updatedAt': '2026-09-02T10:00:00Z',
  'className': className,
};

/// Pumps a dropdown's or a dialog's open/close animation through, the way
/// the Reports flow drives its class filter.
Future<void> _animate(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Classes tab: take over the class names on accounts, give a '
      'class its lessons, rename it with its students, and choose a '
      "student's class from the list", (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    final accounts = harness.cosmos['accounts'];
    final config = harness.cosmos['config'];
    accounts.upsert(_studentDoc('it-anna', 'Anna', className: '6EWI'));
    accounts.upsert(_studentDoc('it-ben', 'Ben', className: '6EWI'));
    accounts.upsert(_studentDoc('it-cara', 'Cara', className: '6WEWI'));
    accounts.upsert(_studentDoc('it-dave', 'Dave', className: '6 WEWI'));

    List<String> listed() => [
      for (final c in (config['classes']?['classes'] as List?) ?? const [])
        (c as Map)['name'] as String,
    ];
    List<dynamic> lessonsOf(String name) {
      for (final c in (config['classes']?['classes'] as List?) ?? const []) {
        if ((c as Map)['name'] == name) return c['lessons'] as List;
      }
      return const [];
    }

    await tester.tap(find.byTooltip('Classes'));
    await pumpUntilFound(tester, find.byType(ClassesPage));

    // 1. The account poll brings the class names that are on accounts.
    await pumpUntilFound(tester, find.byKey(const Key('class-adopt-6EWI')));
    expect(find.text('On accounts, not in the list'), findsOneWidget);
    expect(find.byKey(const Key('class-adopt-6WEWI')), findsOneWidget);
    expect(find.byKey(const Key('class-adopt-6 WEWI')), findsOneWidget);
    expect(config['classes'], isNull, reason: 'nothing is written by itself');

    await tester.tap(find.byKey(const Key('class-adopt-6EWI')));
    await pumpUntilFound(tester, find.byKey(const Key('class-row-6EWI')));
    await tester.tap(find.byKey(const Key('class-adopt-6WEWI')));
    await pumpUntilFound(tester, find.byKey(const Key('class-row-6WEWI')));
    expect(listed(), ['6EWI', '6WEWI']);
    expect(config['global']?['Model'], 'gpt-4o', reason: 'global untouched');
    expect(
      find.descendant(
        of: find.byKey(const Key('class-row-6EWI')),
        matching: find.text('2 students'),
      ),
      findsOneWidget,
    );
    // The typo stays where it is, still offered.
    expect(find.byKey(const Key('class-adopt-6 WEWI')), findsOneWidget);

    // 2. A lesson for 6EWI.
    await tester.tap(find.byKey(const Key('class-row-6EWI')));
    await pumpUntilFound(tester, find.byKey(const Key('lesson-add')));
    expect(find.text('No lessons yet.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lesson-add')));
    await pumpUntilFound(tester, find.byKey(const Key('lesson-weekday-0')));
    expect(lessonsOf('6EWI'), [
      {'weekday': 1, 'start': '08:30', 'end': '09:20'},
    ]);

    await tester.tap(find.byKey(const Key('lesson-weekday-0')));
    await _animate(tester);
    await tester.tap(find.text('Tuesday').last);
    await _animate(tester);
    await pumpUntil(
      tester,
      () => lessonsOf('6EWI').single['weekday'] == DateTime.tuesday,
      reason: 'the weekday should be written to config/classes',
    );

    await tester.tap(find.byKey(const Key('lesson-start-0')));
    await pumpUntilFound(tester, find.byType(TimePickerDialog));
    final timeFields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(timeFields.first, '10');
    await tester.enterText(timeFields.last, '50');
    await tester.tap(find.text('OK'));
    await pumpUntil(
      tester,
      () => lessonsOf('6EWI').single['start'] == '10:50',
      reason: 'the start from the time picker should be written',
    );
    // The lesson kept its 50 minutes.
    expect(lessonsOf('6EWI').single, {
      'weekday': 2,
      'start': '10:50',
      'end': '11:40',
    });
    await pumpUntilFound(tester, find.text('11:40'));
    expect(find.text('10:50'), findsOneWidget);

    // What #219 asks — the lessons of a class, and whether a moment is in
    // one — answered by the app's own provider, from the same list.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ClassesPage)),
    );
    const lesson = LessonSlot(
      weekday: DateTime.tuesday,
      startMinute: 10 * 60 + 50,
      endMinute: 11 * 60 + 40,
    );
    expect(container.read(classLessonsProvider('6EWI')), [lesson]);
    expect(container.read(classLessonsProvider('6WEWI')), isEmpty);
    final classes = container.read(classesServiceProvider)!;
    expect(
      classes.isDuringLesson(
        '6EWI',
        DateTime(2026, 10, 6, 10, 41),
        margin: const Duration(minutes: 10),
      ),
      isTrue,
    );
    expect(
      classes.isDuringLesson('6EWI', DateTime(2026, 10, 6, 19, 0)),
      isFalse,
    );

    // 3. 6EWI has students: no delete. A rename takes them along.
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('class-delete')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('class-rename')));
    await pumpUntilFound(tester, find.byKey(const Key('class-name-input')));
    expect(
      find.text('The 2 students in this class move along.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('class-name-input')), '6EWI-A');
    await tester.tap(find.byKey(const Key('class-name-save')));
    await pumpUntil(
      tester,
      () =>
          accounts['it-anna']?['className'] == '6EWI-A' &&
          accounts['it-ben']?['className'] == '6EWI-A' &&
          listed().contains('6EWI-A'),
      reason: 'the rename should move both students and the list entry',
    );
    expect(listed(), ['6EWI-A', '6WEWI']);
    expect(lessonsOf('6EWI-A').single['start'], '10:50');
    expect(accounts['it-cara']?['className'], '6WEWI');
    expect(accounts['it-dave']?['className'], '6 WEWI');
    await pumpUntilFound(tester, find.byKey(const Key('class-row-6EWI-A')));
    // Once the account poll is back, the old name is not offered again: no
    // account carries it any more.
    await pumpUntil(
      tester,
      () => find
          .descendant(
            of: find.byKey(const Key('class-row-6EWI-A')),
            matching: find.text('2 students'),
          )
          .evaluate()
          .isNotEmpty,
      reason: 'the renamed class should count its two students',
    );
    expect(find.byKey(const Key('class-adopt-6EWI')), findsNothing);

    // 4. A new class with nobody in it can go again.
    await tester.tap(find.byKey(const Key('classes-new')));
    await pumpUntilFound(tester, find.byKey(const Key('class-name-input')));
    await tester.enterText(find.byKey(const Key('class-name-input')), '5A');
    await tester.tap(find.byKey(const Key('class-name-save')));
    await pumpUntilFound(tester, find.byKey(const Key('class-row-5A')));
    expect(listed(), ['5A', '6EWI-A', '6WEWI']);
    await pumpUntil(
      tester,
      () =>
          tester
              .widget<IconButton>(find.byKey(const Key('class-delete')))
              .onPressed !=
          null,
      reason: 'an empty class should be deletable',
    );
    await tester.tap(find.byKey(const Key('class-delete')));
    await pumpUntilFound(tester, find.byKey(const Key('class-delete-confirm')));
    await tester.tap(find.byKey(const Key('class-delete-confirm')));
    await pumpUntilGone(tester, find.byKey(const Key('class-row-5A')));
    expect(listed(), ['6EWI-A', '6WEWI']);

    // 5. The Students page: Dave's typo is shown as it is, with a warning;
    // the class list fixes it.
    await tester.tap(find.byTooltip('Students'));
    await pumpUntilFound(tester, find.byType(AccountsPage));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('class-unlisted-it-dave')),
    );
    expect(find.byKey(const Key('class-unlisted-it-cara')), findsNothing);
    expect(find.byKey(const Key('class-unlisted-it-anna')), findsNothing);

    await tester.tap(find.byKey(const Key('class-cell-it-dave')));
    await pumpUntilFound(tester, classChoiceField());
    expect(find.text('Not in the class list.'), findsOneWidget);
    await chooseClassAndSave(tester, '6WEWI');
    await pumpUntil(
      tester,
      () => accounts['it-dave']?['className'] == '6WEWI',
      reason: 'the class from the list should land on the account doc',
    );
    await pumpUntilGone(
      tester,
      find.byKey(const Key('class-unlisted-it-dave')),
    );

    await harness.dispose(tester);
  });
}
