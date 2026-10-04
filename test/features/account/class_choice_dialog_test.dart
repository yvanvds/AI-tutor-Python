// #218 — a student's class is chosen from the class list, plus "no class",
// instead of typed. The dialog is shared by the class cell (one student) and
// the bulk assignment (#91).

import 'package:ai_tutor_python/features/account/class_choice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localization.dart';

void main() {
  /// Opens the dialog from a button and reports what it popped.
  Future<List<String?>> open(
    WidgetTester tester, {
    required List<String> classNames,
    String? initial,
    Locale locale = const Locale('en'),
  }) async {
    final popped = <String?>[];
    await tester.pumpWidget(
      localizedTestApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => popped.add(
                await showDialog<String>(
                  context: context,
                  builder: (_) => ClassChoiceDialog(
                    classNames: classNames,
                    initial: initial,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.byKey(const Key('class-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  FilledButton save(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('class-choice-save')));

  testWidgets('offers the classes and "no class", and pops the choice', (
    tester,
  ) async {
    final popped = await open(
      tester,
      classNames: const ['6EWI', '6WEWI'],
      initial: '6EWI',
    );

    await tester.tap(find.byKey(const Key('class-choice')));
    await tester.pumpAndSettle();
    expect(find.text('No class'), findsWidgets);
    expect(find.text('6WEWI'), findsWidgets);
    await tester.tap(find.text('6WEWI').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, ['6WEWI']);
  });

  testWidgets('"no class" pops an empty name, which clears the class', (
    tester,
  ) async {
    final popped = await open(
      tester,
      classNames: const ['6EWI'],
      initial: '6EWI',
    );

    await choose(tester, 'No class');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, ['']);
  });

  testWidgets('a class that is not in the list is shown as it is, with a '
      'warning, and kept unless another is chosen', (tester) async {
    final popped = await open(
      tester,
      classNames: const ['6EWI', '6WEWI'],
      initial: '6 WEWI',
    );

    expect(find.text('6 WEWI'), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    expect(find.text('Not in the class list.'), findsOneWidget);

    await choose(tester, '6WEWI');
    expect(find.text('Not in the class list.'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, ['6WEWI']);
  });

  testWidgets('for a selection nothing is chosen yet, and Save waits for a '
      'choice', (tester) async {
    final popped = await open(tester, classNames: const ['6EWI']);

    expect(find.text('Choose a class'), findsOneWidget);
    expect(save(tester).onPressed, isNull);

    await choose(tester, '6EWI');
    expect(save(tester).onPressed, isNotNull);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(popped, ['6EWI']);
  });

  testWidgets('without classes it says where to add them', (tester) async {
    await open(tester, classNames: const [], initial: '');

    expect(
      find.text('There are no classes yet. Add them on the Classes page.'),
      findsOneWidget,
    );
  });

  testWidgets('cancel pops nothing', (tester) async {
    final popped = await open(
      tester,
      classNames: const ['6EWI'],
      initial: '6EWI',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(popped, [null]);
  });

  testWidgets('in Dutch: "Geen klas" and "Kies een klas"', (tester) async {
    await open(tester, classNames: const ['6EWI'], locale: const Locale('nl'));

    expect(find.text('Kies een klas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('class-choice')));
    await tester.pumpAndSettle();
    expect(find.text('Geen klas'), findsWidgets);
  });
}
