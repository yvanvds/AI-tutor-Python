import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/instructions/instructions_provider.dart';
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
    final instructions = await ref.read(instructionsListProviderFuture.future);

    final typeString = _chatRequestTypeToString(type);

    String output = "";
    for (var instruction in instructions) {
      if (instruction.id == typeString) {
        for (var content in instruction.sections.entries) {
          final processed = _replaceTags(content.value, goal, subGoal);
          output += "$processed\n";
        }
      }
    }

    return output;
  }

  String _chatRequestTypeToString(ChatRequestType type) {
    return type.toString().split('.').last;
  }

  String _replaceTags(String input, Goal goal, Goal subGoal) {
    String output = input;

    Map<String, String> replacements = {
      'goal': goal.title,
      'subgoal': subGoal.title,
      'suggestions': subGoal.suggestions.join("\n"),
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
}
