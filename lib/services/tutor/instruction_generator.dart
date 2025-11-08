import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/instructions/instruction.dart';

class InstructionGenerator {
  late final Stream<List<Instruction>> instructionsStream;

  Future<String> generateInstructions(ChatRequestType type) async {
    if (DataService.goals.selectedRootGoal.value == null ||
        DataService.goals.selectedChildGoal.value == null) {
      return "";
    }

    // Implementation for generating instruction using OpenAI or other services
    final instructions = await DataService.instructions.getAll();

    final targetGoal =
        DataService.goals.preferredRootGoal.value ??
        DataService.goals.selectedRootGoal.value!;

    final knownConcepts = await _getMasteredConcepts(targetGoal);

    final typeString = _chatRequestTypeToString(type);

    String output = "";
    String alwaysInclude = "";
    for (var instruction in instructions) {
      if (instruction.id == typeString) {
        for (var content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            DataService.goals.preferredRootGoal.value ??
                DataService.goals.selectedRootGoal.value!,
            DataService.goals.preferredChildGoal.value ??
                DataService.goals.selectedChildGoal.value!,
            knownConcepts,
          );
          output += "$processed\n";
        }
      } else if (instruction.id == "alwaysInclude") {
        // always include this, but add it to another var, because it should come at the end
        for (var content in instruction.sections.entries) {
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

    // add the stuff we always want to include
    output += alwaysInclude;
    return output;
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
    // Ordered by `order`
    final rootGoals = await DataService.goals.getRootGoalsOnce();

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
