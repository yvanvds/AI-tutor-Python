import 'package:ai_tutor_python/features/chat/composer_shell_widget.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ComposerContinueWidget extends StatelessWidget {
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double? sigmaX;
  final double? sigmaY;
  final EdgeInsetsGeometry? padding;
  final bool? handleSafeArea;
  final Color? backgroundColor;

  const ComposerContinueWidget({
    super.key,
    this.left = 0,
    this.right = 0,
    this.top,
    this.bottom = 0,
    this.sigmaX = 20,
    this.sigmaY = 20,
    this.padding = const EdgeInsets.all(8.0),
    this.handleSafeArea = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return ComposerShell(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      sigmaX: sigmaX,
      sigmaY: sigmaY,
      padding: padding,
      handleSafeArea: handleSafeArea,
      backgroundColor: backgroundColor,
      child: Consumer(
        builder: (context, ref, _) => ElevatedButton.icon(
          onPressed: () {
            ref.read(tutorServiceProvider.notifier).moveToFollowUp();
          },
          icon: const Icon(Icons.next_plan),
          label: const Text('Continue'),
        ),
      ),
    );
  }
}
