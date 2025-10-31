import 'package:flutter/material.dart';

class Controllers extends StatelessWidget {
  const Controllers({
    super.key,
    required this.onRunPressed,
    required this.onStopPressed,
    required this.onHintPressed,
    required this.onSubmitPressed,
    required this.onExercisePressed,
  });

  final VoidCallback onRunPressed;
  final VoidCallback onStopPressed;
  final VoidCallback onHintPressed;
  final VoidCallback onSubmitPressed;
  final VoidCallback onExercisePressed;

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
            onPressed: onRunPressed,
            color: Colors.green,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.stop),
            tooltip: 'Stop Code',
            onPressed: onStopPressed,
            color: Colors.red,
          ),
        ),

        // Spacer pushes the next buttons to the right
        const Spacer(),

        // Right-side buttons
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Request Hint',
            onPressed: onHintPressed,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.send),
            tooltip: 'Submit Code',
            onPressed: onSubmitPressed,
            color: Colors.blue,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.school),
            tooltip: 'Request Exercise',
            onPressed: onExercisePressed,
            color: Colors.orange,
          ),
        ),
      ],
    );
  }
}
