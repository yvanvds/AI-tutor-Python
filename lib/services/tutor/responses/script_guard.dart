// Refuses a reply whose prose carries a run of characters from an alphabet
// the tutor does not write in (#147).
//
// Bug #147: a grading reply came back as normal Dutch with one word replaced
// by a short run of non-Latin lookalikes — "Niet **<glyphs>**: de voorwaarde
// wordt `True` ...". It was seen while a nano-class model was set as the
// per-device override, and the raw completion is where the glyphs come from:
// nothing on the client touches the characters. The streaming path decodes
// with `utf8.decoder`, so a multi-byte character split across chunks is not
// it; `EnvelopeAssembler` slices on tag boundaries only; `GptMarkdown`
// rendered the rest of the same reply, code pills included, correctly. Small
// models emitting a stray token from another script in non-English text is a
// known failure mode of the model, not of this app.
//
// So the app cannot fix the cause. What it can do is not put the result in
// front of a student: the reply is refused the way a truncated one is
// (`ChatNoticeKind.replyTruncated`, #7) and `TutorService`'s one automatic
// re-send asks again. A stray token is a sampling accident, so the second
// completion is normally clean.
//
// The rule is deliberately narrow, because a false positive costs a round
// trip and a pill:
//
//   - Only *prose* is looked at. Fenced blocks and inline code spans are cut
//     out first: `print("你好")` is a legitimate Python string, and a lesson
//     about encodings is exactly where one would appear.
//   - Only a run of [kMinOffScriptRun] adjacent off-script characters counts.
//     A lone `π` or `α` in a formula is left alone; garbage arrives in
//     clumps because a token is several characters wide.
//   - The reply must be overwhelmingly Latin — Latin letters outnumbering
//     off-script ones [kLatinDominanceRatio] to one. A reply genuinely
//     written in another script is a different problem (and not one a
//     re-send fixes), so it is not touched here.
//
// Known limits, both accepted: META's own student-facing strings (MCQ
// options, a follow-up question) are not scanned, because META also carries
// code snippets where another script is legitimate; and prose that quotes
// non-Latin characters on purpose ("in het Chinees is 你好 een begroeting")
// trips the guard and costs one re-send.

import 'package:ai_tutor_python/services/tutor/responses/envelope_assembler.dart';

/// Shortest clump of adjacent off-script characters that reads as garbage
/// rather than as a symbol someone meant to type.
const int kMinOffScriptRun = 2;

/// How far Latin letters must outnumber off-script ones before a run is read
/// as a stray token in a Latin-script reply.
const int kLatinDominanceRatio = 10;

/// The off-script run in [rawReply]'s student-visible prose, or `null` when
/// there is none. [rawReply] is the whole assistant message; only the
/// envelope's `<TEXT>` section is examined (the whole message when the model
/// sent no envelope).
String? offScriptRunInReply(String rawReply) {
  final assembler = EnvelopeAssembler()
    ..add(rawReply)
    ..close();
  return offScriptRun(assembler.sawOpenTag ? assembler.text : rawReply);
}

/// The longest off-script run in [prose], or `null` when [prose] reads as an
/// ordinary Latin-script reply. Pure; see the file header for the rule.
String? offScriptRun(String prose) {
  final text = _withoutCode(prose);

  var latin = 0;
  var offScript = 0;
  String? longest;
  final run = StringBuffer();
  var runLength = 0;

  void closeRun() {
    run.clear();
    runLength = 0;
  }

  for (final rune in text.runes) {
    if (_isLatinLetter(rune)) {
      latin++;
      closeRun();
      continue;
    }
    if (_isOffScriptLetter(rune)) {
      offScript++;
      run.writeCharCode(rune);
      runLength++;
      if (runLength >= kMinOffScriptRun &&
          (longest == null || runLength > longest.runes.length)) {
        longest = run.toString();
      }
      continue;
    }
    // Digits, whitespace, punctuation, arrows, emoji: neither Latin nor
    // off-script, and they end a run.
    closeRun();
  }

  if (longest == null) return null;
  if (latin < kLatinDominanceRatio * offScript) return null;
  return longest;
}

final RegExp _fencedBlock = RegExp(r'```[\s\S]*?```');
final RegExp _inlineSpan = RegExp(r'`[^`\n]*`');

String _withoutCode(String s) =>
    s.replaceAll(_fencedBlock, ' ').replaceAll(_inlineSpan, ' ');

/// A letter of the script the tutor's replies are written in: ASCII plus the
/// accented Latin ranges Dutch, French and the other Latin-script languages
/// draw on. `×` and `÷` sit inside the Latin-1 block but are symbols.
bool _isLatinLetter(int rune) {
  if (rune >= 0x41 && rune <= 0x5A) return true; // A-Z
  if (rune >= 0x61 && rune <= 0x7A) return true; // a-z
  if (rune == 0x00D7 || rune == 0x00F7) return false; // × ÷
  if (rune >= 0x00C0 && rune <= 0x024F) return true; // Latin-1 sup + ext A/B
  if (rune >= 0x1E00 && rune <= 0x1EFF) return true; // Latin ext additional
  return false;
}

/// Ranges of the scripts a reply here is never written in. Broad on purpose:
/// #147's glyphs were only ever described as "Armenian/Cyrillic-ish", so the
/// exact code points are unknown and any alphabet that is not Latin is
/// equally out of place. Greek is in the list because the lookalike letters
/// (ο, ν, α) live there; the [kMinOffScriptRun] rule is what keeps a real
/// `π` out of trouble.
const List<List<int>> _offScriptRanges = [
  [0x0370, 0x03FF], // Greek and Coptic
  [0x0400, 0x052F], // Cyrillic + supplement
  [0x0530, 0x058F], // Armenian
  [0x0590, 0x05FF], // Hebrew
  [0x0600, 0x06FF], // Arabic
  [0x0700, 0x074F], // Syriac
  [0x0750, 0x077F], // Arabic supplement
  [0x0780, 0x07BF], // Thaana
  [0x0900, 0x0D7F], // Devanagari … Malayalam
  [0x0D80, 0x0DFF], // Sinhala
  [0x0E00, 0x0E7F], // Thai
  [0x0E80, 0x0EFF], // Lao
  [0x0F00, 0x0FFF], // Tibetan
  [0x1000, 0x109F], // Myanmar
  [0x10A0, 0x10FF], // Georgian
  [0x1100, 0x11FF], // Hangul jamo
  [0x1200, 0x137F], // Ethiopic
  [0x13A0, 0x13FF], // Cherokee
  [0x1780, 0x17FF], // Khmer
  [0x1800, 0x18AF], // Mongolian
  [0x2E80, 0x2FDF], // CJK radicals
  [0x3040, 0x30FF], // Hiragana, Katakana
  [0x3100, 0x312F], // Bopomofo
  [0x3130, 0x318F], // Hangul compatibility jamo
  [0x3400, 0x4DBF], // CJK extension A
  [0x4E00, 0x9FFF], // CJK unified ideographs
  [0xA000, 0xA4CF], // Yi
  [0xAC00, 0xD7AF], // Hangul syllables
  [0xF900, 0xFAFF], // CJK compatibility ideographs
  [0xFB1D, 0xFDFF], // Hebrew + Arabic presentation forms A
  [0xFE70, 0xFEFF], // Arabic presentation forms B
  [0xFF66, 0xFF9F], // Halfwidth katakana
];

bool _isOffScriptLetter(int rune) {
  for (final range in _offScriptRanges) {
    if (rune < range[0]) return false; // ranges are ascending
    if (rune <= range[1]) return true;
  }
  return false;
}
