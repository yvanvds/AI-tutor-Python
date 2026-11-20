import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The functions, methods and classes the course uses, by group (#322): the
/// one source behind the editor's dropdown after a dot and the reference
/// panel (#323). It lives in [PythonReference.assetKey], a JSON file in the
/// repository that ships with the app and that `tooling/site/curriculum.py`
/// can read as well.
///
/// The file:
///
/// ```json
/// {
///   "version": 1,
///   "groups": [
///     {
///       "id": "turtle.Turtle",          // unique; see ReferenceGroupKind
///       "kind": "type",                 // builtins | type | module
///       "title": {"nl": "...", "en": "..."},
///       "setup": "import turtle\nt = turtle.Turtle()", // optional (#323)
///       "items": [
///         {
///           "name": "forward",          // what is typed after the dot
///           "kind": "method",           // function | method | class | constant
///           "signature": "forward(distance)",
///           "returns": "turtle.Turtle", // optional, see ReferenceItem.returns
///           "summary": {"nl": "...", "en": "..."}, // optional (#323)
///           "example": "t.forward(100)",           // optional (#323)
///           "lesson": "<subgoal id>"                // optional (#323)
///         }
///       ]
///     }
///   ]
/// }
/// ```
///
/// A signature keeps Python's own name for every parameter a student writes
/// as a keyword (`sep=`, `end=`, `label=`, `bins=`, `reverse=`); the names
/// of the other parameters only describe them.
///
/// The reference panel (#323) shows every group and item, in the app
/// language, and `tooling/site/curriculum.py` writes the same list on the
/// site; `curriculum.py --check-reference` reports what a live lesson uses
/// that is missing here.
@immutable
class PythonReference {
  const PythonReference(this.groups);

  /// The bundled file. Declared under `assets:` in `pubspec.yaml`.
  static const assetKey = 'assets/reference/python_reference.json';

  /// No groups: the editor then never offers anything after a dot.
  static const empty = PythonReference([]);

  final List<ReferenceGroup> groups;

  factory PythonReference.fromJson(Map<String, dynamic> json) {
    final groups = (json['groups'] as List<dynamic>? ?? const [])
        .map((g) => ReferenceGroup.fromJson(g as Map<String, dynamic>))
        .toList(growable: false);
    return PythonReference(groups);
  }

  factory PythonReference.parse(String source) =>
      PythonReference.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// The group with [id] (a module path such as `matplotlib.pyplot`, a type
  /// such as `list` or `turtle.Turtle`, or `builtins`), or null.
  ReferenceGroup? group(String? id) {
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// The module groups, for the names an `import` can bind.
  Iterable<ReferenceGroup> get modules =>
      groups.where((g) => g.kind == ReferenceGroupKind.module);

  /// The functions callable by their bare name (`input`, `sorted`, …).
  ReferenceGroup? get builtins => group('builtins');

  /// The items a search for [query] finds (#323), best first: a name that
  /// starts with it, then a name — or the name as it is written, such as
  /// `plt.plot(x, y, ...)` — that contains it, then a summary in [language]
  /// that does. Case is ignored; equal hits keep the file's order. An empty
  /// [query] finds nothing: the panel then shows the groups.
  List<ReferenceHit> search(String query, String language) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final ranked = <(int, ReferenceHit)>[];
    for (final group in groups) {
      for (final item in group.items) {
        final name = item.name.toLowerCase();
        final int rank;
        if (name.startsWith(q)) {
          rank = 0;
        } else if (name.contains(q) ||
            item.writtenIn(group).toLowerCase().contains(q)) {
          rank = 1;
        } else if (item.summaryIn(language).toLowerCase().contains(q)) {
          rank = 2;
        } else {
          continue;
        }
        ranked.add((rank, ReferenceHit(group, item)));
      }
    }
    // A stable sort: `List.sort` is not.
    return [
      for (var rank = 0; rank <= 2; rank++)
        for (final (r, hit) in ranked)
          if (r == rank) hit,
    ];
  }

  static PythonReference? _loaded;

  /// The bundled reference, once it has been read; null before that.
  static PythonReference? get loaded => _loaded;

  /// Reads the bundled reference once per process. The parsed value is the
  /// cache, not the future: a future cached by the first widget test's
  /// fake-async zone never completes for the next test (see the note on
  /// `puntenformuleFragmentProvider`). A missing or broken file gives
  /// [empty] — no dropdown after a dot, never a wrong one.
  static Future<PythonReference> load() async {
    final cached = _loaded;
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(assetKey);
      return _loaded = PythonReference.parse(
        utf8.decode(Uint8List.sublistView(data)),
      );
    } catch (e) {
      debugPrint('python reference: could not read $assetKey: $e');
      return _loaded = empty;
    }
  }
}

/// What a group's items belong to.
enum ReferenceGroupKind {
  /// Functions called by their bare name: `print(...)`, `input(...)`.
  builtins,

  /// The methods of a value of one type, after `value.`: `str`, `list`,
  /// `dict`, `turtle.Turtle`. The id is the type, with its module in front
  /// when it has one.
  type,

  /// What a module offers after `module.`. The id is what follows `import`:
  /// `turtle`, `math`, `matplotlib.pyplot`.
  module,
}

@immutable
class ReferenceGroup {
  const ReferenceGroup({
    required this.id,
    required this.kind,
    required this.title,
    required this.items,
    this.setup,
  });

  final String id;
  final ReferenceGroupKind kind;

  /// The group's heading per language code (`nl`, `en`).
  final Map<String, String> title;
  final List<ReferenceItem> items;

  /// The code the examples of this group take for granted (#323): the
  /// import of a module, as the course writes it (`import numpy as np`),
  /// or a turtle to give commands to. Null when the examples need none.
  final String? setup;

  factory ReferenceGroup.fromJson(Map<String, dynamic> json) => ReferenceGroup(
    id: json['id'] as String,
    kind: ReferenceGroupKind.values.byName(json['kind'] as String),
    title: _texts(json['title']),
    items: (json['items'] as List<dynamic>? ?? const [])
        .map((i) => ReferenceItem.fromJson(i as Map<String, dynamic>))
        .toList(growable: false),
    setup: json['setup'] as String?,
  );

  /// The heading in [language], else the Dutch one.
  String titleIn(String language) => _textIn(title, language) ?? id;

  /// What a module's items are written after: the name [setup] imports the
  /// module as (`plt` for `import matplotlib.pyplot as plt`), else its id.
  /// Null for the other groups.
  String? get prefix {
    if (kind != ReferenceGroupKind.module) return null;
    final alias = RegExp(
      '^import ${RegExp.escape(id)} as (\\w+)\$',
      multiLine: true,
    ).firstMatch(setup ?? '');
    return alias?.group(1) ?? id;
  }

  /// The item called [name], or null.
  ReferenceItem? item(String name) {
    for (final i in items) {
      if (i.name == name) return i;
    }
    return null;
  }
}

/// What an item is, which decides what writing it gives.
enum ReferenceItemKind {
  /// Called by name: `print(...)`, `math.sqrt(...)`.
  function,

  /// Called on a value: `lijst.append(...)`.
  method,

  /// Called to make a value of a type: `turtle.Turtle()`.
  class_,

  /// A value, used without a call: `math.pi`.
  constant;

  static ReferenceItemKind parse(String raw) =>
      raw == 'class' ? class_ : ReferenceItemKind.values.byName(raw);

  bool get isCalled => this != constant;
}

@immutable
class ReferenceItem {
  const ReferenceItem({
    required this.name,
    required this.kind,
    required this.signature,
    this.returns,
    this.summary = const {},
    this.example,
    this.lesson,
  });

  final String name;
  final ReferenceItemKind kind;

  /// How it is written, parameters included: `forward(distance)`, `pi`.
  final String signature;

  /// The type of what the item gives — the call's result for a function,
  /// method or class, the value itself for a constant — or null when that
  /// depends on the arguments or is nothing worth naming. When it is the id
  /// of a type group (`str`, `list`, `turtle.Turtle`), the editor follows it:
  /// `t = turtle.Turtle()` makes `t.` offer the turtle's methods.
  final String? returns;

  /// One or two sentences per language code (#323). Empty until written.
  final Map<String, String> summary;

  /// A short example (#323), or null.
  final String? example;

  /// The id of the subgoal whose lesson explains this item (#323), or null.
  final String? lesson;

  /// The summary in [language], else the Dutch one; empty when unwritten.
  String summaryIn(String language) => _textIn(summary, language) ?? '';

  /// How the item is written in code (#323): `random.randint(a, b)` and
  /// `plt.plot(...)` for a module's, `.append(x)` for a method, `print(...)`
  /// for a built-in.
  String writtenIn(ReferenceGroup group) => switch (group.kind) {
    ReferenceGroupKind.module => '${group.prefix}.$signature',
    ReferenceGroupKind.type => '.$signature',
    ReferenceGroupKind.builtins => signature,
  };

  factory ReferenceItem.fromJson(Map<String, dynamic> json) => ReferenceItem(
    name: json['name'] as String,
    kind: ReferenceItemKind.parse(json['kind'] as String),
    signature: json['signature'] as String? ?? json['name'] as String,
    returns: json['returns'] as String?,
    summary: _texts(json['summary']),
    example: json['example'] as String?,
    lesson: json['lesson'] as String?,
  );
}

/// An item a search found, with the group it belongs to.
@immutable
class ReferenceHit {
  const ReferenceHit(this.group, this.item);

  final ReferenceGroup group;
  final ReferenceItem item;
}

String? _textIn(Map<String, String> texts, String language) {
  final text = texts[language] ?? texts['nl'];
  return text == null || text.isEmpty ? null : text;
}

Map<String, String> _texts(Object? raw) => raw is Map
    ? {for (final e in raw.entries) e.key as String: e.value as String}
    : const {};
