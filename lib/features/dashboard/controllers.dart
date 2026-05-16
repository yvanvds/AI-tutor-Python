import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Controllers extends ConsumerWidget {
  const Controllers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Run Code',
            onPressed: () async {
              final code = ref.read(codeServiceProvider(SessionMode.practice)).getText();
              await ref.read(outputServiceProvider).run(code);
            },
            color: Colors.green,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.stop),
            tooltip: 'Stop Code',
            onPressed: () async {
              await ref.read(outputServiceProvider).stop();
            },
            color: Colors.red,
          ),
        ),

        const Spacer(),

        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.question_mark),
            tooltip: 'Request Hint',
            onPressed: () async {
              ref.read(chatServiceProvider).addMessage("Ik heb een hint nodig.");
              final code = ref.read(codeServiceProvider(SessionMode.practice)).getText();
              await ref.read(tutorServiceProvider.notifier).requestHint(code);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.send),
            tooltip: 'Submit Code',
            onPressed: () async {
              ref.read(chatServiceProvider).addMessage("Hier is mijn code.");
              final code = ref.read(codeServiceProvider(SessionMode.practice)).getText();
              await ref.read(tutorServiceProvider.notifier).submitCode(code);
            },
            color: Colors.blue,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.school),
            tooltip: 'Request Exercise',
            onPressed: () async {
              ref
                  .read(chatServiceProvider)
                  .addMessage("Geef me een nieuwe oefening.");
              await ref.read(tutorServiceProvider.notifier).requestExercise();
            },
            color: Colors.orange,
          ),
        ),
      ],
    );
  }
}
