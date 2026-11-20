// #323 — the reference panel searches and shows the bundled reference. These
// pin what it reads from the file: how an item is written (`plt.plot(...)`
// for a module the course imports under another name, `.append(x)` for a
// method), the texts in the app language with Dutch as the fallback, and the
// search: names first, then a word of the explanation, for a student who no
// longer knows the name. And the bundled file itself: every item has its
// texts in both languages and an example (tooling/site/curriculum.py
// --check-reference checks it against the lessons; this keeps the app from
// shipping a half-written item).

import 'dart:io';

import 'package:ai_tutor_python/services/code/python_reference.dart';
import 'package:flutter_test/flutter_test.dart';

final _reference = PythonReference.parse(
  File(PythonReference.assetKey).readAsStringSync(),
);

String _written(String groupId, String name) {
  final group = _reference.group(groupId)!;
  return group.item(name)!.writtenIn(group);
}

List<String> _found(String query, [String language = 'en']) => [
  for (final hit in _reference.search(query, language))
    '${hit.group.id}.${hit.item.name}',
];

void main() {
  group('how an item is written', () {
    test('a module imported under another name, by that name', () {
      expect(
        _written('matplotlib.pyplot', 'plot'),
        'plt.plot(x, y, label=..., color=...)',
      );
      expect(_written('numpy', 'linspace'), 'np.linspace(start, stop, num)');
      expect(_reference.group('numpy')!.prefix, 'np');
    });

    test('a module imported by its own name, by that name', () {
      expect(_written('random', 'randint'), 'random.randint(a, b)');
      expect(_written('math', 'pi'), 'math.pi');
      expect(_written('turtle', 'Turtle'), 'turtle.Turtle()');
    });

    test('a method after a dot, a built-in as it is', () {
      expect(_written('list', 'append'), '.append(x)');
      expect(_written('turtle.Turtle', 'forward'), '.forward(distance)');
      expect(_written('builtins', 'len'), 'len(s)');
      expect(_reference.group('list')!.prefix, isNull);
    });
  });

  group('texts in the app language', () {
    test('Dutch and English, with Dutch as the fallback', () {
      final sqrt = _reference.group('math')!.item('sqrt')!;
      expect(sqrt.summaryIn('nl'), 'De vierkantswortel √x.');
      expect(sqrt.summaryIn('en'), 'The square root √x.');
      expect(sqrt.summaryIn('fr'), 'De vierkantswortel √x.');
      expect(_reference.group('list')!.titleIn('en'), 'Lists (list)');
      expect(_reference.group('list')!.titleIn('nl'), 'Lijsten (list)');
    });

    test('every item of the bundled file has both summaries and an example, '
        'and every group both titles', () {
      for (final group in _reference.groups) {
        for (final language in ['nl', 'en']) {
          expect(group.title[language], isNotEmpty, reason: group.id);
        }
        for (final item in group.items) {
          final where = '${group.id}.${item.name}';
          expect(item.summary['nl'], isNotEmpty, reason: where);
          expect(item.summary['en'], isNotEmpty, reason: where);
          expect(item.example, isNotEmpty, reason: where);
        }
      }
    });

    test('a module group says how the course imports it', () {
      expect(
        _reference.group('matplotlib.pyplot')!.setup,
        'import matplotlib.pyplot as plt',
      );
      expect(
        _reference.group('turtle.Turtle')!.setup,
        'import turtle\nt = turtle.Turtle()',
      );
      expect(_reference.group('builtins')!.setup, isNull);
    });
  });

  group('search', () {
    test('a name that starts with the query comes before one that contains '
        'it, and case does not matter', () {
      expect(_found('Rand'), [
        'random.randint',
        'random.random',
        // `random.` in how they are written.
        'random.uniform',
        'random.choice',
      ]);
      expect(_found('sin').take(2), ['math.sin', 'numpy.sin']);
    });

    test('the name as it is written finds it too', () {
      expect(_found('plt.sh'), ['matplotlib.pyplot.show']);
      expect(_found('np.pi'), ['numpy.pi']);
    });

    test('a word of the explanation, in the app language', () {
      expect(_found('wortel', 'nl'), ['math.sqrt', 'numpy.sqrt']);
      expect(_found('square root'), ['math.sqrt', 'numpy.sqrt']);
      expect(_found('wortel', 'en'), isEmpty);
    });

    test('nothing for an empty query or one that matches nothing', () {
      expect(_found('  '), isEmpty);
      expect(_found('zzz'), isEmpty);
    });
  });
}
