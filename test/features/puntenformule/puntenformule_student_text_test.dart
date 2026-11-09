// #301: the Puntenformule tab opens on a short explanation for students,
// `docs/puntenformule-leerlingen.nl.md` and `.en.md`, next to the
// specification `docs/PUNTENFORMULE.md`. Three files written by hand that
// have to keep saying the same thing, so this compares them — the way
// `test/core/cosmos_paths_readme_parity_test.dart` compares the README with
// the source:
//
//   - **one version**: both texts name the specification's version and its
//     formula, and the formula is the number the app stamps on every
//     proposal and report (`GradingConstants.formulaVersion`). A new version
//     of the specification fails here until someone has looked at the short
//     texts (PUNTENFORMULE §5);
//   - **the formula and its example are the app's**: the weights in the
//     texts are `GradingConstants`, `C(k) = k` holds, and the worked example
//     is recomputed with the real `computeMasteryScore`;
//   - **the student's words**: the texts use the labels the app shows
//     (aangetoond, Leerpad, Mijn rapporten, the three levels, …), read from
//     the ARB files, and none of the specification's jargon;
//   - **short and safe to render**: at most 800 words of prose, headings as
//     questions, and no links — the lesson view has no navigation handling,
//     so a link would take the WebView away from the text.
//
// The texts are read through the asset bundle, like the app reads them, so
// a missing `pubspec.yaml` entry fails here as well.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/features/puntenformule/puntenformule_page.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/grading/grade_formula.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// One short text with what differs per language.
class _Text {
  _Text({
    required this.language,
    required this.assetKey,
    required this.decimal,
    required this.docVersion,
    required this.formulaVersion,
    required this.jargon,
  });

  final String language;
  final String assetKey;

  /// The decimal separator the language writes: `0,8` or `0.8`.
  final String decimal;

  /// Where the text names the specification's version and the formula's.
  final RegExp docVersion;
  final RegExp formulaVersion;

  /// Words of the specification (or of the code) a student never sees.
  final List<RegExp> jargon;

  late String source;

  AppLocalizations get l => lookupAppLocalizations(Locale(language));

  String n(double value, {int digits = 1}) =>
      value.toStringAsFixed(digits).replaceAll('.', decimal);
}

final _version = r'(\d+(?:\.\d+)+)';

final _texts = [
  _Text(
    language: 'nl',
    assetKey: kPuntenformuleStudentNlAssetKey,
    decimal: ',',
    docVersion: RegExp('versie $_version van de puntenformule'),
    formulaVersion: RegExp('rekent met formule $_version'),
    jargon: [
      for (final word in [
        'angoff',
        'overtuiging',
        'kalibratie',
        'gekalibreerd',
        'bewijsmassa',
        'beurt',
        'mijlpaal',
        'ratel',
        'stempel',
      ])
        RegExp(word, caseSensitive: false),
    ],
  ),
  _Text(
    language: 'en',
    assetKey: kPuntenformuleStudentEnAssetKey,
    decimal: '.',
    docVersion: RegExp('version $_version of the grade formula'),
    formulaVersion: RegExp('computes with\\s+formula $_version'),
    jargon: [
      for (final word in [
        'angoff',
        'belief',
        'calibrat',
        'evidence mass',
        r'\bturns?\b',
        'milestone',
        'ratchet',
        r'\bstamp',
      ])
        RegExp(word, caseSensitive: false),
    ],
  ),
];

/// The specification's header: `**Versie 1.1.1** — formule 1.1, …`.
final _specHeader = RegExp(
  r'^\*\*Versie ' + _version + r'\*\* — formule ' + _version,
  multiLine: true,
);

List<int> _parts(String version) {
  final p = version.split('.').map(int.parse).toList();
  return [...p, ...List<int>.filled(3 - p.length, 0)];
}

int _compare(String a, String b) {
  final x = _parts(a);
  final y = _parts(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

/// Prose only: the fenced formula blocks are maths, not reading.
int _proseWords(String markdown) => markdown
    .replaceAll(RegExp(r'^```[\s\S]*?^```', multiLine: true), '')
    .split(RegExp(r'\s+'))
    .where((w) => RegExp(r'\w').hasMatch(w))
    .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String spec;

  setUpAll(() async {
    spec = (await rootBundle.loadString(kPuntenformuleAssetKey))
        .replaceAll('\r\n', '\n');
    for (final text in _texts) {
      text.source = (await rootBundle.loadString(text.assetKey))
          .replaceAll('\r\n', '\n');
    }
  });

  test('the tab picks the text in the app\'s language, English otherwise', () {
    expect(puntenformuleStudentAssetKey('nl'), kPuntenformuleStudentNlAssetKey);
    expect(puntenformuleStudentAssetKey('en'), kPuntenformuleStudentEnAssetKey);
    expect(puntenformuleStudentAssetKey('fr'), kPuntenformuleStudentEnAssetKey);
  });

  group('one version (PUNTENFORMULE §5)', () {
    late String docVersion;
    late String formulaVersion;

    setUp(() {
      final header = _specHeader.firstMatch(spec);
      expect(
        header,
        isNotNull,
        reason:
            'the specification lost its "**Versie X** — formule Y" header '
            'line',
      );
      docVersion = header!.group(1)!;
      formulaVersion = header.group(2)!;
    });

    test('the specification\'s header names its newest log row', () {
      final rows = RegExp(
        r'^\|\s*' + _version + r'\s*\|\s*\d{4}-\d{2}-\d{2}\s*\|',
        multiLine: true,
      ).allMatches(spec).map((m) => m.group(1)!).toList();
      expect(rows, isNotEmpty);
      final newest = rows.reduce((a, b) => _compare(a, b) >= 0 ? a : b);
      expect(docVersion, newest);
      // The formula number is a version the log knows, and never newer than
      // the document: a text-only version keeps it (§5).
      expect(rows, contains(formulaVersion));
      expect(_compare(formulaVersion, docVersion), lessThanOrEqualTo(0));
    });

    test('the formula in the header is the one the app stamps on proposals '
        'and reports', () {
      expect(GradingConstants.formulaVersion, formulaVersion);
    });

    for (final text in _texts) {
      test('the ${text.language} text names the same versions', () {
        final doc = text.docVersion.firstMatch(text.source);
        final formula = text.formulaVersion.firstMatch(text.source);
        expect(doc, isNotNull, reason: 'no version line in ${text.assetKey}');
        expect(formula, isNotNull, reason: 'no formula in ${text.assetKey}');
        expect(
          doc!.group(1),
          docVersion,
          reason:
              '${text.assetKey} still describes version ${doc.group(1)}: '
              'read it against the new specification, update what a student '
              'notices, then its version line',
        );
        expect(formula!.group(1), formulaVersion);
      });
    }
  });

  group('the formula and the worked example are the app\'s', () {
    test('C(k) = k: the texts write the curve under the 50 as k', () {
      for (final k in [0.0, 0.25, 0.5, 0.8, 1.0]) {
        expect(GradingConstants.curve(k), k);
      }
    });

    for (final text in _texts) {
      test('the ${text.language} formula carries the app\'s weights', () {
        final wu = text.n(GradingConstants.weightExtension);
        final wd = text.n(GradingConstants.weightDifficulty);
        expect(
          text.source,
          contains('M = 50 · k  +  50 · k · ($wu · u + $wd · d)'),
        );
      });
    }

    test('the example (8 of 10 core, 2 of 4 extension, 3 at hard) comes out '
        'the way the texts say, with the real formula', () {
      // Core at the expected level (medium): 8 of 10, two of them also
      // answered right at hard. Extension: 2 of 4, one of them at hard.
      // So 10 demonstrated, 3 at hard.
      final los = [
        for (var i = 0; i < 10; i++)
          MilestoneLo(subgoalId: 's', loId: 'k$i', isCore: true),
        for (var i = 0; i < 4; i++)
          MilestoneLo(subgoalId: 's', loId: 'u$i', isCore: false),
      ];
      final inputs = <String, LoGradeInput>{
        for (var i = 0; i < 8; i++)
          's/k$i': LoGradeInput(
            mastered: true,
            highest: i < 2
                ? QuestionDifficulty.hard
                : QuestionDifficulty.medium,
          ),
        's/u0': const LoGradeInput(
          mastered: true,
          highest: QuestionDifficulty.hard,
        ),
        's/u1': const LoGradeInput(
          mastered: true,
          highest: QuestionDifficulty.medium,
        ),
      };
      final score = computeMasteryScore(
        los: los,
        inputs: inputs,
        expectedDifficulty: QuestionDifficulty.medium,
      );
      expect(score.coreCounted, 8);
      expect(score.coreTotal, 10);
      expect(score.extensionMastered, 2);
      expect(score.extensionTotal, 4);
      expect(score.masteredTotal, 10);
      expect(score.hardCount, 3);
      expect(score.k, closeTo(0.8, 1e-12));
      expect(score.u, closeTo(0.5, 1e-12));
      expect(score.d, closeTo(0.3, 1e-12));
      expect(score.m, closeTo(56.8, 1e-9));
      final grade = roundedProposal(proposalScore(mEnd: score.m));
      expect(grade, 57);

      final above =
          GradingConstants.weightExtension * score.u +
          GradingConstants.weightDifficulty * score.d;
      for (final text in _texts) {
        final k = text.n(score.k);
        final u = text.n(score.u);
        final d = text.n(score.d);
        final wu = text.n(GradingConstants.weightExtension);
        final wd = text.n(GradingConstants.weightDifficulty);
        final base = text.n(50 * score.k, digits: 0);
        for (final line in [
          'k = $k',
          'u = $u',
          'd = $d',
          'M = 50 · $k + 50 · $k · ($wu · $u + $wd · $d)',
          '= $base + $base · ${text.n(above, digits: 2)}',
          '= $base + ${text.n(50 * score.k * above)} = ${text.n(score.m)}',
          ' $grade\n',
        ]) {
          expect(
            text.source,
            contains(line),
            reason: '${text.assetKey}: the worked example lost "$line"',
          );
        }
      }
    });
  });

  group('the student\'s words', () {
    for (final text in _texts) {
      test('the ${text.language} text uses the labels the app shows', () {
        final l = text.l;
        for (final label in [
          l.leerpad_objective_demonstrated,
          l.leerpad_objective_notYetDemonstrated,
          l.sidebar_section_map,
          l.sidebar_section_myReports,
          l.myReports_breakdown_title,
          l.difficulty_easy,
          l.difficulty_medium,
          l.difficulty_hard,
        ]) {
          expect(
            text.source,
            contains(label),
            reason: '${text.assetKey} does not use the app\'s "$label"',
          );
        }
      });

      test('the ${text.language} text has none of the specification\'s '
          'jargon', () {
        for (final word in text.jargon) {
          expect(
            word.hasMatch(text.source),
            isFalse,
            reason: '${text.assetKey} uses "${word.pattern}"',
          );
        }
        // No section numbers, and no Greek: the belief's letters stay in
        // the specification.
        for (final glyph in ['§', 'μ', 'α', 'β', 'λ']) {
          expect(text.source, isNot(contains(glyph)));
        }
      });
    }
  });

  group('short and safe to render', () {
    for (final text in _texts) {
      test('the ${text.language} text is at most 800 words of prose', () {
        expect(_proseWords(text.source), lessThanOrEqualTo(800));
      });

      test('the ${text.language} headings are questions', () {
        final headings = RegExp(
          r'^#{1,3} (.+)$',
          multiLine: true,
        ).allMatches(text.source).map((m) => m.group(1)!.trim()).toList();
        expect(headings.length, greaterThan(5));
        for (final heading in headings) {
          expect(heading, endsWith('?'));
        }
      });

      test('the ${text.language} text converts without links or live '
          'blocks', () {
        final html = puntenformuleToHtml(text.source);
        expect(html, contains('<h1'));
        expect(html, contains('<h2'));
        expect(html, contains('<pre><code>'));
        expect(html, isNot(contains('<a ')));
        expect(html, isNot(contains('class="run"')));
        expect(html, isNot(contains('<script')));
        expect(html, isNot(contains('<table>')));
      });
    }
  });
}
