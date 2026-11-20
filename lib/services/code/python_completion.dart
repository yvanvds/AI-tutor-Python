/// The editor's dropdown after a dot (#322): what a student can write after
/// `t.`, `lijst.`, `naam.` or `math.`, read from [PythonReference] — the
/// methods of the value's type, or what the module offers.
///
/// The type comes from a light reading of the code, not from running it: the
/// last assignment to the name before the caret (`x = []`, `naam = input()`,
/// `t = turtle.Turtle()`, `woorden = zin.split()`) and the imports (`import
/// matplotlib.pyplot as plt`, `from turtle import Turtle`). Whatever that
/// reading cannot settle — a function's parameter, a loop variable, an
/// element of a list, a value from a call the reference says nothing about —
/// is unknown, and an unknown type offers nothing: better no dropdown than a
/// wrong one.
library;

import 'package:ai_tutor_python/services/code/python_reference.dart';

/// Where the caret sits in `receiver.prefix`: the dot's offset and the part
/// of the member name typed so far.
class MemberAccess {
  const MemberAccess({
    required this.dot,
    required this.prefix,
    required this.wordEnd,
  });

  /// The offset of the dot in the text.
  final int dot;

  /// The identifier characters between the dot and the caret.
  final String prefix;

  /// Where the identifier the caret is in ends — past the caret when the
  /// student edits in the middle of a name.
  final int wordEnd;

  /// Where the member name starts: right after the dot.
  int get nameStart => dot + 1;
}

/// The member access the caret at [cursor] is in, or null when the caret is
/// not right after `something.` in code — no dot, or a dot inside a string
/// or a comment. A dot after a number (`3.`) still counts: it then offers
/// nothing.
MemberAccess? memberAccessAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  var start = cursor;
  while (start > 0 && _isIdentChar(text.codeUnitAt(start - 1))) {
    start--;
  }
  if (start == 0 || text[start - 1] != '.') return null;
  final dot = start - 1;
  if (!_isCode(text, dot)) return null;
  var end = cursor;
  while (end < text.length && _isIdentChar(text.codeUnitAt(end))) {
    end++;
  }
  return MemberAccess(
    dot: dot,
    prefix: text.substring(start, cursor),
    wordEnd: end,
  );
}

/// What the dropdown offers with the caret at [cursor]: null when the caret
/// is not after a dot in code (the editor's own suggestions apply), else the
/// members of the receiver's group whose name starts with what was typed
/// (ignoring case), sorted by name — empty when the receiver's type is
/// unknown or nothing matches. The member already written out in full is
/// left out, as the editor does for its own words.
List<ReferenceItem>? memberSuggestions(
  PythonReference reference,
  String text,
  int cursor,
) {
  final access = memberAccessAt(text, cursor);
  if (access == null) return null;
  final group = receiverGroup(reference, text, access.dot);
  if (group == null) return const [];
  final prefix = access.prefix.toLowerCase();
  final written = text.substring(access.nameStart, access.wordEnd);
  return group.items
      .where((i) => i.name.toLowerCase().startsWith(prefix))
      .where((i) => i.name != written)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// The group whose members may follow the dot at [dot]: a module group for
/// `math.`, a type group for `t.` when `t` holds a `turtle.Turtle` — or null
/// when the receiver's type is unknown.
ReferenceGroup? receiverGroup(PythonReference reference, String text, int dot) {
  final receiver = _receiverBefore(text, dot);
  if (receiver == null) return null;
  final program = _Program(reference, text);
  final at = program.statementAt(dot);
  final value = program.typeOf(receiver, at, program.scopeOf(at), 0);
  return switch (value) {
    _Module(:final path) => _groupOfKind(
      reference,
      path,
      ReferenceGroupKind.module,
    ),
    _Instance(:final type) => _groupOfKind(
      reference,
      type,
      ReferenceGroupKind.type,
    ),
    _ => null,
  };
}

ReferenceGroup? _groupOfKind(
  PythonReference reference,
  String id,
  ReferenceGroupKind kind,
) {
  final group = reference.group(id);
  return group?.kind == kind ? group : null;
}

// ---------------------------------------------------------------------------
// Characters and literals

bool _isIdentChar(int c) =>
    (c >= 0x61 && c <= 0x7a) || // a-z
    (c >= 0x41 && c <= 0x5a) || // A-Z
    (c >= 0x30 && c <= 0x39) || // 0-9
    c == 0x5f; // _

bool _isIdentStart(int c) => _isIdentChar(c) && !(c >= 0x30 && c <= 0x39);

bool _isQuote(String c) => c == '"' || c == "'";

final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// The end (exclusive) of the string literal whose opening quote is at [i].
/// An unclosed one-line string ends at the line break.
int _stringEnd(String text, int i) {
  final q = text[i];
  final triple = q * 3;
  if (text.startsWith(triple, i)) {
    var j = i + 3;
    while (j < text.length) {
      if (text[j] == r'\') {
        j += 2;
        continue;
      }
      if (text.startsWith(triple, j)) return j + 3;
      j++;
    }
    return text.length;
  }
  var j = i + 1;
  while (j < text.length) {
    final c = text[j];
    if (c == r'\') {
      j += 2;
      continue;
    }
    if (c == q) return j + 1;
    if (c == '\n') return j;
    j++;
  }
  return text.length;
}

/// Whether the character at [offset] is code — not inside a string literal
/// or a comment.
bool _isCode(String text, int offset) {
  var i = 0;
  while (i < offset) {
    final c = text[i];
    if (c == '#') {
      final eol = text.indexOf('\n', i);
      if (eol == -1 || eol >= offset) return false;
      i = eol;
    } else if (_isQuote(c)) {
      final end = _stringEnd(text, i);
      if (end > offset) return false;
      i = end;
    } else {
      i++;
    }
  }
  return true;
}

/// The expression right before the dot at [dot] — `t`, `turtle.Turtle()`,
/// `zin.strip()`, `"abc"`, `[1, 2]`, `lijst[0]` — or null when there is
/// none (a dot at the start of a line, after a space or an operator).
String? _receiverBefore(String text, int dot) {
  var i = dot;
  while (i > 0) {
    final c = text[i - 1];
    if (_isIdentChar(c.codeUnitAt(0))) {
      while (i > 0 && _isIdentChar(text.codeUnitAt(i - 1))) {
        i--;
      }
    } else if (c == ')' || c == ']') {
      final open = _openingBracket(text, i - 1);
      if (open == null) return null;
      i = open;
      // A call or an index continues the chain to its left; a bracket with
      // nothing before it is the whole receiver: `(a + b).`, `[1, 2].`.
      if (i > 0) {
        final before = text[i - 1];
        if (_isIdentChar(before.codeUnitAt(0)) ||
            before == ')' ||
            before == ']') {
          continue;
        }
      }
      break;
    } else if (_isQuote(c)) {
      final open = _openingQuote(text, i - 1);
      if (open == null) return null;
      i = open;
      // A prefix such as f"…" or r'…' belongs to the literal.
      while (i > 0 && 'fFrRbBuU'.contains(text[i - 1])) {
        i--;
      }
      break;
    } else {
      break;
    }
    if (i > 0 && text[i - 1] == '.') {
      i--;
      continue;
    }
    break;
  }
  if (i == dot) return null;
  return text.substring(i, dot);
}

/// The opening bracket that matches the closing one at [close], skipping
/// string literals; null when there is none.
int? _openingBracket(String text, int close) {
  var depth = 0;
  var i = close;
  while (i >= 0) {
    final c = text[i];
    if (_isQuote(c)) {
      final open = _openingQuote(text, i);
      if (open == null) return null;
      i = open - 1;
      continue;
    }
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      depth--;
      if (depth == 0) return i;
    }
    if (c == '\n' && depth == 0) return null;
    i--;
  }
  return null;
}

/// The opening quote of the string literal whose closing quote is at
/// [close]; null when there is none.
int? _openingQuote(String text, int close) {
  final q = text[close];
  final triple = q * 3;
  if (close >= 2 && text.substring(close - 2, close + 1) == triple) {
    final open = text.lastIndexOf(triple, close - 3);
    return open == -1 ? null : open;
  }
  var i = close - 1;
  while (i >= 0) {
    final c = text[i];
    if (c == '\n') return null;
    if (c == q && (i == 0 || text[i - 1] != r'\')) return i;
    i--;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Statements and scopes

/// One logical line of code: physical lines joined inside brackets and after
/// a backslash, comments dropped, split at `;`.
class _Statement {
  _Statement(this.start, this.end, this.indent, this.text);

  final int start;
  final int end;
  final int indent;
  final String text;
  late final _Scope scope;
  Map<String, _Binding>? _bindings;
}

/// A function (or class) body, or the module.
class _Scope {
  _Scope({this.parent, this.indent = -1, this.isClass = false, this.params});

  final _Scope? parent;

  /// The indentation of the `def` / `class` line; -1 for the module.
  final int indent;
  final bool isClass;

  /// A function's parameters; null for the module and a class.
  final Set<String>? params;

  bool get isModule => parent == null;
}

List<_Statement> _statements(String text) {
  final statements = <_Statement>[];
  final buf = StringBuffer();
  int? start;
  var indent = 0;
  int? forcedIndent;
  var lineStart = 0;
  var depth = 0;
  var i = 0;

  void flush(int end) {
    final s = buf.toString().trim();
    if (s.isNotEmpty && start != null) {
      statements.add(_Statement(start!, end, indent, s));
    }
    buf.clear();
    start = null;
  }

  void begin(int at) {
    if (start != null) return;
    start = at;
    indent = forcedIndent ?? at - lineStart;
  }

  while (i < text.length) {
    final c = text[i];
    if (c == '#') {
      while (i < text.length && text[i] != '\n') {
        i++;
      }
      continue;
    }
    if (_isQuote(c)) {
      begin(i);
      final end = _stringEnd(text, i);
      buf.write(text.substring(i, end).replaceAll('\n', ' '));
      i = end;
      continue;
    }
    if (c == r'\' && i + 1 < text.length && text[i + 1] == '\n') {
      buf.write(' ');
      i += 2;
      continue;
    }
    if (c == '\n') {
      if (depth > 0) {
        buf.write(' ');
      } else {
        flush(i);
        forcedIndent = null;
      }
      i++;
      lineStart = i;
      continue;
    }
    if (c == ';' && depth == 0) {
      flush(i);
      forcedIndent = indent;
      i++;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if ((c == ')' || c == ']' || c == '}') && depth > 0) depth--;
    if (c != ' ' && c != '\t' && c != '\r') begin(i);
    buf.write(c);
    i++;
  }
  flush(text.length);
  return statements;
}

final _defLine = RegExp(r'^(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\((.*)\)');
final _classLine = RegExp(r'^class\s+([A-Za-z_]\w*)');

/// The names a `def` line's parameter list binds: `t`, `lengte=10`,
/// `*args`, `x: int` all bind their name.
Set<String> _params(String list) => {
  for (final p in _splitTopLevel(list, ','))
    if (RegExp(r'^\**\s*([A-Za-z_]\w*)').firstMatch(p.trim())?.group(1)
        case final name?)
      name,
};

void _assignScopes(List<_Statement> statements, _Scope module) {
  final stack = [module];
  for (final s in statements) {
    while (stack.length > 1 && s.indent <= stack.last.indent) {
      stack.removeLast();
    }
    s.scope = stack.last;
    final def = _defLine.firstMatch(s.text);
    if (def != null) {
      stack.add(
        _Scope(
          parent: stack.last,
          indent: s.indent,
          params: _params(def.group(2)!),
        ),
      );
    } else if (_classLine.hasMatch(s.text)) {
      stack.add(_Scope(parent: stack.last, indent: s.indent, isClass: true));
    }
  }
}

// ---------------------------------------------------------------------------
// Values

/// What an expression evaluates to, as far as the reference knows.
sealed class _Value {
  const _Value();

  /// For comparing the candidates of a name bound in several places.
  String get key;
}

/// A module, or the package in front of one (`matplotlib` before
/// `.pyplot`).
class _Module extends _Value {
  const _Module(this.path);
  final String path;
  @override
  String get key => 'module:$path';
}

/// A value of a type: `str`, `list`, `turtle.Turtle`, …
class _Instance extends _Value {
  const _Instance(this.type);
  final String type;
  @override
  String get key => 'type:$type';
}

/// A function, method or class not called yet; calling it gives a value of
/// [returns], or something unknown when that is null.
class _Callable extends _Value {
  const _Callable(this.name, this.returns);
  final String name;
  final String? returns;
  @override
  String get key => 'callable:$name:$returns';
}

/// What a statement binds a name to: an expression evaluated where the
/// statement stands, or a value known outright (an import; null for a loop
/// variable, a parameter, a function name — bound, but to something
/// unknown).
sealed class _Binding {
  const _Binding();
}

class _Expression extends _Binding {
  const _Expression(this.source);
  final String source;
}

class _Known extends _Binding {
  const _Known(this.value);
  final _Value? value;
}

/// The result of looking a name up: [found] false when nothing binds it
/// (Python's builtins then apply), else its [value] — null when bound to
/// something unknown.
class _Lookup {
  const _Lookup.notFound() : found = false, value = null;
  const _Lookup.of(this.value) : found = true;
  final bool found;
  final _Value? value;
}

// ---------------------------------------------------------------------------
// The program

class _Program {
  _Program(this.reference, String text) : statements = _statements(text) {
    _assignScopes(statements, module);
  }

  final PythonReference reference;
  final List<_Statement> statements;
  final module = _Scope();

  static const _maxDepth = 12;

  /// The index of the statement [offset] is in (the caret's own, unfinished
  /// one); bindings count only from the statements before it.
  int statementAt(int offset) {
    for (var k = 0; k < statements.length; k++) {
      if (offset < statements[k].start) return k;
      if (offset <= statements[k].end) return k;
    }
    return statements.length;
  }

  _Scope scopeOf(int at) =>
      at < statements.length ? statements[at].scope : _scopeAtEnd();

  _Scope _scopeAtEnd() => statements.isEmpty ? module : statements.last.scope;

  // -- names --------------------------------------------------------------

  /// [name] as seen from statement [at] in [scope]: the last binding before
  /// [at] in the same scope; a function's parameter (unknown); else what
  /// the enclosing scopes bind it to anywhere — when they agree.
  _Lookup lookup(String name, int at, _Scope scope, int depth) {
    for (var k = at - 1; k >= 0; k--) {
      final s = statements[k];
      if (!identical(s.scope, scope)) continue;
      final binding = _bindingsOf(s)[name];
      if (binding != null) {
        return _Lookup.of(_evaluate(binding, k, s.scope, depth));
      }
    }
    if (scope.params?.contains(name) ?? false) return const _Lookup.of(null);
    var outer = scope.parent;
    while (outer != null && outer.isClass) {
      outer = outer.parent;
    }
    if (outer == null) return const _Lookup.notFound();
    return _lookupAnywhere(name, outer, at, depth);
  }

  /// [name] as a function body sees it in an enclosing [scope]: every
  /// binding there counts (the function runs after them), and they must
  /// agree. [at] is the caret's statement, never a binding.
  _Lookup _lookupAnywhere(String name, _Scope scope, int at, int depth) {
    _Value? agreed;
    var found = false;
    for (var k = 0; k < statements.length; k++) {
      if (k == at) continue;
      final s = statements[k];
      if (!identical(s.scope, scope)) continue;
      final binding = _bindingsOf(s)[name];
      if (binding == null) continue;
      final value = _evaluate(binding, k, s.scope, depth);
      if (value == null) return const _Lookup.of(null);
      if (found && agreed!.key != value.key) return const _Lookup.of(null);
      agreed = value;
      found = true;
    }
    if (found) return _Lookup.of(agreed);
    if (scope.params?.contains(name) ?? false) return const _Lookup.of(null);
    var outer = scope.parent;
    while (outer != null && outer.isClass) {
      outer = outer.parent;
    }
    if (outer == null) return const _Lookup.notFound();
    return _lookupAnywhere(name, outer, at, depth);
  }

  _Value? _evaluate(_Binding binding, int at, _Scope scope, int depth) =>
      switch (binding) {
        _Known(:final value) => value,
        _Expression(:final source) => typeOf(source, at, scope, depth + 1),
      };

  /// A name nothing in the program binds: a builtin function, or a type
  /// called to make a value (`str(5)`, `list()`).
  _Value? _builtin(String name) {
    final item = reference.builtins?.item(name);
    if (item != null) return _itemValue(item);
    final group = reference.group(name);
    if (group != null && group.kind == ReferenceGroupKind.type) {
      return _Callable(name, name);
    }
    return null;
  }

  _Value? _itemValue(ReferenceItem item) => item.kind.isCalled
      ? _Callable(item.name, item.returns)
      : (item.returns == null ? null : _Instance(item.returns!));

  // -- bindings -----------------------------------------------------------

  Map<String, _Binding> _bindingsOf(_Statement s) =>
      s._bindings ??= _parseBindings(s.text);

  Map<String, _Binding> _parseBindings(String t) {
    final bindings = <String, _Binding>{};
    void unknown(String name) => bindings[name] = const _Known(null);

    if (t.startsWith('import ')) {
      for (final part in _splitTopLevel(t.substring(7), ',')) {
        final m = RegExp(r'^([\w.]+)(?:\s+as\s+(\w+))?$')
            .firstMatch(part.trim());
        if (m == null) continue;
        final path = m.group(1)!;
        final alias = m.group(2);
        if (alias != null) {
          bindings[alias] = _Known(_Module(path));
        } else {
          final head = path.split('.').first;
          bindings[head] = _Known(_Module(head));
        }
      }
      return bindings;
    }

    final from = RegExp(r'^from\s+([\w.]+)\s+import\s+(.+)$').firstMatch(t);
    if (from != null) {
      final module = from.group(1)!;
      final names = from.group(2)!.replaceAll(RegExp(r'[()]'), '');
      for (final part in _splitTopLevel(names, ',')) {
        final p = part.trim();
        if (p == '*') {
          for (final item in reference.group(module)?.items ?? const []) {
            bindings[item.name] = _Known(_itemValue(item));
          }
          continue;
        }
        final m = RegExp(r'^(\w+)(?:\s+as\s+(\w+))?$').firstMatch(p);
        if (m == null) continue;
        final name = m.group(1)!;
        bindings[m.group(2) ?? name] = _Known(_imported(module, name));
      }
      return bindings;
    }

    final def = _defLine.firstMatch(t) ?? _classLine.firstMatch(t);
    if (def != null) {
      unknown(def.group(1)!);
      return bindings;
    }

    if (t.startsWith('for ')) {
      final targets = t.substring(4).split(RegExp(r'\s+in\s+')).first;
      for (final name in RegExp(r'[A-Za-z_]\w*').allMatches(targets)) {
        unknown(name.group(0)!);
      }
      return bindings;
    }

    if (t.startsWith('with ') || t.startsWith('except')) {
      for (final m in RegExp(r'\bas\s+([A-Za-z_]\w*)').allMatches(t)) {
        unknown(m.group(1)!);
      }
      return bindings;
    }

    final parts = _splitAssignment(t);
    if (parts.length < 2) return bindings;
    final source = parts.last;
    for (final rawTarget in parts.take(parts.length - 1)) {
      // `x: list = []` — the annotation is not part of the name.
      final target = _splitTopLevel(rawTarget, ':').first.trim();
      if (_identifier.hasMatch(target)) {
        bindings[target] = _Expression(source);
      } else if (_splitTopLevel(target, ',').length > 1 ||
          target.startsWith('(') ||
          target.startsWith('[')) {
        // Unpacking: each name gets one element of something unknown.
        for (final name in RegExp(r'[A-Za-z_]\w*').allMatches(target)) {
          unknown(name.group(0)!);
        }
      }
      // `lijst[0] = …` and `obj.x = …` bind no name.
    }
    return bindings;
  }

  /// What `from module import name` binds `name` to.
  _Value? _imported(String module, String name) {
    final item = reference.group(module)?.item(name);
    if (item != null) return _itemValue(item);
    final sub = '$module.$name';
    if (_isModulePath(sub)) return _Module(sub);
    return null;
  }

  /// Whether [path] is a module in the reference or a package in front of
  /// one.
  bool _isModulePath(String path) =>
      reference.modules.any((g) => g.id == path || g.id.startsWith('$path.'));

  // -- expressions --------------------------------------------------------

  /// The value of the expression [source], read at statement [at] in
  /// [scope]; null when unknown.
  _Value? typeOf(String source, int at, _Scope scope, int depth) {
    final e = source.trim();
    if (e.isEmpty || depth > _maxDepth) return null;

    if (_splitTopLevel(e, ',').length > 1) return null; // a tuple
    if (_wraps(e, '(', ')')) {
      return typeOf(e.substring(1, e.length - 1), at, scope, depth + 1);
    }

    // `"Hallo " + naam`, `[0] * 10`: a string or a list on either side
    // decides. Anything else with an operator is out of reach.
    final terms = _splitOperators(e);
    if (terms == null) return null;
    if (terms.length > 1) {
      final values = [for (final t in terms) typeOf(t, at, scope, depth + 1)];
      for (final type in const ['str', 'list']) {
        if (values.any((v) => v is _Instance && v.type == type)) {
          return _Instance(type);
        }
      }
      return null;
    }

    return _chain(e, at, scope, depth);
  }

  /// A primary expression: an atom followed by `.name`, `(…)` and `[…]`.
  _Value? _chain(String e, int at, _Scope scope, int depth) {
    _Value? value;
    var i = 0;
    final first = e.codeUnitAt(0);
    if (_isQuote(e[0]) || _stringPrefixAt(e) > 0) {
      final open = _stringPrefixAt(e);
      if (e.substring(0, open).toLowerCase().contains('b')) return null;
      i = _stringEnd(e, open);
      value = const _Instance('str');
    } else if (_isIdentStart(first)) {
      while (i < e.length && _isIdentChar(e.codeUnitAt(i))) {
        i++;
      }
      final name = e.substring(0, i);
      if (_keywords.contains(name)) return null;
      final found = lookup(name, at, scope, depth);
      value = found.found ? found.value : _builtin(name);
    } else if (e[0] == '[') {
      final close = _closingBracket(e, 0);
      if (close == null) return null;
      i = close + 1;
      value = const _Instance('list');
    } else if (e[0] == '{') {
      final close = _closingBracket(e, 0);
      if (close == null) return null;
      final inner = e.substring(1, close).trim();
      // `{}` and `{a: b}` are dicts; `{1, 2}` is a set.
      if (inner.isNotEmpty && _splitTopLevel(inner, ':').length < 2) {
        return null;
      }
      i = close + 1;
      value = const _Instance('dict');
    } else if (e[0] == '(') {
      final close = _closingBracket(e, 0);
      if (close == null) return null;
      value = typeOf(e.substring(1, close), at, scope, depth + 1);
      i = close + 1;
    } else {
      return null;
    }

    while (i < e.length) {
      if (value == null) return null;
      final c = e[i];
      if (c == ' ') {
        i++;
      } else if (c == '.') {
        var j = i + 1;
        while (j < e.length && _isIdentChar(e.codeUnitAt(j))) {
          j++;
        }
        if (j == i + 1) return null;
        value = _member(value, e.substring(i + 1, j));
        i = j;
      } else if (c == '(') {
        final close = _closingBracket(e, i);
        if (close == null) return null;
        value = value is _Callable && value.returns != null
            ? _Instance(value.returns!)
            : null;
        i = close + 1;
      } else {
        // An index, `lijst[0]`, gives an element of something: unknown.
        return null;
      }
    }
    return value;
  }

  _Value? _member(_Value value, String name) {
    switch (value) {
      case _Module(:final path):
        final group = reference.group(path);
        final item = group?.kind == ReferenceGroupKind.module
            ? group!.item(name)
            : null;
        if (item != null) return _itemValue(item);
        final sub = '$path.$name';
        return _isModulePath(sub) ? _Module(sub) : null;
      case _Instance(:final type):
        final group = reference.group(type);
        final item = group?.kind == ReferenceGroupKind.type
            ? group!.item(name)
            : null;
        return item == null ? null : _itemValue(item);
      case _Callable():
        return null;
    }
  }
}

const _keywords = {
  'and', 'or', 'not', 'in', 'is', 'if', 'else', 'for', 'lambda', 'None', //
  'True', 'False', 'await', 'yield', 'as', 'from',
};

/// The length of a string prefix (`f`, `rb`, …) right before an opening
/// quote at the start of [e]; 0 when [e] does not start with one.
int _stringPrefixAt(String e) {
  var i = 0;
  while (i < e.length && i < 2 && 'fFrRbBuU'.contains(e[i])) {
    i++;
  }
  return i < e.length && _isQuote(e[i]) ? i : 0;
}

/// Whether [e] is one bracket pair from its first to its last character.
bool _wraps(String e, String open, String close) =>
    e.startsWith(open) && _closingBracket(e, 0) == e.length - 1;

/// The closing bracket matching the opening one at [open], skipping string
/// literals.
int? _closingBracket(String e, int open) {
  var depth = 0;
  var i = open;
  while (i < e.length) {
    final c = e[i];
    if (_isQuote(c)) {
      i = _stringEnd(e, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return null;
}

/// [e] split at [separator] outside brackets and strings.
List<String> _splitTopLevel(String e, String separator) {
  final parts = <String>[];
  var depth = 0;
  var from = 0;
  var i = 0;
  while (i < e.length) {
    final c = e[i];
    if (_isQuote(c)) {
      i = _stringEnd(e, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if ((c == ')' || c == ']' || c == '}') && depth > 0) depth--;
    if (depth == 0 && c == separator) {
      parts.add(e.substring(from, i));
      from = i + 1;
    }
    i++;
  }
  parts.add(e.substring(from));
  return parts;
}

/// A statement split at its assignment `=` signs — `a = b = []` gives
/// `a`, `b`, `[]` — and a single part when it assigns nothing (`==`, `+=`,
/// `<=` and `=` inside brackets do not count).
List<String> _splitAssignment(String t) {
  final parts = <String>[];
  var depth = 0;
  var from = 0;
  var i = 0;
  while (i < t.length) {
    final c = t[i];
    if (_isQuote(c)) {
      i = _stringEnd(t, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if ((c == ')' || c == ']' || c == '}') && depth > 0) depth--;
    if (depth == 0 && c == '=') {
      final before = i > 0 ? t[i - 1] : '';
      final after = i + 1 < t.length ? t[i + 1] : '';
      if (after == '=') {
        i += 2;
        continue;
      }
      if (!'+-*/%&|^<>!=:@'.contains(before) || before.isEmpty) {
        parts.add(t.substring(from, i));
        from = i + 1;
      }
    }
    i++;
  }
  parts.add(t.substring(from));
  return parts;
}

/// [e] split at its top-level `+` and `*` (not `**`), or null when [e]
/// holds any other operator or a keyword such as `if`, `and`, `in` at the
/// top level — an expression this reading does not follow.
List<String>? _splitOperators(String e) {
  final terms = <String>[];
  var depth = 0;
  var from = 0;
  var i = 0;
  while (i < e.length) {
    final c = e[i];
    if (_isQuote(c)) {
      i = _stringEnd(e, i);
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if ((c == ')' || c == ']' || c == '}') && depth > 0) depth--;
    if (depth == 0) {
      if ('-/%<>=!&|^~@'.contains(c)) return null;
      if (c == '*' && i + 1 < e.length && e[i + 1] == '*') return null;
      if (c == '+' || c == '*') {
        terms.add(e.substring(from, i));
        from = i + 1;
      } else if (_isIdentStart(c.codeUnitAt(0)) &&
          (i == 0 || !_isIdentChar(e.codeUnitAt(i - 1)))) {
        var j = i;
        while (j < e.length && _isIdentChar(e.codeUnitAt(j))) {
          j++;
        }
        final word = e.substring(i, j);
        // A keyword at the top level makes a condition, a test or a lambda —
        // unless it is the receiver of a chain (`None` is still a keyword).
        if (_keywords.contains(word) && word != 'None') return null;
        i = j;
        continue;
      }
    }
    i++;
  }
  terms.add(e.substring(from));
  if (terms.any((t) => t.trim().isEmpty)) return null;
  return terms;
}
