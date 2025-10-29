import 'package:flutter/material.dart';

class Controllers extends StatelessWidget {
  const Controllers({
    super.key,
    required this.onRunPressed,
    required this.onStopPressed,
  });

  final VoidCallback onRunPressed;
  final VoidCallback onStopPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
      ],
    );
  }
}
