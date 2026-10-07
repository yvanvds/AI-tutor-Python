// Issue #206 — the `translations` doc shape and the `sourceHash` a
// translation is judged stale by. The hash is pinned to values computed
// outside Dart (Python's hashlib, the recipe in `translationSourceHash`'s
// doc comment), because the tooling that writes the first translations
// (#209) computes it in Python: the two must agree to the byte.
//
// Issue #243 — a learning objective's statement is a translation of its
// own: one `objective_${subgoalId}.${loId}` doc per LO, the statement
// stored as `statement`, no title, hashed with an empty title.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sourceHash', () {
    test('matches the Python recipe, line endings normalised', () {
      // hashlib.sha256((norm(title) + '\0' + norm(text)).encode('utf-8'))
      const expected =
          '220e6ffa097b1396a5982f8baf0566150210b353685950bdf105f95a87f13973';
      const body = '<p>Een variabele is een doos.</p>\r\n<p>Één ding.</p>';
      expect(translationSourceHash('Variabelen', body), expected);
      expect(
        translationSourceHash('Variabelen', body.replaceAll('\r\n', '\n')),
        expected,
        reason: 'a CRLF/LF round trip through an editor is not a change',
      );
      expect(
        contentSourceHash(Content(id: 's1', title: 'Variabelen', body: body)),
        expected,
      );
    });

    test('a goal without a description hashes as an empty one', () {
      const expected =
          '941ad07a66ce42e57501dd67f2b0aaf3472c1009fdbbadcf13080f215f2403c4';
      expect(
        goalSourceHash(Goal(id: 'r1', title: 'Lussen', order: 0)),
        expected,
      );
      expect(
        goalSourceHash(
          Goal(id: 'r1', title: 'Lussen', description: '', order: 0),
        ),
        expected,
      );
    });

    test('an LO statement hashes with an empty title (#243)', () {
      // hashlib.sha256(('' + '\0' + statement).encode('utf-8'))
      const expected =
          '62df92465cc34d981136db5f95321525b64e6c4379cf2eb594e8424f55b9335c';
      const statement =
          'Je kan een for-lus schrijven die een bewerking een vast aantal '
          'keer herhaalt.';
      expect(
        objectiveSourceHash(
          const LearningObjective(
            id: 'write_for_loop',
            statement: statement,
            kind: LoKind.apply,
          ),
        ),
        expected,
      );
      expect(translationSourceHash('', statement), expected);
    });

    test('any change to the title or the text changes it', () {
      final base = translationSourceHash('Lussen', 'Herhalen met for.');
      expect(
        translationSourceHash('Lussen!', 'Herhalen met for.'),
        isNot(base),
      );
      expect(
        translationSourceHash('Lussen', 'Herhalen met while.'),
        isNot(base),
      );
      // The separator keeps title and text apart.
      expect(
        translationSourceHash('Lussen H', 'erhalen met for.'),
        isNot(base),
      );
    });
  });

  group('doc shape', () {
    test('a lesson translation round-trips through its Cosmos doc', () {
      final t = Translation.content(
        language: 'en',
        contentId: 's1',
        title: 'Variables',
        body: '<p>A variable is a box.</p>',
        sourceHash: 'abc',
        updatedAt: DateTime.utc(2026, 9, 30, 8),
      );
      final doc = t.toMap();
      expect(doc, {
        'id': 'content_s1',
        'language': 'en',
        'kind': 'content',
        'refId': 's1',
        'title': 'Variables',
        'body': '<p>A variable is a box.</p>',
        'sourceHash': 'abc',
        'updatedAt': '2026-09-30T08:00:00.000Z',
      });
      expect(Translation.tryFromCosmos(doc), t);
    });

    test('a goal translation stores its text as the description', () {
      final t = Translation.goal(
        language: 'en',
        goalId: 's1',
        title: 'Loops',
        description: 'Repeat with for.',
        sourceHash: 'abc',
      );
      final doc = t.toMap();
      expect(doc['id'], 'goal_s1');
      expect(doc['kind'], 'goal');
      expect(doc['description'], 'Repeat with for.');
      expect(doc.containsKey('body'), isFalse);
      expect(Translation.tryFromCosmos(doc), t);
    });

    test('an LO translation (#243) stores its statement, no title, under '
        'the subgoal and LO id', () {
      final t = Translation.objective(
        language: 'en',
        subgoalId: 'herhalen-for',
        loId: 'write_for_loop',
        statement: 'You can write a for loop that repeats a step.',
        sourceHash: 'abc',
        updatedAt: DateTime.utc(2026, 10, 7, 8),
      );
      final doc = t.toMap();
      expect(doc, {
        'id': 'objective_herhalen-for.write_for_loop',
        'language': 'en',
        'kind': 'objective',
        'refId': 'herhalen-for.write_for_loop',
        'statement': 'You can write a for loop that repeats a step.',
        'sourceHash': 'abc',
        'updatedAt': '2026-10-07T08:00:00.000Z',
      });
      expect(
        t.id,
        Translation.objectiveDocId('herhalen-for', 'write_for_loop'),
      );
      expect(Translation.tryFromCosmos(doc), t);
    });

    test('a lesson and its subgoal share an id but not a doc id', () {
      expect(
        Translation.contentDocId('s1'),
        isNot(Translation.goalDocId('s1')),
      );
    });

    test('docs this build cannot read are skipped, not thrown on', () {
      expect(Translation.tryFromCosmos({'id': 'x', 'kind': 'content'}), isNull);
      expect(
        Translation.tryFromCosmos({
          'id': 'x',
          'language': 'en',
          'kind': 'audio',
          'refId': 's1',
        }),
        isNull,
      );
      expect(
        Translation.tryFromCosmos({
          'id': 'x',
          'language': 'en',
          'kind': 'goal',
        }),
        isNull,
      );
    });

    test('stale when the Dutch text hashes differently now', () {
      final t = Translation.content(
        language: 'en',
        contentId: 's1',
        title: 'Variables',
        body: '<p>x</p>',
        sourceHash: translationSourceHash('Variabelen', '<p>x</p>'),
      );
      expect(
        t.isStaleFor(translationSourceHash('Variabelen', '<p>x</p>')),
        isFalse,
      );
      expect(
        t.isStaleFor(translationSourceHash('Variabelen', '<p>y</p>')),
        isTrue,
      );
    });
  });

  group('status (#208)', () {
    final hash = translationSourceHash('Variabelen', '<p>x</p>');
    Translation made(String from) => Translation.content(
      language: 'en',
      contentId: 's1',
      title: 'Variables',
      body: '<p>x</p>',
      sourceHash: from,
    );

    test('missing, current or stale against the Dutch text as it is now', () {
      expect(translationStatus(null, hash), TranslationStatus.missing);
      expect(translationStatus(made(hash), hash), TranslationStatus.current);
      expect(
        translationStatus(made(hash), translationSourceHash('Variabelen', '')),
        TranslationStatus.stale,
      );
    });

    test('the content languages are the app languages, the source first', () {
      expect(kContentLanguages.first, kSourceLanguage);
      expect(kContentLanguages.skip(1), kTranslationLanguages);
      expect(kTranslationLanguages, isNot(contains(kSourceLanguage)));
      expect(
        kContentLanguages.toSet(),
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
        reason:
            'a UI language the editors do not offer, or one they offer '
            'that the app cannot show',
      );
    });
  });
}
