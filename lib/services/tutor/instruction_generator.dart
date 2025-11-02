import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/instructions/instructions_provider.dart';
import 'package:ai_tutor_python/data/progress/progress_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class InstructionGenerator {
  InstructionGenerator({required this.ref});
  final Ref ref;

  Future<String> generateInstructions(
    ChatRequestType type,
    Goal goal,
    Goal subGoal,
  ) async {
    // Implementation for generating instruction using OpenAI or other services
    final repo = ref.read(instructionsRepositoryProvider);
    final instructions = await repo.getAll();

    // get local goal data to make sure it is up to date
    final goalsRepo = ref.read(goalsRepositoryProvider);
    final localGoal = await goalsRepo.streamGoal(goal.id).first;
    final localSubGoal = await goalsRepo.streamGoal(subGoal.id).first;

    final knownConcepts = await _getMasteredConcepts();

    final typeString = _chatRequestTypeToString(type);

    String output = "";
    String alwaysInclude = "";
    for (var instruction in instructions) {
      if (instruction.id == typeString) {
        for (var content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            localGoal ?? goal,
            localSubGoal ?? subGoal,
            knownConcepts,
          );
          output += "$processed\n";
        }
      } else if (instruction.id == "alwaysInclude") {
        // always include this, but add it to another var, because it should come at the end
        for (var content in instruction.sections.entries) {
          final processed = _replaceTags(
            content.value,
            goal,
            subGoal,
            knownConcepts,
          );
          alwaysInclude += "$processed\n";
        }
      }
    }

    // add the stuff we always want to include
    output += alwaysInclude;
    print("Our instructions:");
    print(output);
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
      'knownConcepts': knownConcepts.join("\n"),
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

  Future<List<String>> _getMasteredConcepts() async {
    // Retrieve all root goals
    final rootGoals = await ref.read(rootGoalsProviderFuture.future);
    // Retrieve all progress records
    final progressList = await ref.read(progressListProviderFuture.future);

    // Create a map for quick lookup of progress by goalID
    final progressMap = {for (var p in progressList) p.goalID: p.progress};

    final Set<String> masteredConcepts = {};

    for (final goal in rootGoals) {
      final goalProgress = progressMap[goal.id] ?? 0.0;
      if (goalProgress >= 1.0) {
        masteredConcepts.addAll(goal.knownConcepts);
      }
    }

    return masteredConcepts.toList();
  }
}
