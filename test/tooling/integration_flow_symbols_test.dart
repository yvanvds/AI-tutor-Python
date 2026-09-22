// Issue #155 — an integration flow must not be left driving a widget key that
// nothing in lib/ produces any more, and must not resolve the app's scroll
// view by position.
//
// #154 is the failure this exists to stop. `9f44cf4` (#148) deleted
// `lib/features/account/detail/grade_proposal_section.dart` and ported the one
// flow it knew about (`integration_test/flows/grade_proposal.dart`); a second
// flow, `integration_test/flows/period_start_snapshot.dart`, drove the same
// deleted section and went red without anyone noticing. Nothing local could
// see it: widget keys here are string literals, so `flutter analyze` stayed
// clean and every unit test stayed green, and the batch rule — run the
// integration files a commit *touches* — never put that flow in the set,
// because the commit touched it only by deleting the surface underneath it.
// The only thing that would have caught it was the full Windows sweep, ten
// minutes away in CI.
//
// So the invariant is stated here instead, and deliberately as a property of
// the whole tree rather than of a diff: every key literal a flow drives must
// exist somewhere in lib/. That is what makes it usable. There is no base ref
// to choose, it costs a second inside `flutter test` — so it runs locally
// before the commit, not only in CI — and moving a key from one lib/ file to
// another, which is what an ordinary rename does, cannot fire it, because the
// question is only ever "does lib/ still produce this key".
//
// The other half of #155 — a deleted widget *class* an untouched flow still
// names — needs no check of its own: it is an unresolved identifier, so the
// analyzer reports it. It went unreported only because the CI gate was
// `flutter analyze lib test`, narrower than the bare `flutter analyze` run
// locally. The gate now includes `integration_test` (see .github/workflows/
// build.yml), which is stricter than any grep over removed class names.
//
// #156's CI failure was a different shape, and the key guard would not have
// caught it: `a20ef0b` wrapped the sidebar rail in a scroll view, and three
// About flows that resolved their scroll view as `find.byType(Scrollable)
// .first` silently started dragging the rail. Those flows referenced nothing
// the commit changed — the breakage travelled through the *shape* of the
// widget tree, which no symbol-level check can see. What is checkable is the
// precondition: picking an ambient framework type by position is a bomb
// waiting for the tree to grow another one. The second test below forbids the
// unscoped `find.byType(Scrollable)` that made the failure silent (it fires on
// all three flows as they stood before dc57931). The rest of that class — a
// page's own ordinal finders, `find.byType(TextField).first` and friends — is
// tracked separately in #158, and "the tree changed shape" in general stays
// the full Windows sweep's job.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A `Key('…')` or `ValueKey('…')` with a single-quoted value.
///
/// The lookbehind is what keeps `containsKey('answer')` — and `ObjectKey`,
/// `PageStorageKey`, `GlobalObjectKey` — out of the match.
final _keyLiteral = RegExp(r"(?<![A-Za-z0-9_])(?:Value)?Key\('([^']*)'\)");

/// `$foo` or `${foo.bar}` inside a key value.
final _interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z0-9_.]+');

final _scrollableByType = RegExp(r'find\.byType\(Scrollable\)');

List<File> _dartFiles(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) {
    throw StateError('${root.path} is missing (cwd: ${Directory.current})');
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _rel(File file) => file.path.replaceAll(r'\', '/');

int _lineOf(String source, int offset) =>
    source.substring(0, offset).split('\n').length;

/// Whether the line an offset sits on is a comment line.
///
/// Both checks below are text searches, and the harness documents the very
/// pattern the second one forbids ("Never `find.byType(Scrollable)` …"), so
/// prose has to be excluded or the guard fires on its own explanation. Only a
/// line that *starts* as a comment counts: a trailing `//` after real code is
/// still scanned, so nothing is hidden by appending a comment to it.
bool _inComment(String source, int offset) {
  final lineStart = source.lastIndexOf('\n', offset) + 1;
  final before = source.substring(lineStart, offset).trimLeft();
  return before.startsWith('//') || before.startsWith('*');
}

/// The statement a match sits in, so a wrapped `expect(…)` keeps the
/// `findsNothing` that belongs to it.
String _statementAround(String source, Match match) {
  final from = source.lastIndexOf(';', match.start) + 1;
  final to = source.indexOf(';', match.end);
  return source.substring(from, to < 0 ? source.length : to);
}

/// `Key('reports-row-$uid')` in lib/ becomes `^reports-row-.*$`, so the
/// `Key('reports-row-it-dave')` a flow builds from a seed id still resolves.
RegExp _patternFor(String value) {
  final pattern = StringBuffer('^');
  var at = 0;
  for (final match in _interpolation.allMatches(value)) {
    pattern
      ..write(RegExp.escape(value.substring(at, match.start)))
      ..write('.*');
    at = match.end;
  }
  pattern
    ..write(RegExp.escape(value.substring(at)))
    ..write(r'$');
  return RegExp(pattern.toString());
}

/// Every key lib/ can render: the plain literals, plus a pattern per key
/// built with string interpolation.
class _LibKeys {
  _LibKeys(this.literals, this.patterns);

  factory _LibKeys.scan() {
    final literals = <String>{};
    final patterns = <RegExp>[];
    for (final file in _dartFiles('lib')) {
      for (final match in _keyLiteral.allMatches(file.readAsStringSync())) {
        final value = match.group(1)!;
        if (value.contains(r'$')) {
          patterns.add(_patternFor(value));
        } else {
          literals.add(value);
        }
      }
    }
    return _LibKeys(literals, patterns);
  }

  final Set<String> literals;
  final List<RegExp> patterns;

  bool produces(String key) =>
      literals.contains(key) || patterns.any((p) => p.hasMatch(key));
}

void main() {
  final flows = _dartFiles('integration_test');

  group('integration flows stay wired to what lib/ actually renders', () {
    test('every key a flow drives is still produced somewhere in lib/', () {
      final libKeys = _LibKeys.scan();
      // A tripwire: if the scan ever silently stops finding keys (a regex that
      // no longer matches how lib/ spells them), every flow below would pass
      // vacuously.
      expect(
        libKeys.literals,
        isNotEmpty,
        reason:
            'No plain Key(\'…\') literal was found in lib/ at all, so the '
            'check below cannot fail — fix _keyLiteral, do not delete this.',
      );

      final stale = <String>[];
      for (final file in flows) {
        final source = file.readAsStringSync();
        for (final match in _keyLiteral.allMatches(source)) {
          final value = match.group(1)!;
          if (_inComment(source, match.start)) continue;
          // The flow builds this one at runtime (a seed uid, a scope name);
          // there is no literal to resolve.
          if (value.contains(r'$')) continue;
          // `findsNothing` is a flow asserting the key is *gone* — the
          // opposite claim, and the correct way to port a flow past a
          // deletion.
          if (_statementAround(source, match).contains('findsNothing')) {
            continue;
          }
          if (libKeys.produces(value)) continue;
          stale.add(
            "${_rel(file)}:${_lineOf(source, match.start)} — Key('$value')",
          );
        }
      }

      expect(
        stale,
        isEmpty,
        reason:
            'These flows drive widget keys that no longer exist anywhere in '
            'lib/, so they can only fail at runtime, in the Windows '
            'integration sweep — the #154 failure mode.\n'
            'The fix belongs in the commit that removed the key: port the '
            'flow to the surface that replaced it, delete the flow, or — if '
            'the point is that the widget is gone — assert its absence with '
            '`findsNothing`, which this check honours.\n'
            'If instead you moved the key inside lib/, this is a false alarm '
            'worth reporting: a key that is still produced anywhere in lib/ '
            'is accepted, interpolated ones included.\n'
            'Stale references:',
      );
    });

    test('no flow resolves a Scrollable by bare type', () {
      final unscoped = <String>[];
      for (final file in flows) {
        final source = file.readAsStringSync();
        for (final match in _scrollableByType.allMatches(source)) {
          if (_inComment(source, match.start)) continue;
          // Scoped, i.e. the `matching:` argument of a descendant/ancestor
          // finder that says which subtree is meant.
          if (source
              .substring(0, match.start)
              .trimRight()
              .endsWith('matching:')) {
            continue;
          }
          unscoped.add('${_rel(file)}:${_lineOf(source, match.start)}');
        }
      }

      expect(
        unscoped,
        isEmpty,
        reason:
            'A `find.byType(Scrollable)` that is not scoped to a subtree '
            'matches every scroll view in the app, and the shell has more '
            'than one: in #156 wrapping the sidebar rail in a scroll view '
            'made three About flows drag the *rail* instead of the Options '
            'page, and they failed in CI without referencing anything that '
            'commit changed.\n'
            'The fix: `optionsScrollable()` from '
            'integration_test/harness/app_harness.dart for the Options page, '
            'or `find.descendant(of: find.byType(<the page>), matching: '
            'find.byType(Scrollable))` for any other one. Never the bare '
            'finder, and never its `.first`.\n'
            'Unscoped finders:',
      );
    });
  });
}
