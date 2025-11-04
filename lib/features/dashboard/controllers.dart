import 'package:ai_tutor_python/data/session/code_timeline_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class Controllers extends ConsumerWidget {
  const Controllers({
    super.key,
    required this.onRunPressed,
    required this.onStopPressed,
    required this.onHintPressed,
    required this.onSubmitPressed,
    required this.onExercisePressed,
    required this.onPreviousPressed,
    required this.onNextPressed,
  });

  final VoidCallback onRunPressed;
  final VoidCallback onStopPressed;
  final VoidCallback onHintPressed;
  final VoidCallback onSubmitPressed;
  final VoidCallback onExercisePressed;
  final VoidCallback onPreviousPressed;
  final VoidCallback onNextPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

        const Spacer(),

        // middle buttons
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: OutlinedButton(
            onPressed: ref.watch(canGoPrevProvider) ? onPreviousPressed : null,
            child: const Text('Previous Code'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: OutlinedButton(
            onPressed: ref.watch(canGoNextProvider) ? onNextPressed : null,
            child: const Text('Next Code'),
          ),
        ),

        // Spacer pushes the next buttons to the right
        const Spacer(),

        // Right-side buttons
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton.outlined(
            icon: const Icon(Icons.question_mark),
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
