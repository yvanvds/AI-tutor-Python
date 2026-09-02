// Issue #85 — the goals import's Replace mode used to delete every goal not
// in the file across ALL sets. These tests mount the real GoalsPage over the
// real GoalsService (in-memory Cosmos) with a fake file picker, drive the
// import dialogs the way a teacher does, and assert on what actually ends up
// in the store:
//
//   - Replace with a matching root id rewrites that set and leaves every
//     other set byte-for-byte unchanged;
//   - an unrelated root gets the add / replace-a-chosen-set / cancel dialog
//     and never deletes a set the user did not select;
//   - the removal count is shown BEFORE confirmation, and cancelling the
//     preview changes nothing;
//   - the global wipe survives as the separate "Replace all" action.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/features/goals/goals_page.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_file_picker.dart';
import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

Map<String, dynamic> _goal({
  required String id,
  required String title,
  required int order,
  String? parentId,
  String? contentId,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': order,
  'optional': false,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': contentId,
  'moduleId': 'python-basics',
};

/// Two sets: "Basics" (r1 > s1, s2) and "Extra" (r2 > x1). s1 carries a
/// content link that a Replace must preserve.
List<Map<String, dynamic>> _seed() => [
  _goal(id: 'r1', title: 'Basics', order: 1000),
  _goal(
    id: 's1',
    title: 'Print',
    order: 1000,
    parentId: 'r1',
    contentId: 'c-print',
  ),
  _goal(id: 's2', title: 'Variables', order: 2000, parentId: 'r1'),
  _goal(id: 'r2', title: 'Extra', order: 2000),
  _goal(id: 'x1', title: 'Lists', order: 1000, parentId: 'r2'),
];

/// A file whose root matches r1 by id: keeps s1, drops s2, adds s3.
const Map<String, dynamic> _basicsV2 = {
  'version': 2,
  'goals': [
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
  ],
};

/// A file whose root matches nothing that exists.
const Map<String, dynamic> _freshSet = {
  'version': 2,
  'goals': [
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
  ],
};

void main() {
  late Directory dir;
  late InMemoryCosmos goals;
  late ProviderContainer container;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('goals_import_test_');
    goals = InMemoryCosmos(_seed());
    container = ProviderContainer(
      overrides: [
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  String writeImportFile(Map<String, dynamic> payload) {
    final file = File('${dir.path}${Platform.pathSeparator}goals.json');
    file.writeAsStringSync(jsonEncode(payload));
    return file.path;
  }

  Future<void> mountPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(const Scaffold(body: GoalsPage())),
      ),
    );
    // Roots poll, first-root auto-select, children poll.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    // The polling timers never stop; unmount so the test can end.
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  }

  /// Taps [finder] and lets the real file IO behind the import complete —
  /// `File.readAsString` runs on the real event loop, which the fake-async
  /// test zone does not advance on its own. Interleaves real-async turns
  /// with pumps until [expected] shows up (or, when null, a fixed number of
  /// turns has run).
  Future<void> tapAndFlushIo(
    WidgetTester tester,
    Finder finder, {
    Finder? expected,
  }) async {
    await tester.tap(finder);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (expected == null && i >= 2) return;
      if (expected != null && expected.evaluate().isNotEmpty) return;
    }
    if (expected != null) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText())
          .toList();
      fail('nothing matched $expected; visible texts: $texts');
    }
  }

  Map<String, Map<String, dynamic>?> snapshot(Iterable<String> ids) => {
    for (final id in ids) id: goals.read(id),
  };

  testWidgets('Replace with a matching root id rewrites that set and leaves '
      'the other set byte-for-byte unchanged', (tester) async {
    FakeFilePicker(writeImportFile(_basicsV2)).install();
    await mountPage(tester);
    final extraBefore = snapshot(['r2', 'x1']);

    await tapAndFlushIo(
      tester,
      find.text('Import goals'),
      expected: find.text('Replace'),
    );
    await tapAndFlushIo(
      tester,
      find.text('Replace'),
      expected: find.text('Confirm replace'),
    );

    // The removal count is previewed BEFORE anything is written.
    expect(
      find.text('Replaces "Basics" (3 goal(s) in file, 1 will be removed)'),
      findsOneWidget,
    );
    expect(goals['s2'], isNotNull, reason: 'nothing may be deleted yet');

    await tapAndFlushIo(
      tester,
      find.text('Replace'),
      expected: find.text('Imported 3 goal(s) (removed 1 not in file)'),
    );

    expect(snapshot(['r2', 'x1']), extraBefore);
    expect(goals['s2'], isNull);
    expect(goals['s3'], isNotNull);
    expect(goals['r1']!['title'], 'Basics v2');
    expect(
      goals['s1']!['contentId'],
      'c-print',
      reason: 'the lesson content link must survive the re-import',
    );
    expect(
      find.text('Imported 3 goal(s) (removed 1 not in file)'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the preview changes nothing', (tester) async {
    FakeFilePicker(writeImportFile(_basicsV2)).install();
    await mountPage(tester);
    final before = snapshot(['r1', 's1', 's2', 'r2', 'x1']);

    await tapAndFlushIo(
      tester,
      find.text('Import goals'),
      expected: find.text('Replace'),
    );
    await tapAndFlushIo(
      tester,
      find.text('Replace'),
      expected: find.text('Confirm replace'),
    );
    await tapAndFlushIo(tester, find.text('Cancel'));

    expect(snapshot(['r1', 's1', 's2', 'r2', 'x1']), before);
  });

  testWidgets('an unrelated root asks, and replaces only the set chosen in '
      'the dropdown', (tester) async {
    FakeFilePicker(writeImportFile(_freshSet)).install();
    await mountPage(tester);
    final basicsBefore = snapshot(['r1', 's1', 's2']);

    await tapAndFlushIo(
      tester,
      find.text('Import goals'),
      expected: find.text('Replace'),
    );
    await tapAndFlushIo(
      tester,
      find.text('Replace'),
      expected: find.text('No matching set'),
    );

    // Default is "add as a new set"; pick replacing "Extra" instead.
    await tester.tap(find.text('Add as a new set'));
    await tester.pump();
    await tester.tap(find.text('Replace "Extra"').last);
    await tester.pump();
    await tapAndFlushIo(
      tester,
      find.text('Continue'),
      expected: find.text(
        'Replaces "Extra" (2 goal(s) in file, 2 will be removed)',
      ),
    );
    await tapAndFlushIo(
      tester,
      find.text('Replace'),
      expected: find.text('Imported 2 goal(s) (removed 2 not in file)'),
    );

    expect(snapshot(['r1', 's1', 's2']), basicsBefore);
    expect(goals['r2'], isNull);
    expect(goals['x1'], isNull);
    expect(goals['rX'], isNotNull);
    expect(goals['y1'], isNotNull);
  });

  testWidgets('an unrelated root added as a new set deletes nothing', (
    tester,
  ) async {
    FakeFilePicker(writeImportFile(_freshSet)).install();
    await mountPage(tester);
    final before = snapshot(['r1', 's1', 's2', 'r2', 'x1']);

    await tapAndFlushIo(
      tester,
      find.text('Import goals'),
      expected: find.text('Replace'),
    );
    await tapAndFlushIo(
      tester,
      find.text('Replace'),
      expected: find.text('Continue'),
    );
    // Keep the dropdown default: add as a new set.
    await tapAndFlushIo(
      tester,
      find.text('Continue'),
      expected: find.text('Adds new set "Fresh"'),
    );
    await tapAndFlushIo(
      tester,
      find.text('Replace'),
      expected: find.text('Imported 2 goal(s)'),
    );

    expect(snapshot(['r1', 's1', 's2', 'r2', 'x1']), before);
    expect(goals['rX'], isNotNull);
    expect(goals['y1'], isNotNull);
  });

  testWidgets('Replace all still wipes every set, after an explicit confirm '
      'that shows the removal count', (tester) async {
    FakeFilePicker(writeImportFile(_basicsV2)).install();
    await mountPage(tester);

    await tapAndFlushIo(
      tester,
      find.text('Import goals'),
      expected: find.text('Replace all'),
    );
    await tapAndFlushIo(
      tester,
      find.text('Replace all'),
      expected: find.text('Replace all sets'),
    );

    expect(
      find.text(
        'This removes every goal not in the file, across all sets: '
        '3 goal(s) will be removed.',
      ),
      findsOneWidget,
    );
    expect(goals['r2'], isNotNull, reason: 'nothing may be deleted yet');

    await tapAndFlushIo(
      tester,
      find.text('Replace all'),
      expected: find.text('Imported 3 goal(s) (removed 3 not in file)'),
    );

    expect(goals['r2'], isNull);
    expect(goals['x1'], isNull);
    expect(goals['s2'], isNull);
    expect(goals['r1'], isNotNull);
    expect(goals['s3'], isNotNull);
  });
}
