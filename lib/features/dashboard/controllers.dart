import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';

class Controllers extends StatelessWidget {
  const Controllers({
    super.key,

    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  final VoidCallback onPreviousPressed;
  final VoidCallback onNextPressed;

  @override
  Widget build(BuildContext context) {
    // final canPrev = ref.watch(timeLineProvider.select((t) => t.canGoPrev));
    // final canNext = ref.watch(timeLineProvider.select((t) => t.canGoNext));

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

        // middle buttons
        // Padding(
        //   padding: const EdgeInsets.all(8.0),
        //   child: OutlinedButton(
        //     onPressed: canPrev ? onPreviousPressed : null,
        //     child: const Text('Previous Code'),
        //   ),
        // ),
        // Padding(
        //   padding: const EdgeInsets.all(8.0),
        //   child: OutlinedButton(
        //     onPressed: canNext ? onNextPressed : null,
        //     child: const Text('Next Code'),
        //   ),
        // ),

        // Spacer pushes the next buttons to the right
        const Spacer(),

        // Right-side buttons
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.question_mark),
            tooltip: 'Request Hint',
            onPressed: () async {
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
              await DataService.tutor.requestExercise();
            },
            color: Colors.orange,
          ),
        ),
      ],
    );
  }
}
