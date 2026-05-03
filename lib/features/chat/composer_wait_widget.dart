import 'package:ai_tutor_python/features/chat/composer_shell_widget.dart';
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class ComposerWaitWidget extends StatelessWidget {
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double? sigmaX;
  final double? sigmaY;
  final EdgeInsetsGeometry? padding;
  final bool? handleSafeArea;
  final Color? backgroundColor;

  const ComposerWaitWidget({
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
      child: LoadingAnimationWidget.staggeredDotsWave(
        color: Colors.blue,
        size: 36,
      ),
    );
  }
}
