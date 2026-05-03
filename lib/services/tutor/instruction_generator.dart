import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
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

class InstructionGenerator {
  Future<String> generateInstructions(
    ChatRequestType type, {
    required GoalSelectionState goalSelection,
    required List<Instruction> cachedInstructions,
    required Future<List<Instruction>> Function() fetchInstructions,
    required Future<List<Goal>> Function() fetchRootGoals,
  }) async {
    final selectedRoot = goalSelection.selectedRoot;
    final selectedChild = goalSelection.selectedChild;
    if (selectedRoot == null || selectedChild == null) return '';

    final instructions = cachedInstructions.isNotEmpty
        ? cachedInstructions
        : await fetchInstructions();

    final targetGoal = goalSelection.preferredRoot ?? selectedRoot;
    final knownConcepts = await _getMasteredConcepts(
      targetGoal,
      cachedRoots: goalSelection.cachedRoots,
      fetchRootGoals: fetchRootGoals,
    );

    final typeString = _chatRequestTypeToString(type);

    String alwaysInclude = '';
    String typeSpecific = '';
    for (final instruction in instructions) {
      if (instruction.id == typeString) {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            goalSelection.preferredRoot ?? selectedRoot,
            goalSelection.preferredChild ?? selectedChild,
            knownConcepts,
          );
          typeSpecific += '$processed\n';
        }
      } else if (instruction.id == 'alwaysInclude') {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            selectedRoot,
            selectedChild,
            knownConcepts,
          );
          alwaysInclude += '$processed\n';
        }
      }
    }

    return '$envelopeContract\n$alwaysInclude$typeSpecific';
  }

  String _chatRequestTypeToString(ChatRequestType type) =>
      type.toString().split('.').last;

  String _replaceTags(
    String input,
    Goal goal,
    Goal subGoal,
    List<String> knownConcepts,
  ) {
    String output = input;
    final replacements = {
      'goal': goal.title,
      'subgoal': subGoal.title,
      'suggestions': subGoal.suggestions.join('\n'),
      'known concepts': knownConcepts.join('\n'),
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

  Future<List<String>> _getMasteredConcepts(
    Goal targetGoal, {
    required List<Goal> cachedRoots,
    required Future<List<Goal>> Function() fetchRootGoals,
  }) async {
    final rootGoals = cachedRoots.isNotEmpty
        ? cachedRoots
        : await fetchRootGoals();

    final masteredConcepts = <String>{};
    for (final goal in rootGoals) {
      if (goal.order >= targetGoal.order || goal.id == targetGoal.id) break;
      masteredConcepts.addAll(goal.knownConcepts);
    }
    return masteredConcepts.toList();
  }
}
