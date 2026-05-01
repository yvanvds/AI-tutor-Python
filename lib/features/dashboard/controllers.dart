import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';

class Controllers extends StatelessWidget {
  const Controllers({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left-side buttons
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Run Code',
            onPressed: () async {
              final code = DataService.code.getText();
              await DataService.output.run(code);
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
              await DataService.output.stop();
            },
            color: Colors.red,
          ),
        ),

        const Spacer(),

        // Right-side buttons
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.question_mark),
            tooltip: 'Request Hint',
            onPressed: () async {
              DataService.chat.addMessage("Ik heb een hint nodig.");
              final code = DataService.code.getText();
              await DataService.tutor.requestHint(code);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.send),
            tooltip: 'Submit Code',
            onPressed: () async {
              DataService.chat.addMessage("Hier is mijn code.");
              final code = DataService.code.getText();
              await DataService.tutor.submitCode(code);
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
              DataService.chat.addMessage("Geef me een nieuwe oefening.");
              await DataService.tutor.requestExercise();
            },
            color: Colors.orange,
          ),
        ),
      ],
    );
  }
}
