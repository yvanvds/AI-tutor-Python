// The SQL the app sends to Cosmos, run against documents in memory (#263).
//
// Two users: the local storage of the stand-alone mode
// (`LocalCosmosClient`) and the in-memory fake of the tests
// (`test/helpers/in_memory_cosmos.dart`). Both run the same code, so a query
// that works in the tests works on the pc.
//
// It understands the subset the services use, and nothing more:
//
//   SELECT [TOP n] * | c.a [AS x], c["b"], ... FROM c
//   [WHERE <condition>]
//   [ORDER BY c.a [ASC|DESC], ...]
//
// with conditions built from `=`, `!=`, `<>`, `<`, `<=`, `>`, `>=`, `AND`,
// `OR`, `NOT`, parentheses, `IS_DEFINED`, `IS_NULL` and `ARRAY_LENGTH`, over
// paths into the document, `@parameters` and literals.
//
// A query it does not understand fails with a 400, as Cosmos fails on a
// syntax error. An empty result would hide the gap until someone wonders
// where their data went.
//
// Semantics follow Cosmos where the app could notice:
//
//   - a missing field is *undefined*, not null; comparing with undefined, or
//     comparing values of different types, is undefined, and a row is kept
//     only when its condition is `true`;
//   - ORDER BY sorts undefined < null < booleans < numbers < strings, and
//     keeps rows that lack the field;
//   - a projection leaves out the fields a document does not have.

import 'dart:convert';

import 'package:ai_tutor_python/core/cosmos_client.dart';

/// A parsed query. Parse once with [CosmosQuery.parse], run many times.
class CosmosQuery {
  CosmosQuery._(
    this.sql,
    this._top,
    this._projection,
    this._where,
    this._order,
  );

  /// Parses [sql], or throws a [CosmosException] with status 400 when it is
  /// not part of the subset this interpreter understands.
  factory CosmosQuery.parse(String sql) {
    final cached = _cache[sql];
    if (cached != null) return cached;
    final parsed = _Parser(sql).parse();
    if (_cache.length > 500) _cache.clear();
    return _cache[sql] = parsed;
  }

  static final Map<String, CosmosQuery> _cache = {};

  /// Runs [sql] over [docs] with [parameters] (keys with their `@`).
  static List<Map<String, dynamic>> run(
    String sql,
    Iterable<Map<String, dynamic>> docs, [
    Map<String, Object?> parameters = const {},
  ]) => CosmosQuery.parse(sql).execute(docs, parameters);

  final String sql;
  final int? _top;

  /// `null` for `SELECT *`.
  final List<_Projection>? _projection;
  final _Expr? _where;
  final List<_OrderBy> _order;

  /// The rows of [docs] this query selects, in its order, projected. The
  /// rows are copies: changing them changes no document.
  List<Map<String, dynamic>> execute(
    Iterable<Map<String, dynamic>> docs, [
    Map<String, Object?> parameters = const {},
  ]) {
    final where = _where;
    final rows = <Map<String, dynamic>>[
      for (final d in docs)
        if (where == null || where.eval(d, parameters, sql) == true) d,
    ];
    if (_order.isNotEmpty) {
      // Stable: rows that tie keep the order they came in.
      final indexed = rows.asMap().entries.toList();
      indexed.sort((a, b) {
        for (final o in _order) {
          final c = _compareForOrder(
            o.path.eval(a.value, parameters, sql),
            o.path.eval(b.value, parameters, sql),
          );
          if (c != 0) return o.descending ? -c : c;
        }
        return a.key.compareTo(b.key);
      });
      rows
        ..clear()
        ..addAll(indexed.map((e) => e.value));
    }
    final top = _top;
    final limited = top == null || rows.length <= top
        ? rows
        : rows.sublist(0, top);
    final projection = _projection;
    if (projection == null) return [for (final d in limited) _deepCopy(d)];
    return [
      for (final d in limited)
        {
          for (final p in projection)
            if (p.path.eval(d, parameters, sql) case final v
                when !identical(v, _undefined))
              p.name: _deepCopyValue(v),
        },
    ];
  }
}

/// Throws the 400 Cosmos answers a query it cannot run with.
Never _badQuery(String sql, String reason) => throw CosmosException(
  400,
  'Query not understood by the local storage ($reason): $sql',
  code: 'BadRequest',
);

/// Cosmos' *undefined*: a field the document does not have.
const Object _undefined = _Undefined();

class _Undefined {
  const _Undefined();
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> d) =>
    _deepCopyValue(d) as Map<String, dynamic>;

Object? _deepCopyValue(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key as String: _deepCopyValue(e.value),
    };
  }
  if (v is List) return [for (final x in v) _deepCopyValue(x)];
  return v;
}

int _typeRank(Object? v) {
  if (identical(v, _undefined)) return 0;
  if (v == null) return 1;
  if (v is bool) return 2;
  if (v is num) return 3;
  if (v is String) return 4;
  if (v is List) return 5;
  return 6;
}

int _compareForOrder(Object? a, Object? b) {
  final ra = _typeRank(a);
  final rb = _typeRank(b);
  if (ra != rb) return ra.compareTo(rb);
  return _compareSameType(a, b) ?? 0;
}

/// Order of two values of the same scalar type, `null` when they have none.
int? _compareSameType(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  if (a == null && b == null) return 0;
  return null;
}

// --- AST -------------------------------------------------------------------

abstract class _Expr {
  /// `true`, `false`, a value, or [_undefined].
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  );
}

class _Path extends _Expr {
  _Path(this.segments);

  /// Field names (String) and array indexes (int).
  final List<Object> segments;

  String get lastName {
    final last = segments.last;
    return last is String ? last : '\$1';
  }

  @override
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  ) {
    Object? cur = doc;
    for (final s in segments) {
      if (s is String && cur is Map && cur.containsKey(s)) {
        cur = cur[s];
      } else if (s is int && cur is List && s >= 0 && s < cur.length) {
        cur = cur[s];
      } else {
        return _undefined;
      }
    }
    return cur;
  }
}

class _Literal extends _Expr {
  _Literal(this.value);
  final Object? value;

  @override
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  ) => value;
}

class _Param extends _Expr {
  _Param(this.name);
  final String name;

  @override
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  ) {
    if (!params.containsKey(name)) _badQuery(sql, 'no value for $name');
    return params[name];
  }
}

class _Not extends _Expr {
  _Not(this.inner);
  final _Expr inner;

  @override
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  ) {
    final v = inner.eval(doc, params, sql);
    return v is bool ? !v : _undefined;
  }
}

class _Logic extends _Expr {
  _Logic(this.isAnd, this.left, this.right);
  final bool isAnd;
  final _Expr left;
  final _Expr right;

  @override
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  ) {
    final a = left.eval(doc, params, sql);
    final b = right.eval(doc, params, sql);
    if (isAnd) {
      if (a == false || b == false) return false;
      if (a == true && b == true) return true;
      return _undefined;
    }
    if (a == true || b == true) return true;
    if (a == false && b == false) return false;
    return _undefined;
  }
}

class _Compare extends _Expr {
  _Compare(this.op, this.left, this.right);
  final String op;
  final _Expr left;
  final _Expr right;

  @override
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  ) {
    final a = left.eval(doc, params, sql);
    final b = right.eval(doc, params, sql);
    if (identical(a, _undefined) || identical(b, _undefined)) return _undefined;
    if (_typeRank(a) != _typeRank(b)) return _undefined;
    if (op == '=' || op == '!=') {
      final equal = (a is Map || a is List)
          ? jsonEncode(a) == jsonEncode(b)
          : a == b || (a is num && b is num && a.compareTo(b) == 0);
      return op == '=' ? equal : !equal;
    }
    final c = _compareSameType(a, b);
    if (c == null) return _undefined;
    return switch (op) {
      '<' => c < 0,
      '<=' => c <= 0,
      '>' => c > 0,
      '>=' => c >= 0,
      _ => _undefined,
    };
  }
}

class _Call extends _Expr {
  _Call(this.function, this.arg);
  final String function;
  final _Expr arg;

  @override
  Object? eval(
    Map<String, dynamic> doc,
    Map<String, Object?> params,
    String sql,
  ) {
    final v = arg.eval(doc, params, sql);
    return switch (function) {
      'IS_DEFINED' => !identical(v, _undefined),
      'IS_NULL' => v == null,
      'ARRAY_LENGTH' => v is List ? v.length : _undefined,
      _ => _undefined,
    };
  }
}

class _Projection {
  _Projection(this.path, this.name);
  final _Path path;
  final String name;
}

class _OrderBy {
  _OrderBy(this.path, {required this.descending});
  final _Path path;
  final bool descending;
}

// --- Lexer -----------------------------------------------------------------

enum _T { word, param, number, string, punct, end }

class _Token {
  _Token(this.type, this.text, [this.value]);
  final _T type;
  final String text;
  final Object? value;

  bool isWord(String w) => type == _T.word && text.toUpperCase() == w;
  bool isPunct(String p) => type == _T.punct && text == p;

  @override
  String toString() => type == _T.end ? 'end of query' : '"$text"';
}

List<_Token> _lex(String sql) {
  final out = <_Token>[];
  var i = 0;
  bool isWordChar(String ch) => RegExp(r'[A-Za-z0-9_]').hasMatch(ch);
  while (i < sql.length) {
    final ch = sql[i];
    if (ch.trim().isEmpty) {
      i++;
      continue;
    }
    if (RegExp(r'[A-Za-z_]').hasMatch(ch)) {
      final start = i;
      while (i < sql.length && isWordChar(sql[i])) {
        i++;
      }
      out.add(_Token(_T.word, sql.substring(start, i)));
      continue;
    }
    if (ch == '@') {
      final start = i++;
      while (i < sql.length && isWordChar(sql[i])) {
        i++;
      }
      if (i == start + 1) _badQuery(sql, 'a lone "@"');
      out.add(_Token(_T.param, sql.substring(start, i)));
      continue;
    }
    if (RegExp(r'[0-9]').hasMatch(ch) ||
        (ch == '-' &&
            i + 1 < sql.length &&
            RegExp(r'[0-9]').hasMatch(sql[i + 1]))) {
      final start = i++;
      while (i < sql.length && RegExp(r'[0-9.]').hasMatch(sql[i])) {
        i++;
      }
      final text = sql.substring(start, i);
      final value = num.tryParse(text) ?? _badQuery(sql, 'bad number $text');
      out.add(_Token(_T.number, text, value));
      continue;
    }
    if (ch == '"' || ch == "'") {
      final start = i++;
      final buf = StringBuffer();
      while (i < sql.length && sql[i] != ch) {
        if (sql[i] == r'\' && i + 1 < sql.length) i++;
        buf.write(sql[i]);
        i++;
      }
      if (i >= sql.length) _badQuery(sql, 'unterminated string');
      i++;
      out.add(_Token(_T.string, sql.substring(start, i), buf.toString()));
      continue;
    }
    final two = i + 1 < sql.length ? sql.substring(i, i + 2) : '';
    if (two == '<=' || two == '>=' || two == '!=' || two == '<>') {
      out.add(_Token(_T.punct, two == '<>' ? '!=' : two));
      i += 2;
      continue;
    }
    if ('*,.()[]=<>'.contains(ch)) {
      out.add(_Token(_T.punct, ch));
      i++;
      continue;
    }
    _badQuery(sql, 'unexpected "$ch"');
  }
  out.add(_Token(_T.end, ''));
  return out;
}

// --- Parser ----------------------------------------------------------------

const Set<String> _keywords = {
  'SELECT',
  'TOP',
  'FROM',
  'WHERE',
  'ORDER',
  'BY',
  'ASC',
  'DESC',
  'AND',
  'OR',
  'NOT',
  'AS',
  'VALUE',
  'DISTINCT',
  'JOIN',
  'IN',
  'GROUP',
  'OFFSET',
  'LIMIT',
};

const Set<String> _functions = {'IS_DEFINED', 'IS_NULL', 'ARRAY_LENGTH'};

class _Parser {
  _Parser(this.sql) : _tokens = _lex(sql);

  final String sql;
  final List<_Token> _tokens;
  int _pos = 0;
  String? _alias;

  _Token get _peek => _tokens[_pos];
  _Token _next() => _tokens[_pos++];

  Never _fail(String reason) => _badQuery(sql, reason);

  void _expectWord(String w) {
    final t = _next();
    if (!t.isWord(w)) _fail('expected $w, found $t');
  }

  void _expectPunct(String p) {
    final t = _next();
    if (!t.isPunct(p)) _fail('expected "$p", found $t');
  }

  CosmosQuery parse() {
    _expectWord('SELECT');
    int? top;
    if (_peek.isWord('TOP')) {
      _next();
      final t = _next();
      if (t.type != _T.number || t.value is! int || (t.value as int) < 0) {
        _fail('TOP needs a whole number, found $t');
      }
      top = t.value as int;
    }

    // The projection names the alias before FROM declares it: read it as
    // tokens first, resolve it once the alias is known.
    final projectionStart = _pos;
    while (!_peek.isWord('FROM')) {
      if (_peek.type == _T.end) _fail('no FROM');
      _next();
    }
    final projectionEnd = _pos;

    _expectWord('FROM');
    final alias = _next();
    if (alias.type != _T.word || _keywords.contains(alias.text.toUpperCase())) {
      _fail('expected a collection alias after FROM, found $alias');
    }
    _alias = alias.text;
    final afterFrom = _pos;

    _pos = projectionStart;
    final projection = _parseProjection(projectionEnd);
    _pos = afterFrom;

    _Expr? where;
    if (_peek.isWord('WHERE')) {
      _next();
      where = _parseOr();
    }

    final order = <_OrderBy>[];
    if (_peek.isWord('ORDER')) {
      _next();
      _expectWord('BY');
      do {
        if (order.isNotEmpty) _next(); // the comma
        final path = _parsePath();
        var descending = false;
        if (_peek.isWord('ASC')) {
          _next();
        } else if (_peek.isWord('DESC')) {
          _next();
          descending = true;
        }
        order.add(_OrderBy(path, descending: descending));
      } while (_peek.isPunct(','));
    }

    if (_peek.type != _T.end) _fail('unexpected $_peek');
    return CosmosQuery._(sql, top, projection, where, order);
  }

  List<_Projection>? _parseProjection(int end) {
    if (_peek.isPunct('*')) {
      _next();
      if (_pos != end) _fail('unexpected ${_tokens[_pos]} after *');
      return null;
    }
    final out = <_Projection>[];
    while (true) {
      final path = _parsePath();
      var name = path.lastName;
      if (_peek.isWord('AS')) {
        _next();
        final t = _next();
        if (t.type != _T.word) _fail('expected a name after AS, found $t');
        name = t.text;
      }
      out.add(_Projection(path, name));
      if (_pos == end) break;
      _expectPunct(',');
    }
    if (_pos != end) _fail('unexpected ${_tokens[_pos]} in SELECT');
    return out;
  }

  _Path _parsePath() {
    final root = _next();
    if (root.type != _T.word || root.text != _alias) {
      _fail('expected a path on "$_alias", found $root');
    }
    final segments = <Object>[];
    while (true) {
      if (_peek.isPunct('.')) {
        _next();
        final t = _next();
        if (t.type != _T.word) _fail('expected a field name, found $t');
        segments.add(t.text);
      } else if (_peek.isPunct('[')) {
        _next();
        final t = _next();
        if (t.type == _T.string) {
          segments.add(t.value as String);
        } else if (t.type == _T.number && t.value is int) {
          segments.add(t.value as int);
        } else {
          _fail('expected a field name or index in [], found $t');
        }
        _expectPunct(']');
      } else {
        break;
      }
    }
    if (segments.isEmpty) _fail('a bare "$_alias" is not supported');
    return _Path(segments);
  }

  _Expr _parseOr() {
    var left = _parseAnd();
    while (_peek.isWord('OR')) {
      _next();
      left = _Logic(false, left, _parseAnd());
    }
    return left;
  }

  _Expr _parseAnd() {
    var left = _parseNot();
    while (_peek.isWord('AND')) {
      _next();
      left = _Logic(true, left, _parseNot());
    }
    return left;
  }

  _Expr _parseNot() {
    if (_peek.isWord('NOT')) {
      _next();
      return _Not(_parseNot());
    }
    return _parseComparison();
  }

  _Expr _parseComparison() {
    final left = _parseOperand();
    final t = _peek;
    if (t.type == _T.punct &&
        const {'=', '!=', '<', '<=', '>', '>='}.contains(t.text)) {
      _next();
      return _Compare(t.text, left, _parseOperand());
    }
    return left;
  }

  _Expr _parseOperand() {
    final t = _peek;
    if (t.isPunct('(')) {
      _next();
      final inner = _parseOr();
      _expectPunct(')');
      return inner;
    }
    if (t.type == _T.param) {
      _next();
      return _Param(t.text);
    }
    if (t.type == _T.number || t.type == _T.string) {
      _next();
      return _Literal(t.value);
    }
    if (t.type == _T.word) {
      final upper = t.text.toUpperCase();
      if (upper == 'TRUE') {
        _next();
        return _Literal(true);
      }
      if (upper == 'FALSE') {
        _next();
        return _Literal(false);
      }
      if (upper == 'NULL') {
        _next();
        return _Literal(null);
      }
      if (t.text == _alias) return _parsePath();
      if (_tokens[_pos + 1].isPunct('(')) {
        if (!_functions.contains(upper)) _fail('unknown function ${t.text}');
        _next();
        _next();
        final arg = _parseOr();
        _expectPunct(')');
        return _Call(upper, arg);
      }
    }
    _fail('unexpected $t');
  }
}
