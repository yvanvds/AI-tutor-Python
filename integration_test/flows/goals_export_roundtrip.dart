// End-to-end (#320): the goals export writes a subgoal's concept marking
// (`kind`), so an export followed by an import as a new set (Add) gives the
// concept subgoals back marked. The export used to leave `kind` out; the
// copy then came back as an ordinary goal.
//
// Driven against the real app — shell navigation, the real GoalsPage, the
// real GoalsService over the harness's in-memory Cosmos. The export writes a
// real file (into the harness's own folder, never the real Downloads) and the
// import reads that same file back; only the file picker is faked (an
// OS-owned dialog no test can click).
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/goals_export_roundtrip.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/features/goals/editor/goal_form.dart';
import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_file_picker.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Goals export: the concept marking survives export and import '
      'as a new set', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    final goals = harness.cosmos['goals'];
    // The teacher marked "Print" as a concept goal; "Variables" is not one.
    goals.upsert({...goals.read('s1')!, 'kind': 'concept'});

    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));
    await pumpUntilFound(tester, find.text('Export goals'));

    await tester.tap(find.text('Export goals'));
    await pumpUntilFound(tester, find.textContaining('Exported to '));

    // The file the teacher gets: "Print" carries the marking, "Variables"
    // and the root carry none.
    final files = harness.exportDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final exported =
        jsonDecode(files.single.readAsStringSync()) as Map<String, dynamic>;
    final entry = (exported['goals'] as List).single as Map<String, dynamic>;
    final subgoals = (entry['subgoals'] as List).cast<Map<String, dynamic>>();
    final printOut = subgoals.singleWhere((s) => s['title'] == 'Print');
    final variablesOut = subgoals.singleWhere((s) => s['title'] == 'Variables');
    expect(printOut['kind'], 'concept');
    expect(variablesOut.containsKey('kind'), isFalse);
    expect((entry['goal'] as Map).containsKey('kind'), isFalse);

    // Import that same file as a new set — once the export's message, which
    // lies over the buttons, is gone.
    FakeFilePicker(files.single.path).install();
    await pumpUntil(
      tester,
      () => find.textContaining('Exported to ').evaluate().isEmpty,
      reason: 'the export message never went away',
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Import goals'));
    await pumpUntilFound(tester, find.text('Replace all'));
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await pumpUntilFound(tester, find.text('Imported 3 goal(s)'));

    // The copy: a second "Basics" with its own ids, its "Print" a concept
    // goal, its "Variables" not.
    final copyRoot = goals.docs.values.singleWhere(
      (d) => d['title'] == 'Basics' && d['id'] != 'r1',
    );
    Map<String, dynamic> copyOf(String title) => goals.docs.values.singleWhere(
      (d) => d['title'] == title && d['parentId'] == copyRoot['id'],
    );
    final copyPrint = copyOf('Print');
    expect(copyPrint['kind'], 'concept');
    expect(copyOf('Variables').containsKey('kind'), isFalse);
    expect(copyRoot.containsKey('kind'), isFalse);
    // The original is as it was.
    expect(goals['s1']!['kind'], 'concept');
    expect(goals['s2']!.containsKey('kind'), isFalse);

    // And the teacher sees it: the goal editor of the copy's "Print" has the
    // "Concept goal" switch on.
    final copyRootRow = find.byKey(ValueKey(copyRoot['id'] as String));
    await pumpUntilFound(tester, copyRootRow);
    await tester.tap(copyRootRow);
    final copyPrintRow = find.byKey(ValueKey('child_${copyPrint['id']}'));
    await pumpUntilFound(tester, copyPrintRow);
    await tester.tap(copyPrintRow.first);
    await pumpUntil(
      tester,
      () =>
          find.byType(GoalForm).evaluate().isNotEmpty &&
          tester.widget<GoalForm>(find.byType(GoalForm)).goal.id ==
              copyPrint['id'],
      reason: 'the goal editor never opened on the copy of "Print"',
    );
    final concept = find.widgetWithText(SwitchListTile, 'Concept goal');
    await tester.scrollUntilVisible(
      concept,
      120,
      scrollable: find
          .descendant(
            of: find.byType(GoalForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.widget<SwitchListTile>(concept).value, isTrue);

    await harness.dispose(tester);
  });
}
