// #322 — after a dot the editor's dropdown offered every word in the buffer
// and every keyword starting with what was typed, whatever stood before the
// dot. These pin the light type reading behind the new dropdown: the members
// of the receiver's type or module from the bundled reference, and nothing
// when the type is unknown.

import 'dart:io';

import 'package:ai_tutor_python/services/code/python_completion.dart';
import 'package:ai_tutor_python/services/code/python_reference.dart';
import 'package:flutter_test/flutter_test.dart';

final _reference = PythonReference.parse(
  File(PythonReference.assetKey).readAsStringSync(),
);

/// The names the dropdown offers for [code], where `|` marks the caret;
/// null when the caret is not after a dot in code.
List<String>? _offered(String code) {
  final cursor = code.indexOf('|');
  final text = code.replaceFirst('|', '');
  return memberSuggestions(
    _reference,
    text,
    cursor,
  )?.map((i) => i.name).toList();
}

const _turtle = [
  'backward',
  'forward',
  'left',
  'pencolor',
  'pendown',
  'penup',
  'right',
];
const _list = ['append', 'insert', 'pop', 'remove', 'sort'];
const _dict = ['get', 'items', 'keys', 'pop', 'values'];
const _str = [
  'count',
  'endswith',
  'find',
  'isdigit',
  'join',
  'lower',
  'replace',
  'split',
  'startswith',
  'strip',
  'upper',
];

void main() {
  group('a known type offers its members', () {
    test('a turtle made from the module', () {
      expect(_offered('import turtle\nt = turtle.Turtle()\nt.|'), _turtle);
    });

    test('a turtle made from an imported class', () {
      expect(_offered('from turtle import Turtle\nt = Turtle()\nt.|'), _turtle);
      expect(_offered('from turtle import *\nt = Turtle()\nt.|'), _turtle);
    });

    test('a list', () {
      expect(_offered('getallen = [3, 1, 2]\ngetallen.|'), _list);
      expect(_offered('leeg = []\nleeg.|'), _list);
      expect(
        _offered('kwadraten = [x * x for x in range(5)]\nk = kwadraten\nk.|'),
        _list,
      );
      expect(_offered('nullen = [0] * 10\nnullen.|'), _list);
      expect(_offered('[1, 2].|'), _list);
    });

    test('a string', () {
      expect(_offered('naam = input("Naam? ")\nnaam.|'), _str);
      expect(_offered("tekst = 'hallo'\ntekst.|"), _str);
      expect(_offered('zin = f"{a} en {b}"\nzin.|'), _str);
      expect(_offered('groet = "Hallo " + naam + "!"\ngroet.|'), _str);
      expect(_offered('lijn = "-" * 20\nlijn.|'), _str);
      expect(_offered('", ".|'), _str);
    });

    test('a dictionary', () {
      expect(_offered('punten = {}\npunten.|'), _dict);
      expect(_offered('punten = {"An": 7, "Bo": 9}\npunten.|'), _dict);
    });

    test('through a chain of calls the reference describes', () {
      expect(
        _offered('zin = input()\nwoorden = zin.split()\nwoorden.|'),
        _list,
      );
      expect(_offered('naam = input()\nnaam.strip().|'), _str);
      expect(_offered('import turtle\nturtle.Turtle().|'), _turtle);
      expect(_offered('x = sorted(getallen)\nx.|'), _list);
      expect(_offered('x = str(5)\nx.|'), _str);
    });

    test('inside brackets and calls on the same line', () {
      expect(
        _offered('t = turtle.Turtle()\nprint(t.|)'),
        isEmpty,
        reason: 'no import: turtle is unknown',
      );
      expect(
        _offered('import turtle\nt = turtle.Turtle()\nprint(t.|)'),
        _turtle,
      );
    });
  });

  group('a module offers what it has', () {
    test('turtle, math and random after their import', () {
      expect(_offered('import turtle\nturtle.|'), ['done', 'Turtle']);
      expect(_offered('import math\nmath.|'), ['cos', 'pi', 'sin', 'sqrt']);
      expect(_offered('import random\nrandom.|'), [
        'choice',
        'randint',
        'random',
        'uniform',
      ]);
    });

    test('matplotlib.pyplot under its alias and its full name', () {
      final pyplot = _offered('import matplotlib.pyplot as plt\nplt.|');
      expect(pyplot, containsAll(['plot', 'show', 'xlabel', 'legend']));
      expect(_offered('import matplotlib.pyplot\nmatplotlib.pyplot.|'), pyplot);
      expect(_offered('from matplotlib import pyplot as plt\nplt.|'), pyplot);
    });

    test('numpy under its alias', () {
      expect(
        _offered('import numpy as np\nnp.|'),
        containsAll(['array', 'linspace', 'pi']),
      );
    });
  });

  group('what was typed after the dot narrows the list', () {
    test('by the start of the name, ignoring case', () {
      const code = 'import turtle\nt = turtle.Turtle()\n';
      expect(_offered('${code}t.pe|'), ['pencolor', 'pendown', 'penup']);
      expect(_offered('${code}t.F|'), ['forward']);
      expect(_offered('${code}t.x|'), isEmpty);
    });

    test('a name written out in full is not offered again', () {
      const code = 'import turtle\nt = turtle.Turtle()\n';
      expect(_offered('${code}t.left|'), isEmpty);
      expect(_offered('${code}t.fo|rward'), isEmpty);
    });
  });

  group('an unknown type offers nothing', () {
    test('a name nothing binds', () {
      expect(_offered('onbekend.|'), isEmpty);
    });

    test('a module that is not imported', () {
      expect(_offered('turtle.|'), isEmpty);
      expect(_offered('math.|'), isEmpty);
    });

    test('a value the reference has no methods for', () {
      expect(_offered('getal = 5\ngetal.|'), isEmpty);
      expect(_offered('x = 3.|'), isEmpty);
      expect(_offered('x = len(lijst)\nx.|'), isEmpty);
      expect(_offered('s = {1, 2}\ns.|'), isEmpty);
      expect(_offered('p = (1, 2)\np.|'), isEmpty);
      expect(
        _offered('import numpy as np\nx = np.linspace(0, 1, 5)\nx.|'),
        isEmpty,
      );
    });

    test('an element, a loop variable, an unpacked name, a parameter', () {
      expect(_offered('woorden = ["a"]\nwoorden[0].|'), isEmpty);
      expect(_offered('for w in ["a", "b"]:\n    w.|'), isEmpty);
      expect(_offered('a, b = "x", "y"\na.|'), isEmpty);
      expect(
        _offered(
          'import turtle\nt = turtle.Turtle()\ndef vierkant(t):\n    t.|',
        ),
        isEmpty,
        reason: 'the parameter t is not the module-level turtle',
      );
    });

    test('a call the reference says nothing about', () {
      expect(_offered('import random\nx = random.choice(namen)\nx.|'), isEmpty);
      expect(_offered('x = maak()\nx.|'), isEmpty);
      expect(_offered('x = "a" if ok else []\nx.|'), isEmpty);
    });
  });

  group('which binding counts', () {
    test('the last assignment before the caret', () {
      expect(_offered('x = []\nx = "a"\nx.|'), _str);
      expect(_offered('x = "a"\nx = []\nx.|'), _list);
      expect(_offered('x = []\nx.|\nx = "a"'), _list);
      expect(_offered('x = []\nx = x.|'), _list);
    });

    test('a global in a function: the module binds it one way', () {
      expect(
        _offered(
          'import turtle\nt = turtle.Turtle()\ndef vierkant():\n    t.|',
        ),
        _turtle,
      );
      expect(
        _offered(
          'import turtle\ndef vierkant():\n    t.|\nt = turtle.Turtle()',
        ),
        _turtle,
        reason: 'the function runs after the module bound t',
      );
      expect(
        _offered(
          'import turtle\nt = turtle.Turtle()\ndef f():\n    t.|\nt = []',
        ),
        isEmpty,
        reason: 'two different module bindings: unknown',
      );
    });

    test('a local assignment in a function', () {
      expect(_offered('def f():\n    x = []\n    x.|'), _list);
      expect(_offered('x = "a"\ndef f():\n    x = []\n    x.|'), _list);
      expect(
        _offered('def f():\n    x = []\n\nx = "a"\nx.|'),
        _str,
        reason: 'back at module level the function body does not count',
      );
    });

    test('statements over several lines and after a semicolon', () {
      expect(_offered('x = [\n    1,\n    2,\n]\nx.|'), _list);
      expect(_offered('x = 1; y = []\ny.|'), _list);
    });
  });

  group('not after a dot in code: the editor keeps its own words', () {
    test('no dot', () {
      expect(_offered('pri|'), isNull);
      expect(_offered('t = 1\nt|'), isNull);
    });

    test('a dot inside a string or a comment', () {
      expect(_offered('print("Hallo. Wie|")'), isNull);
      expect(_offered('print("t.|")'), isNull);
      expect(_offered('# t.|'), isNull);
      expect(_offered('x = 1  # zie lijst.|'), isNull);
    });
  });

  group('the bundled reference', () {
    test('group ids are unique and items have a signature with their name', () {
      final ids = _reference.groups.map((g) => g.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final g in _reference.groups) {
        expect(g.title.keys, containsAll(['nl', 'en']), reason: g.id);
        final names = g.items.map((i) => i.name).toList();
        expect(names.toSet(), hasLength(names.length), reason: g.id);
        for (final i in g.items) {
          expect(i.signature, startsWith(i.name), reason: '${g.id}.${i.name}');
        }
      }
    });

    test('holds the groups the dropdown and the course need', () {
      expect(_reference.group('builtins')?.kind, ReferenceGroupKind.builtins);
      for (final type in ['str', 'list', 'dict', 'turtle.Turtle']) {
        expect(_reference.group(type)?.kind, ReferenceGroupKind.type);
      }
      for (final module in [
        'turtle',
        'math',
        'random',
        'matplotlib.pyplot',
        'numpy',
      ]) {
        expect(_reference.group(module)?.kind, ReferenceGroupKind.module);
      }
    });
  });
}
