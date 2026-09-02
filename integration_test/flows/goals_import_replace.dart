// End-to-end (#85): the goals import's Replace is scoped to the set the file
// names. It used to delete every goal not in the file across ALL sets; now it
// matches each root entry to an existing root, previews the removal count
// before writing, and never touches a set the user has not seen named.
//
// Driven against the real app — shell navigation, the real GoalsPage, the
// real GoalsService over the harness's in-memory Cosmos — with only the file
// picker faked (an OS-owned dialog no test can click); the picked file is
// read from the real disk.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/goals_import_replace.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_file_picker.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// A second set next to the seeded "Basics" — the one Replace must not touch.
void _seedExtraSet(AppHarness harness) {
  final goals = harness.cosmos['goals'];
  goals.upsert(goalDoc(id: 'r2', title: 'Extra', order: 2000));
  goals.upsert(goalDoc(id: 'x1', title: 'Lists', parentId: 'r2', order: 1000));
}

String _writeImportFile(List<Map<String, dynamic>> entries) {
  final dir = Directory.systemTemp.createTempSync('goals_import_it_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}${Platform.pathSeparator}goals.json');
  file.writeAsStringSync(jsonEncode({'version': 2, 'goals': entries}));
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Goals import: Replace rewrites only the set the file names', (
    tester,
  ) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    _seedExtraSet(harness);
    final goals = harness.cosmos['goals'];
    final extraBefore = {'r2': goals.read('r2'), 'x1': goals.read('x1')};

    // A new version of "Basics": same root id, keeps Print, drops Variables,
    // adds Loops.
    FakeFilePicker(
      _writeImportFile([
        {
          'goal': {
            'id': 'r1',
            'title': 'Basics v2',
            'order': 1000,
            'optional': false,
            'moduleId': 'python-basics',
          },
          'subgoals': [
            {'id': 's1', 'title': 'Print', 'order': 1000},
            {'id': 's3', 'title': 'Loops', 'order': 2000},
          ],
        },
      ]),
    ).install();

    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));
    await pumpUntilFound(tester, find.text('Import goals'));

    await tester.tap(find.text('Import goals'));
    await pumpUntilFound(tester, find.text('Replace all'));
    await tester.tap(find.text('Replace'));

    // The removal count is shown BEFORE anything is written (#85).
    await pumpUntilFound(
      tester,
      find.text('Replaces "Basics" (3 goal(s) in file, 1 will be removed)'),
    );
    expect(goals['s2'], isNotNull, reason: 'nothing may be deleted yet');

    // The mode dialog's own "Replace" is still animating out when the
    // preview appears; wait until the preview's confirm is the only one.
    await pumpUntil(
      tester,
      () => find.text('Replace').evaluate().length == 1,
      reason: 'the mode dialog should have finished closing',
    );
    await tester.tap(find.text('Replace'));
    await pumpUntilFound(
      tester,
      find.text('Imported 3 goal(s) (removed 1 not in file)'),
    );

    // The other set is byte-for-byte unchanged.
    expect(goals.read('r2'), extraBefore['r2']);
    expect(goals.read('x1'), extraBefore['x1']);
    // The named set was replaced: Variables gone, Loops added, and the
    // authored lesson link on Print survived.
    expect(goals['s2'], isNull);
    expect(goals['s3'], isNotNull);
    expect(goals['r1']!['title'], 'Basics v2');
    expect(goals['s1']!['contentId'], 's1');

    await harness.dispose(tester);
  });

  testWidgets('Goals import: an unrelated root never wipes a set the user '
      'did not pick', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);
    _seedExtraSet(harness);
    final goals = harness.cosmos['goals'];
    final basicsBefore = {
      'r1': goals.read('r1'),
      's1': goals.read('s1'),
      's2': goals.read('s2'),
    };

    FakeFilePicker(
      _writeImportFile([
        {
          'goal': {
            'id': 'rX',
            'title': 'Fresh',
            'order': 1000,
            'optional': false,
            'moduleId': 'python-basics',
          },
          'subgoals': [
            {'id': 'y1', 'title': 'Intro', 'order': 1000},
          ],
        },
      ]),
    ).install();

    await tester.tap(find.byTooltip('Goals'));
    await pumpUntilFound(tester, find.byType(GoalsPage));
    await pumpUntilFound(tester, find.text('Import goals'));

    await tester.tap(find.text('Import goals'));
    await pumpUntilFound(tester, find.text('Replace all'));
    await tester.tap(find.text('Replace'));

    // Nothing matches "Fresh", so the app asks instead of deleting.
    await pumpUntilFound(tester, find.text('No matching set'));
    await tester.tap(find.text('Add as a new set'));
    await pumpUntilFound(tester, find.text('Replace "Extra"'));
    await tester.tap(find.text('Replace "Extra"').last);
    await tester.pump();
    await tester.tap(find.text('Continue'));

    await pumpUntilFound(
      tester,
      find.text('Replaces "Extra" (2 goal(s) in file, 2 will be removed)'),
    );
    await pumpUntil(
      tester,
      () => find.text('Replace').evaluate().length == 1,
      reason: 'earlier dialogs should have finished closing',
    );
    await tester.tap(find.text('Replace'));
    await pumpUntilFound(tester, find.textContaining('Imported 2 goal(s)'));

    // Only the chosen set was replaced.
    expect(goals.read('r1'), basicsBefore['r1']);
    expect(goals.read('s1'), basicsBefore['s1']);
    expect(goals.read('s2'), basicsBefore['s2']);
    expect(goals['r2'], isNull);
    expect(goals['x1'], isNull);
    expect(goals['rX'], isNotNull);
    expect(goals['y1'], isNotNull);

    await harness.dispose(tester);
  });
}
