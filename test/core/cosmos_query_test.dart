// The query interpreter shared by the stand-alone storage and the test fake
// (#263): it must understand every query the app sends, and refuse what it
// does not understand.

import 'dart:io';

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_query.dart';
import 'package:flutter_test/flutter_test.dart';

/// Queries in `lib/` built with interpolation, as the scan reads them (up to
/// the first quote inside an interpolation), and what they expand to. A new
/// interpolated query fails the scan below until it is listed here.
const Map<String, List<String>> _interpolated = {
  // ProgressService._fetchHistory.
  r"SELECT $top* FROM c WHERE ${clauses.join(": [
    'SELECT * FROM c WHERE c.uid = @uid ORDER BY c.at ASC',
    'SELECT TOP 5 * FROM c WHERE c.uid = @uid AND c.goalId = @goalId '
        'AND c.at >= @since ORDER BY c.at ASC',
  ],
};

/// Every SQL text in `lib/`: each run of adjacent single-quoted literals
/// that starts with `SELECT`.
List<String> _queriesInLib() {
  final literalRun = RegExp(r"(?:'(?:[^'\\\n]|\\.)*'\s*)+");
  final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
  final out = <String>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final source = file.readAsStringSync();
    for (final run in literalRun.allMatches(source)) {
      final text = literal
          .allMatches(run.group(0)!)
          .map((m) => m.group(1)!)
          .join();
      if (!text.startsWith('SELECT ')) continue;
      out.add(text);
    }
  }
  return out;
}

final _docs = <Map<String, dynamic>>[
  {'id': 'a', 'uid': 'u1', 'order': 2, 'title': 'B', 'parentId': null},
  {
    'id': 'b',
    'uid': 'u1',
    'order': 1,
    'title': 'A',
    'parentId': 'a',
    'signalEvents': ['x'],
  },
  {'id': 'c', 'uid': 'u2', 'order': 3, 'signalEvents': <String>[]},
  {
    'id': 'd',
    'uid': 'u1',
    'signalEvents': ['y'],
    'acknowledgedAt': '2026-01-01',
  },
];

List<String> _ids(List<Map<String, dynamic>> rows) => [
  for (final r in rows) r['id'] as String,
];

void main() {
  test('understands every query in lib/', () {
    final queries = _queriesInLib();
    // The services send about forty; a scan that finds a handful is broken.
    expect(queries.length, greaterThan(30));
    final failures = <String>[];
    for (final sql in queries) {
      final variants = sql.contains(r'$') ? _interpolated[sql] : [sql];
      if (variants == null) {
        failures.add('interpolated, add its expansions to the test: $sql');
        continue;
      }
      for (final v in variants) {
        try {
          CosmosQuery.parse(v);
        } on CosmosException catch (e) {
          failures.add(e.message);
        }
      }
    }
    expect(failures, isEmpty);
  });

  test('refuses a query it does not understand, with a 400', () {
    for (final sql in [
      'SELECT VALUE c.id FROM c',
      'SELECT * FROM c WHERE STARTSWITH(c.id, "a")',
      'SELECT * FROM c JOIN t IN c.tags',
      'SELECT * FROM c WHERE c.id IN ("a", "b")',
      'SELECT * FROM c GROUP BY c.uid',
      'DELETE FROM c',
    ]) {
      expect(
        () => CosmosQuery.parse(sql),
        throwsA(
          isA<CosmosException>().having((e) => e.statusCode, 'status', 400),
        ),
        reason: sql,
      );
    }
  });

  test('a parameter the query names but the call does not pass is a 400', () {
    expect(
      () => CosmosQuery.run('SELECT * FROM c WHERE c.uid = @uid', _docs),
      throwsA(isA<CosmosException>()),
    );
  });

  test('filters on equality, AND and parameters', () {
    expect(
      _ids(
        CosmosQuery.run(
          'SELECT * FROM c WHERE c.uid = @uid AND c.parentId = @p',
          _docs,
          {'@uid': 'u1', '@p': 'a'},
        ),
      ),
      ['b'],
    );
  });

  test('a missing field is undefined, not null', () {
    // `c.parentId = null` matches only a field that is there and null.
    expect(
      _ids(CosmosQuery.run('SELECT * FROM c WHERE c.parentId = null', _docs)),
      ['a'],
    );
    expect(
      _ids(
        CosmosQuery.run(
          'SELECT * FROM c WHERE NOT IS_DEFINED(c.parentId) '
          'OR IS_NULL(c.parentId)',
          _docs,
        ),
      ),
      ['a', 'c', 'd'],
    );
    // NOT of undefined stays undefined: the row is not kept.
    expect(
      _ids(CosmosQuery.run('SELECT * FROM c WHERE NOT (c.title = "A")', _docs)),
      ['a'],
    );
  });

  test('the signal-event filters of turn_history', () {
    expect(
      _ids(
        CosmosQuery.run(
          'SELECT * FROM c WHERE c.uid = @uid '
          'AND (NOT IS_DEFINED(c.acknowledgedAt) OR IS_NULL(c.acknowledgedAt)) '
          'AND IS_DEFINED(c.signalEvents) '
          'AND ARRAY_LENGTH(c.signalEvents) > 0',
          _docs,
          {'@uid': 'u1'},
        ),
      ),
      ['b'],
    );
  });

  test('range comparisons on strings and numbers; mixed types never match', () {
    final rows = [
      {'id': '1', 'at': '2026-01-01T00:00:00Z'},
      {'id': '2', 'at': '2026-02-01T00:00:00Z'},
      {'id': '3', 'at': 5},
    ];
    expect(
      _ids(
        CosmosQuery.run('SELECT * FROM c WHERE c.at >= @from', rows, {
          '@from': '2026-01-15T00:00:00Z',
        }),
      ),
      ['2'],
    );
    expect(_ids(CosmosQuery.run('SELECT * FROM c WHERE c.at < 10', rows)), [
      '3',
    ]);
  });

  test('ORDER BY, DESC, TOP and the next-order projection', () {
    expect(
      _ids(CosmosQuery.run('SELECT * FROM c ORDER BY c["order"]', _docs)),
      // A doc without the field sorts first, as in Cosmos.
      ['d', 'b', 'a', 'c'],
    );
    expect(
      _ids(CosmosQuery.run('SELECT * FROM c ORDER BY c.title DESC', _docs)),
      ['a', 'b', 'c', 'd'],
    );
    expect(
      CosmosQuery.run(
        'SELECT TOP 1 c["order"] AS o FROM c '
        'WHERE NOT IS_DEFINED(c.parentId) OR IS_NULL(c.parentId) '
        'ORDER BY c["order"] DESC',
        _docs,
      ),
      [
        {'o': 3},
      ],
    );
  });

  test('a projection leaves out fields a doc does not have', () {
    expect(CosmosQuery.run('SELECT c.id, c.title FROM c', _docs), [
      {'id': 'a', 'title': 'B'},
      {'id': 'b', 'title': 'A'},
      {'id': 'c'},
      {'id': 'd'},
    ]);
  });

  test('hands out copies, never the docs themselves', () {
    final rows = CosmosQuery.run('SELECT * FROM c', _docs);
    (rows[1]['signalEvents'] as List).add('changed');
    expect(_docs[1]['signalEvents'], ['x']);
  });
}
