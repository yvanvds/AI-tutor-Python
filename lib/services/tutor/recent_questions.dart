import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/explain_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/write_code.dart';

/// The questions asked most recently this session, one line each (#184).
///
/// Question generation goes out without conversation history
/// (`PreviousInputs.newSession`), so this list is what the model knows
/// about what it asked before: it travels in the request's
/// `recent_questions` block, and the teacher-authored question
/// instructions point at that block for "do not repeat yourself".
///
/// A line is `type | loId | code | prompt` (#244): the question type as the
/// model names it (`multiple_choice`, `complete_code`, …), the LO the
/// question was asked for (`-` when none), the code shown with it as its
/// shape ([codeShape], capped at [maxCodeLength]; `-` when there is none),
/// and its prompt on one line, capped at [maxPromptLength] — or at
/// [maxPromptOnlyLength] when there is no code.
///
/// The code comes first and without its texts because that is where an
/// exercise's structure is. The line used to be the prompt followed by the
/// code, cut at 160 characters, and the prompt — mostly the story around
/// the exercise — usually filled those: the model saw a new story and no
/// code, so the same exercise with other names passed as a new one.
class RecentQuestions {
  RecentQuestions({this.capacity = defaultCapacity});

  /// How many questions the block names (#184).
  static const int defaultCapacity = 12;

  /// Cap on the shape of a question's code, in characters (#244).
  static const int maxCodeLength = 200;

  /// Cap on the prompt of a question with code, in characters (#244).
  static const int maxPromptLength = 100;

  /// Cap on the prompt of a question without code — a `write_code` or a
  /// socratic question, whose prompt is all there is.
  static const int maxPromptOnlyLength = 160;

  final int capacity;
  final List<String> _lines = <String>[];

  /// Oldest first.
  List<String> get lines => List.unmodifiable(_lines);

  /// Remembers [response] if it is a question, as asked for [loId]; the
  /// oldest line goes once there are more than [capacity]. Anything else —
  /// a grade, a hint, an error — is not a question and is ignored. Returns
  /// whether a line was added.
  bool add(ChatResponse response, {String? loId}) {
    final line = describe(response, loId: loId);
    if (line == null) return false;
    _lines.add(line);
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
    return true;
  }

  void clear() => _lines.clear();

  /// The line for [response], or `null` when it is not a question.
  static String? describe(ChatResponse response, {String? loId}) {
    final (String prompt, String code)? parts = switch (response) {
      MultipleChoice(:final prompt, :final code) => (prompt, code),
      CompleteCode(:final prompt, :final code) => (prompt, code),
      ExplainCode(:final prompt, :final code) => (prompt, code),
      WriteCode(:final prompt) => (prompt, ''),
      SocraticQuestion(:final prompt) => (prompt, ''),
      _ => null,
    };
    if (parts == null) return null;
    final lo = (loId == null || loId.isEmpty) ? '-' : loId;
    final code = _cap(codeShape(parts.$2), maxCodeLength);
    final prompt = _cap(
      parts.$1.replaceAll(RegExp(r'\s+'), ' ').trim(),
      code.isEmpty ? maxPromptOnlyLength : maxPromptLength,
    );
    return '${response.type} | $lo | ${_orDash(code)} | ${_orDash(prompt)}';
  }

  /// The shape of [code], the part of a question that shows what the
  /// exercise is (#244): on one line, its lines joined with `; `, every
  /// string literal as `"…"` and comments left out. Names and numbers stay —
  /// they are short, and an index or a bound can be the point — but the
  /// texts, which are what a new story around the same exercise changes,
  /// go. Empty when nothing but comments and blank lines is left.
  static String codeShape(String code) {
    final out = StringBuffer();
    var i = 0;
    while (i < code.length) {
      final c = code[i];
      if (c == '#') {
        while (i < code.length && code[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        final quote = code.startsWith(c * 3, i) ? c * 3 : c;
        var j = i + quote.length;
        while (j < code.length && !code.startsWith(quote, j)) {
          if (code[j] == r'\') {
            j += 2;
            continue;
          }
          // An unclosed one-line string ends at the end of its line.
          if (quote.length == 1 && code[j] == '\n') break;
          j++;
        }
        out.write('"…"');
        i = j < code.length && code[j] == '\n' ? j : j + quote.length;
        continue;
      }
      out.write(c);
      i++;
    }
    return out
        .toString()
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .join('; ');
  }

  static String _cap(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max - 1).trimRight()}…';
  }

  static String _orDash(String text) => text.isEmpty ? '-' : text;
}
