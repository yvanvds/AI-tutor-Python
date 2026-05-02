import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
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
  late final Stream<List<Instruction>> instructionsStream;

  Future<String> generateInstructions(ChatRequestType type) async {
    if (DataService.goals.selectedRootGoal.value == null ||
        DataService.goals.selectedChildGoal.value == null) {
      return "";
    }

    final instructions = await _readInstructions();

    final targetGoal =
        DataService.goals.preferredRootGoal.value ??
        DataService.goals.selectedRootGoal.value!;

    final knownConcepts = await _getMasteredConcepts(targetGoal);

    final typeString = _chatRequestTypeToString(type);

    // Build sections separately so we can order them deliberately:
    // 1. envelope contract (always identical — best cache prefix)
    // 2. alwaysInclude (stable across request types — second-best cache prefix)
    // 3. type-specific block (varies by request type)
    String alwaysInclude = "";
    String typeSpecific = "";
    for (final instruction in instructions) {
      if (instruction.id == typeString) {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            DataService.goals.preferredRootGoal.value ??
                DataService.goals.selectedRootGoal.value!,
            DataService.goals.preferredChildGoal.value ??
                DataService.goals.selectedChildGoal.value!,
            knownConcepts,
          );
          typeSpecific += "$processed\n";
        }
      } else if (instruction.id == "alwaysInclude") {
        for (final content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            DataService.goals.selectedRootGoal.value!,
            DataService.goals.selectedChildGoal.value!,
            knownConcepts,
          );
          alwaysInclude += "$processed\n";
        }
      }
    }

    return "$envelopeContract\n$alwaysInclude$typeSpecific";
  }

  Future<List<Instruction>> _readInstructions() async {
    final cached = DataService.instructions.cachedAll.value;
    if (cached.isNotEmpty) return cached;
    return DataService.instructions.getAll();
  }

  String _chatRequestTypeToString(ChatRequestType type) {
    return type.toString().split('.').last;
  }

  String _replaceTags(
    String input,
    Goal goal,
    Goal subGoal,
    List<String> knownConcepts,
  ) {
    String output = input;

    Map<String, String> replacements = {
      'goal': goal.title,
      'subgoal': subGoal.title,
      'suggestions': subGoal.suggestions.join("\n"),
      'known concepts': knownConcepts.join("\n"),
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

  Future<List<String>> _getMasteredConcepts(Goal targetGoal) async {
    // Ordered by `order`. Prefer the cached watcher snapshot to avoid a
    // Cosmos round-trip on every AI request.
    final cached = DataService.goals.cachedRoots.value;
    final rootGoals = cached.isNotEmpty
        ? cached
        : await DataService.goals.getRootGoalsOnce();

    final masteredConcepts = <String>{};

    // Collect concepts from all root goals that come *before* the target goal.
    for (final goal in rootGoals) {
      // Stop once we reach (or pass) the target position.
      if (goal.order >= targetGoal.order || goal.id == targetGoal.id) {
        break;
      }
      masteredConcepts.addAll(goal.knownConcepts);
    }

    return masteredConcepts.toList();
  }
}
