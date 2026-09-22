// Issue #147 — the off-script run detector behind the reply guard.
//
// The reported symptom is the first test: normal Dutch with one word
// replaced by a clump of non-Latin lookalikes. The rest pin the boundaries
// that keep the guard from refusing a good reply — accented Dutch, a lone
// Greek letter in a formula, emoji, and non-Latin characters inside code,
// where they belong.

import 'package:ai_tutor_python/services/tutor/responses/script_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// The reply from #147, with the garbled word written out as the Armenian
/// lookalikes it was described as.
const String _garbledFeedback =
    'Niet **աբգդե**: de voorwaarde wordt `True`, dus er wordt **ja** '
    'afgedrukt. De eerste helft wordt eerst `False` door de `not`, en '
    'daarna maakt `or` het geheel alsnog `True`.';

const String _cleanFeedback =
    'Niet **helemaal**: de voorwaarde wordt `True`, dus er wordt **ja** '
    'afgedrukt. De eerste helft wordt eerst `False` door de `not`, en '
    'daarna maakt `or` het geheel alsnog `True`.';

void main() {
  group('offScriptRun', () {
    test('finds the stray run in the reply from #147', () {
      expect(offScriptRun(_garbledFeedback), 'աբգդե');
    });

    test('leaves the same reply alone once the word is Dutch again', () {
      expect(offScriptRun(_cleanFeedback), isNull);
    });

    test('leaves accented Dutch, French and German letters alone', () {
      expect(
        offScriptRun(
          'Je hebt één café-scenario overgeslagen: de coëfficiënt is nul, '
          'dus de naïeve aanpak faalt. Vergelijk met Müller en Ångström.',
        ),
        isNull,
      );
    });

    test('a lone Greek letter in a formula is not a run', () {
      expect(
        offScriptRun('De omtrek is 2 × π × r, met α als hoek en β als rest.'),
        isNull,
      );
    });

    // kMinOffScriptRun is 2: one stray character still reads as a symbol
    // someone may have meant, two read as half a token.
    test('one stray character is not a run', () {
      expect(
        offScriptRun(
          'Een lus herhaalt code zolang de voorwaarde waar blijft, en stopt '
          'zodra ze onwaar wordt. Дus.',
        ),
        isNull,
      );
    });

    test('two stray characters are a run', () {
      expect(
        offScriptRun(
          'Een lus herhaalt code zolang de voorwaarde waar blijft, en stopt '
          'zodra ze onwaar wordt. Дус.',
        ),
        'Дус',
      );
    });

    test('emoji, arrows and box drawing are not off-script', () {
      expect(
        offScriptRun('Goed gedaan! 🎉 De waarde gaat van 0 → 1 en dan ✓.'),
        isNull,
      );
    });

    test('a non-Latin string literal in a fenced block is left alone', () {
      expect(
        offScriptRun(
          'Python werkt met unicode, dus dit mag:\n'
          '```python\n'
          'print("你好, wereld")\n'
          '```\n'
          'De tekst tussen de aanhalingstekens is gewoon data.',
        ),
        isNull,
      );
    });

    test('a non-Latin string literal in an inline span is left alone', () {
      expect(
        offScriptRun(
          'De uitdrukking `print("Привет")` drukt de Russische begroeting '
          'af, precies zoals je ze getypt hebt in de editor hierboven.',
        ),
        isNull,
      );
    });

    test('a reply genuinely written in another script is not refused', () {
      // Nothing a re-send fixes, and the guard is not a language check:
      // Latin has to outnumber off-script kLatinDominanceRatio to one.
      expect(offScriptRun('你好，这是一个循环的例子。'), isNull);
      expect(offScriptRun('Loop: 这是一个循环的例子，用于说明。'), isNull);
    });

    test('empty and whitespace-only prose is clean', () {
      expect(offScriptRun(''), isNull);
      expect(offScriptRun('   \n\n'), isNull);
    });
  });

  group('offScriptRunInReply', () {
    test('scans the envelope TEXT section', () {
      expect(
        offScriptRunInReply(
          '<TEXT>$_garbledFeedback</TEXT>'
          '<META>{"type":"socratic_feedback"}</META>',
        ),
        'աբգդե',
      );
    });

    test('passes a clean envelope', () {
      expect(
        offScriptRunInReply(
          '<TEXT>$_cleanFeedback</TEXT>'
          '<META>{"type":"socratic_feedback"}</META>',
        ),
        isNull,
      );
    });

    test('META is out of the guard\'s reach by design', () {
      // META carries code snippets, where another script is legitimate, so
      // it is not scanned. Documented limit, not an oversight.
      expect(
        offScriptRunInReply(
          '<TEXT>Kies het juiste antwoord uit de lijst hieronder, en let '
          'goed op de volgorde van de bewerkingen.</TEXT>'
          '<META>{"type":"multiple_choice","options":["աբգդե","twee"]}'
          '</META>',
        ),
        isNull,
      );
    });

    test('a reply without an envelope is scanned whole', () {
      expect(offScriptRunInReply(_garbledFeedback), 'աբգդե');
    });
  });
}
