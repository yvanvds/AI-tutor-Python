import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/goal/learning_objective.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';

/// Hard-coded envelope contract appended to every system prompt. Tells the
/// model to wrap student-facing markdown in `<TEXT>...</TEXT>` and the rest
/// of the structured payload (type + any code/options/quality/...) as JSON in
/// `<META>...</META>`. This lives outside teacher-editable instructions so
/// the transport contract can never be accidentally broken.
const String envelopeContract = '''
RESPONSE FORMAT — STRICT.
Every response must be wrapped in two sections, in this order:

<TEXT>
The student-facing markdown text (what would normally go in the "prompt" field). This is what the student reads. Do not put JSON or fenced code blocks containing JSON here. Plain markdown only.
</TEXT>
<META>
{"type":"<one of the response types>", ...all other structured fields except "prompt"}
</META>

Rules:
- Do not put any other content outside these two sections.
- Do not include the "prompt" field inside META — its value is the TEXT section.
- For status_summary the TEXT section may be the report itself; the rest of the stats stay in META.
- For multiple_choice keep "options" inside META.
- If the response would be of type "error", put the error message in TEXT and {"type":"error"} in META.
''';

/// The language a code stands for, spelled out for the model. Mirrors the
/// mapping in `grading/grade_justification.dart` (#99) so the tutor and the
/// grade justification never disagree about what `nl` means.
String _languageName(String languageCode) {
  switch (languageCode) {
    case 'nl':
      return 'Dutch (Nederlands)';
    default:
      return 'English';
  }
}

/// The output-language directive appended to every system prompt (#117).
///
/// The student picks a language in Options; until now that switched only the
/// interface, because the tutor's language was implicit in the
/// teacher-authored instruction bodies — which happen to be written in Dutch.
/// So this directive has to *override* the language those bodies are written
/// in, and it is appended last, after them, saying so in as many words.
///
/// It is scoped to student-facing prose only: META's JSON keys and enum
/// values, learning-objective ids and code are the machine half of the
/// contract (see `docs/LLM_CONTRACT.md`) and translating them would break
/// parsing and belief updates.
String languageDirective(String languageCode) {
  final language = _languageName(languageCode);
  return '''
OUTPUT LANGUAGE — STRICT. This overrides the language of every instruction above.
Write all student-facing text in $language: the entire TEXT section and every student-facing string inside META (questions, multiple-choice options, hints, feedback, explanations, status reports). The instructions above may themselves be written in another language; that is not a licence to answer in it.
Never translate the machine parts: META's JSON keys and enum values (including "type"), learning-objective ids, and the code, identifiers and API names in any snippet you show the student.
''';
}

class InstructionGenerator {
  Future<String> generateInstructions(
    ChatRequestType type, {
    required GoalSelectionState goalSelection,
    required List<Instruction> cachedInstructions,
    required Future<List<Instruction>> Function() fetchInstructions,
    required Future<List<Goal>> Function() fetchRootGoals,
    required String languageCode,
    List<LearningObjective> targetLOs = const [],
    List<({String subgoalId, LearningObjective lo})> goalScopeLOs = const [],
    Goal? subgoalOverride,
  }) async {
    final selectedRoot = goalSelection.selectedRoot;
    final selectedChild = goalSelection.selectedChild;
    if (selectedRoot == null || selectedChild == null) return '';

    final instructions = cachedInstructions.isNotEmpty
        ? cachedInstructions
        : await fetchInstructions();

    final typeString = _chatRequestTypeToString(type);

    String alwaysInclude = '';
    String typeSpecific = '';
    final root = goalSelection.preferredRoot ?? selectedRoot;
    // A warm-up review question (#102) is about an older subgoal of the same
    // root: `{subgoal}` and `{teachingTips}` then describe that one, so the
    // model writes and grades the question in its proper context.
    final subgoal =
        subgoalOverride ?? goalSelection.preferredChild ?? selectedChild;
    final alwaysIncludeSubgoal = subgoalOverride ?? selectedChild;
    for (final instruction in instructions) {
      if (instruction.id == typeString) {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            root,
            subgoal,
            targetLOs: targetLOs,
            goalScopeLOs: goalScopeLOs,
          );
          typeSpecific += '$processed\n';
        }
      } else if (instruction.id == 'alwaysInclude') {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            selectedRoot,
            alwaysIncludeSubgoal,
            targetLOs: targetLOs,
            goalScopeLOs: goalScopeLOs,
          );
          alwaysInclude += '$processed\n';
        }
      }
    }

    // The language directive goes last, after the teacher-authored bodies it
    // has to override (#117).
    return '$envelopeContract\n$alwaysInclude$typeSpecific'
        '\n${languageDirective(languageCode)}';
  }

  String _chatRequestTypeToString(ChatRequestType type) =>
      type.toString().split('.').last;

  String _replaceTags(
    String input,
    Goal goal,
    Goal subGoal, {
    required List<LearningObjective> targetLOs,
    required List<({String subgoalId, LearningObjective lo})> goalScopeLOs,
  }) {
    String output = input;
    final teachingTips = subGoal.teachingTips.join('\n');
    final replacements = {
      'goal': goal.title,
      'subgoal': subGoal.title,
      // `{teachingTips}` is the canonical name; `{suggestions}` is kept as
      // an alias for any teacher-authored instruction docs that haven't been
      // updated yet.
      'teachingTips': teachingTips,
      'suggestions': teachingTips,
      'targetLOs': _renderTargetLOs(targetLOs),
      'goalScopeLOs': _renderGoalScopeLOs(goalScopeLOs),
      // `{known concepts}` no longer expands to a real list — the LO model
      // replaces concept-scope fencing. Stale instruction docs that still
      // reference it resolve to an empty string.
      'known concepts': '',
    };
    for (final entry in replacements.entries) {
      final pattern = RegExp(
        r'\{\s*' + entry.key + r'\s*\}',
        caseSensitive: false,
      );
      output = output.replaceAll(pattern, entry.value);
    }
    return output;
  }

  String _renderTargetLOs(List<LearningObjective> los) {
    if (los.isEmpty) return '';
    return los
        .map((lo) => '- (${lo.kind.name}) ${lo.id}: ${lo.statement}')
        .join('\n');
  }

  String _renderGoalScopeLOs(
    List<({String subgoalId, LearningObjective lo})> entries,
  ) {
    if (entries.isEmpty) return '';
    return entries
        .map(
          (e) =>
              '- [${e.subgoalId}] (${e.lo.kind.name}) ${e.lo.id}: ${e.lo.statement}',
        )
        .join('\n');
  }
}
