// Issue #210 — a goal tile on the student's own progress list shows the
// goal's title and description in the app language when the goal has a
// translation, else in Dutch without a notice. The teacher's read-only view
// of a student (the detail drawer) shows the Dutch source, as every teacher
// page does.

import 'package:ai_tutor_python/features/progress/goal_tile.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

final _root = Goal(id: 'r1', title: 'Basis', order: 0);
final _printen = Goal(
  id: 's1',
  title: 'Printen',
  description: 'Tekst op het scherm zetten.',
  parentId: 'r1',
  order: 1,
);
final _variabelen = Goal(
  id: 's2',
  title: 'Variabelen',
  description: 'Waarden bewaren.',
  parentId: 'r1',
  order: 2,
);

void main() {
  late InMemoryCosmos store;

  setUp(() {
    store = InMemoryCosmos.partitioned('language', [
      Translation.goal(
        language: 'en',
        goalId: 's1',
        title: 'Printing',
        description: 'Putting text on the screen.',
        sourceHash: goalSourceHash(_printen),
      ).toMap(),
    ]);
  });

  Future<void> mount(WidgetTester tester, {required bool readOnly}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWithValue(const Locale('en')),
          translationServiceProvider.overrideWithValue(
            TranslationService(container: store.container),
          ),
        ],
        child: localizedTestApp(
          Scaffold(
            body: ListView(
              children: [
                for (final goal in [_printen, _variabelen])
                  GoalTile(
                    goal: goal,
                    rootGoal: _root,
                    progress: 0.4,
                    depth: 1,
                    isSubgoal: true,
                    readOnly: readOnly,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('the student sees the translated goal in English and the '
      'untranslated one in Dutch', (tester) async {
    await mount(tester, readOnly: false);

    expect(find.text('Printing'), findsOneWidget);
    expect(find.text('Putting text on the screen.'), findsOneWidget);
    expect(find.text('Printen'), findsNothing);
    expect(find.text('Variabelen'), findsOneWidget);
    expect(find.text('Waarden bewaren.'), findsOneWidget);
  });

  testWidgets('the teacher\'s read-only view shows the Dutch source', (
    tester,
  ) async {
    await mount(tester, readOnly: true);

    expect(find.text('Printen'), findsOneWidget);
    expect(find.text('Tekst op het scherm zetten.'), findsOneWidget);
    expect(find.text('Printing'), findsNothing);
  });
}
