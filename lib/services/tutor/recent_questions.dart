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
/// A line is `type | loId | core`: the question type as the model names it
/// (`multiple_choice`, `complete_code`, …), the LO the question was asked
/// for (`-` when none), and the gist of the question — its prompt with the
/// code on one line — capped at [maxCoreLength] characters, some 50 tokens.
class RecentQuestions {
  RecentQuestions({this.capacity = defaultCapacity});

  /// How many questions the block names (#184).
  static const int defaultCapacity = 12;

  /// Cap on the gist of one question, in characters.
  static const int maxCoreLength = 160;

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
    return '${response.type} | $lo | ${_core(parts.$1, parts.$2)}';
  }

  /// The prompt on one line, followed by the code on one line (its lines
  /// joined with `; `) unless the prompt already quotes it.
  static String _core(String prompt, String code) {
    final text = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    final oneLineCode = code
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('; ');
    final quoted =
        oneLineCode.isEmpty ||
        text.contains(code.replaceAll(RegExp(r'\s+'), ' ').trim());
    final core = quoted
        ? text
        : [if (text.isNotEmpty) text, '`$oneLineCode`'].join(' ');
    if (core.length <= maxCoreLength) return core;
    return '${core.substring(0, maxCoreLength - 1).trimRight()}…';
  }
}
