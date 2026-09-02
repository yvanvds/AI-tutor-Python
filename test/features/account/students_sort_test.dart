// Unit tests for the Students page sort model (#87): per-account derived
// row data (hoisted from the cells) and the per-column comparators that
// order the full list before pagination.

import 'package:ai_tutor_python/features/account/students_sort.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account(
  String uid, {
  String email = '',
  String firstName = '',
  String lastName = '',
  String className = '',
  DateTime? createdAt,
  DateTime? updatedAt,
}) => Account(
  uid: uid,
  email: email.isEmpty ? '$uid@example.com' : email,
  firstName: firstName,
  lastName: lastName,
  targetGoal: '',
  className: className,
  createdAt: createdAt,
  updatedAt: updatedAt,
);

StudentRowData _row(
  String uid, {
  String email = '',
  String firstName = '',
  String lastName = '',
  String className = '',
  String? rootTitle,
  double progress = 0.0,
  StudentStatus status = StudentStatus.idle,
  DateTime? lastActive,
}) => StudentRowData(
  account: _account(
    uid,
    email: email,
    firstName: firstName,
    lastName: lastName,
    className: className,
  ),
  lastActive: lastActive,
  goalTitles: rootTitle == null
      ? null
      : (rootTitle: rootTitle, subgoalTitle: null),
  overallProgress: progress,
  status: status,
);

List<String> _uids(List<StudentRowData> rows) => [
  for (final r in rows) r.account.uid,
];

void main() {
  group('StudentRowData.compute', () {
    Goal goal(String id, {String? parentId, bool optional = false}) => Goal(
      id: id,
      title: 'title-$id',
      parentId: parentId,
      order: 0,
      optional: optional,
    );

    final goals = [
      goal('r1'),
      goal('s1', parentId: 'r1'),
      goal('s2', parentId: 'r1'),
    ];
    final goalById = {for (final g in goals) g.id: g};
    final parentByChild = {for (final g in goals) g.id: g.parentId};
    final at = DateTime.parse('2026-05-01T10:00:00Z');

    test('carries the same values the pure helpers produce', () {
      final progress = [
        Progress(goalID: 's1', progress: 1.0, updatedAt: at, lastSessionAt: at),
      ];
      final row = StudentRowData.compute(
        _account('u1'),
        progress: progress,
        goalById: goalById,
        parentByChild: parentByChild,
        now: at,
      );
      // 1.0 over the two non-optional subgoals of r1 (#89).
      expect(row.overallProgress, closeTo(0.5, 1e-9));
      expect(row.goalTitles, (rootTitle: 'title-r1', subgoalTitle: 'title-s1'));
      expect(row.status, StudentStatus.active);
    });

    test('lastActive prefers updatedAt and falls back to createdAt', () {
      final created = DateTime.parse('2026-01-01T00:00:00Z');
      final updated = DateTime.parse('2026-02-01T00:00:00Z');
      final both = StudentRowData.compute(
        _account('u1', createdAt: created, updatedAt: updated),
        progress: const [],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(both.lastActive, updated);
      final createdOnly = StudentRowData.compute(
        _account('u2', createdAt: created),
        progress: const [],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(createdOnly.lastActive, created);
    });

    test('no progress: em-dash goal cell, 0 progress, idle', () {
      final row = StudentRowData.compute(
        _account('u1'),
        progress: const [],
        goalById: goalById,
        parentByChild: parentByChild,
      );
      expect(row.goalTitles, isNull);
      expect(row.overallProgress, 0.0);
      expect(row.status, StudentStatus.idle);
    });
  });

  group('sortStudentRows', () {
    test('email sorts case-insensitively', () {
      final rows = [
        _row('u1', email: 'zoe@school.be'),
        _row('u2', email: 'Anna@school.be'),
        _row('u3', email: 'ben@school.be'),
      ];
      sortStudentRows(rows, key: StudentsSortKey.email, ascending: true);
      expect(_uids(rows), ['u2', 'u3', 'u1']);
    });

    test('name sorts by last name then first name, case-insensitively', () {
      final rows = [
        _row('u1', firstName: 'Zoe', lastName: 'ackers'),
        _row('u2', firstName: 'Anna', lastName: 'Bakkers'),
        _row('u3', firstName: 'Ben', lastName: 'Ackers'),
      ];
      sortStudentRows(rows, key: StudentsSortKey.name, ascending: true);
      expect(_uids(rows), ['u3', 'u1', 'u2']);
    });

    test('descending reverses the order', () {
      final rows = [
        _row('u1', firstName: 'Anna'),
        _row('u2', firstName: 'Ben'),
      ];
      sortStudentRows(rows, key: StudentsSortKey.name, ascending: false);
      expect(_uids(rows), ['u2', 'u1']);
    });

    test('class sorts case-insensitively; classless students group first', () {
      final rows = [
        _row('u1', className: '5b'),
        _row('u2', className: '5A'),
        _row('u3'),
      ];
      sortStudentRows(rows, key: StudentsSortKey.className, ascending: true);
      expect(_uids(rows), ['u3', 'u2', 'u1']);
    });

    test('current goal sorts by root title; goalless rows sort first', () {
      final rows = [
        _row('u1', rootTitle: 'Loops'),
        _row('u2', rootTitle: 'basics'),
        _row('u3'),
      ];
      sortStudentRows(rows, key: StudentsSortKey.currentGoal, ascending: true);
      expect(_uids(rows), ['u3', 'u2', 'u1']);
    });

    test('progress sorts by value', () {
      final rows = [
        _row('u1', progress: 0.5),
        _row('u2', progress: 0.25),
        _row('u3', progress: 1.0),
      ];
      sortStudentRows(rows, key: StudentsSortKey.progress, ascending: true);
      expect(_uids(rows), ['u2', 'u1', 'u3']);
      sortStudentRows(rows, key: StudentsSortKey.progress, ascending: false);
      expect(_uids(rows), ['u3', 'u1', 'u2']);
    });

    test('status sorts active first, most recently active first within '
        'each bucket', () {
      DateTime day(int d) => DateTime.parse('2026-05-0${d}T10:00:00Z');
      final rows = [
        _row('u1', status: StudentStatus.idle, lastActive: day(2)),
        _row('u2', status: StudentStatus.active, lastActive: day(1)),
        _row('u3', status: StudentStatus.idle, lastActive: day(3)),
        _row('u4', status: StudentStatus.active, lastActive: day(4)),
        _row('u5', status: StudentStatus.idle), // never active: very last
      ];
      sortStudentRows(rows, key: StudentsSortKey.status, ascending: true);
      expect(_uids(rows), ['u4', 'u2', 'u3', 'u1', 'u5']);
    });

    test('equal keys fall back to uid order, both directions, so a rebuild '
        'cannot shuffle visually identical rows', () {
      final rows = [
        _row('u3', progress: 0.5),
        _row('u1', progress: 0.5),
        _row('u2', progress: 0.5),
      ];
      sortStudentRows(rows, key: StudentsSortKey.progress, ascending: true);
      expect(_uids(rows), ['u1', 'u2', 'u3']);
      sortStudentRows(rows, key: StudentsSortKey.progress, ascending: false);
      expect(_uids(rows), ['u3', 'u2', 'u1']);
    });
  });
}
