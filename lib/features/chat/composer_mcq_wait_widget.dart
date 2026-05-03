import 'package:ai_tutor_python/features/chat/composer_shell_widget.dart';
import 'package:flutter/material.dart';

class ComposerMcqWaitWidget extends StatelessWidget {
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double? sigmaX;
  final double? sigmaY;
  final EdgeInsetsGeometry? padding;
  final bool? handleSafeArea;
  final Color? backgroundColor;

  const ComposerMcqWaitWidget({
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Klik op een antwoord hierboven',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
