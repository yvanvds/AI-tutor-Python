// The Klassen page (#218), mounted alone over the real ClassesService and
// AccountService on an in-memory Cosmos: the list with its student counts,
// the one-click add for class names that are on accounts but not in the
// list, delete only for an empty class, rename moving the students along,
// and a class's lessons — weekday from a list, times from the time picker.

import 'package:ai_tutor_python/features/classes/classes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

Map<String, dynamic> _account(String uid, String className) => {
  'id': uid,
  'uid': uid,
  'email': '$uid@example.com',
  'firstName': uid,
  'lastName': 'Student',
  'targetGoal': '',
  'mayUseGlobalKey': false,
  'className': className,
  'createdAt': '2026-09-01T10:00:00Z',
};

const _global = {
  'id': 'global',
  'type': 'config',
  'Model': 'gpt-4o',
  'ApiKey': '',
};

Map<String, dynamic> _classesDoc() => {
  'id': 'classes',
  'type': 'config',
  'classes': [
    {
      'name': '6EWI',
      'lessons': [
        {'weekday': 2, 'start': '10:50', 'end': '11:40'},
      ],
    },
    {'name': '5A', 'lessons': []},
  ],
};

void main() {
  late InMemoryCosmosClient cosmos;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cosmos = InMemoryCosmosClient({
      'accounts': InMemoryCosmos([
        _account('a1', '6EWI'),
        _account('a2', '6EWI'),
        _account('a3', '6WEWI'),
        _account('a4', ''),
      ]),
      'config': InMemoryCosmos([_global, _classesDoc()]),
    })..install();
    await tester.pumpWidget(
      ProviderScope(
        child: localizedTestApp(
          const Scaffold(body: ClassesPage()),
          locale: locale,
        ),
      ),
    );
    await settle(tester);
  }

  List<Map<String, dynamic>> storedClasses() => [
    for (final c in cosmos['config']['classes']!['classes'] as List)
      Map<String, dynamic>.from(c as Map),
  ];

  List<dynamic> storedLessons(String name) =>
      storedClasses().firstWhere((c) => c['name'] == name)['lessons'] as List;

  Future<void> select(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(Key('class-row-$name')));
    await settle(tester);
  }

  testWidgets('lists the classes with their student counts, and the names '
      'on accounts that are not in the list', (tester) async {
    await mount(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('class-row-6EWI')),
        matching: find.text('2 students'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('class-row-5A')),
        matching: find.text('no students'),
      ),
      findsOneWidget,
    );
    expect(find.text('On accounts, not in the list'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('class-unlisted-row-6WEWI')),
        matching: find.text('1 student'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('one click adds a class name that is on accounts, exactly as '
      'it is written there', (tester) async {
    await mount(tester);

    await tester.tap(find.byKey(const Key('class-adopt-6WEWI')));
    await settle(tester);

    expect(storedClasses().map((c) => c['name']), ['5A', '6EWI', '6WEWI']);
    expect(find.text('On accounts, not in the list'), findsNothing);
    expect(find.byKey(const Key('class-row-6WEWI')), findsOneWidget);
    // It opens on the right, with its student.
    expect(find.byKey(const Key('class-editor-name')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('class-editor-name'))).data,
      '6WEWI',
    );
  });

  testWidgets('a class with students cannot be deleted; an empty one can', (
    tester,
  ) async {
    await mount(tester);

    await select(tester, '6EWI');
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('class-delete')))
          .onPressed,
      isNull,
    );

    await select(tester, '5A');
    await tester.tap(find.byKey(const Key('class-delete')));
    await settle(tester);
    expect(find.text('Delete 5A?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('class-delete-confirm')));
    await settle(tester);

    expect(storedClasses().map((c) => c['name']), ['6EWI']);
    expect(find.byKey(const Key('class-row-5A')), findsNothing);
  });

  testWidgets('a new class needs a name no other class has, up to case', (
    tester,
  ) async {
    await mount(tester);

    await tester.tap(find.byKey(const Key('classes-new')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('class-name-save')));
    await settle(tester);
    expect(find.text('Give the class a name.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('class-name-input')), '6ewi');
    await tester.tap(find.byKey(const Key('class-name-save')));
    await settle(tester);
    expect(find.text('There already is a class 6EWI.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('class-name-input')), ' 7A ');
    await tester.tap(find.byKey(const Key('class-name-save')));
    await settle(tester);

    expect(storedClasses().map((c) => c['name']), ['5A', '6EWI', '7A']);
    expect(find.byKey(const Key('class-row-7A')), findsOneWidget);
  });

  testWidgets('renaming a class moves its students along and keeps its '
      'lessons', (tester) async {
    await mount(tester);

    await select(tester, '6EWI');
    await tester.tap(find.byKey(const Key('class-rename')));
    await settle(tester);
    expect(
      find.text('The 2 students in this class move along.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('class-name-input')), '6EWI-A');
    await tester.tap(find.byKey(const Key('class-name-save')));
    await settle(tester);

    final accounts = cosmos['accounts'];
    expect(accounts['a1']!['className'], '6EWI-A');
    expect(accounts['a2']!['className'], '6EWI-A');
    expect(accounts['a3']!['className'], '6WEWI');
    expect(accounts['a4']!['className'], '');
    expect(storedClasses().map((c) => c['name']), ['5A', '6EWI-A']);
    expect(storedLessons('6EWI-A'), [
      {'weekday': 2, 'start': '10:50', 'end': '11:40'},
    ]);
    expect(
      tester.widget<Text>(find.byKey(const Key('class-editor-name'))).data,
      '6EWI-A',
    );
  });

  testWidgets('lessons: add one, pick its weekday, its start keeps its length '
      'and an end before the start is refused', (tester) async {
    await mount(tester);
    await select(tester, '6EWI');
    expect(find.text('Tuesday'), findsOneWidget);

    // A second lesson: the same period, the next day.
    await tester.tap(find.byKey(const Key('lesson-add')));
    await settle(tester);
    expect(storedLessons('6EWI'), [
      {'weekday': 2, 'start': '10:50', 'end': '11:40'},
      {'weekday': 3, 'start': '10:50', 'end': '11:40'},
    ]);

    // Weekday from the list: Wednesday becomes Friday.
    await tester.tap(find.byKey(const Key('lesson-weekday-1')));
    await settle(tester);
    await tester.tap(find.text('Friday').last);
    await settle(tester);
    expect(storedLessons('6EWI')[1], {
      'weekday': 5,
      'start': '10:50',
      'end': '11:40',
    });

    // Start from the time picker, typed: 10:00 keeps the 50 minutes.
    await tester.tap(find.byKey(const Key('lesson-start-1')));
    await settle(tester);
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '10');
    await tester.enterText(fields.last, '00');
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(storedLessons('6EWI')[1], {
      'weekday': 5,
      'start': '10:00',
      'end': '10:50',
    });

    // A double period: the end moves on its own.
    await tester.tap(find.byKey(const Key('lesson-end-1')));
    await settle(tester);
    await tester.enterText(fields.first, '11');
    await tester.enterText(fields.last, '40');
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(storedLessons('6EWI')[1]['end'], '11:40');

    // An end before the start is refused, and nothing is written.
    await tester.tap(find.byKey(const Key('lesson-end-1')));
    await settle(tester);
    await tester.enterText(fields.first, '09');
    await tester.enterText(fields.last, '30');
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('A lesson has to end after it starts.'), findsOneWidget);
    expect(storedLessons('6EWI')[1]['end'], '11:40');

    // And one goes again.
    await tester.tap(find.byKey(const Key('lesson-delete-0')));
    await settle(tester);
    expect(storedLessons('6EWI'), [
      {'weekday': 5, 'start': '10:00', 'end': '11:40'},
    ]);
  });

  testWidgets('in Dutch the weekdays and counts are Dutch', (tester) async {
    await mount(tester, locale: const Locale('nl'));

    expect(
      find.descendant(
        of: find.byKey(const Key('class-row-6EWI')),
        matching: find.text('2 leerlingen'),
      ),
      findsOneWidget,
    );
    expect(find.text('Op accounts, nog niet in de lijst'), findsOneWidget);
    await select(tester, '6EWI');
    expect(find.text('Dinsdag'), findsOneWidget);
  });
}
