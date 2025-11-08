import 'dart:ui';

import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:provider/provider.dart';

/// The message composer widget positioned at the bottom of the chat screen.
///
/// Includes a text input field, an optional attachment button, and a send button.
class ComposerContinueWidget extends StatefulWidget {
  /// Optional left position.
  final double? left;

  /// Optional right position.
  final double? right;

  /// Optional top position.
  final double? top;

  /// Optional bottom position.
  final double? bottom;

  /// Optional X blur value for the background (if using glassmorphism).
  final double? sigmaX;

  /// Optional Y blur value for the background (if using glassmorphism).
  final double? sigmaY;

  /// Padding around the composer content.
  final EdgeInsetsGeometry? padding;

  /// Whether to adjust padding for the bottom safe area.
  final bool? handleSafeArea;

  /// Background color of the composer container.
  final Color? backgroundColor;

  /// Creates a message composer widget.
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
  State<ComposerContinueWidget> createState() => _ComposerContinueWidgetState();
}

class _ComposerContinueWidgetState extends State<ComposerContinueWidget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant ComposerContinueWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = widget.handleSafeArea == true
        ? MediaQuery.of(context).padding.bottom
        : 0.0;

    final sigmaX = widget.sigmaX ?? 0;
    final sigmaY = widget.sigmaY ?? 0;
    final shouldUseBackdropFilter = sigmaX > 0 || sigmaY > 0;

    final content = Container(
      key: _key,
      color: Theme.of(context).canvasColor,
      child: Column(
        children: [
          Padding(
            padding: widget.handleSafeArea == true
                ? (widget.padding?.add(
                        EdgeInsets.only(bottom: bottomSafeArea),
                      ) ??
                      EdgeInsets.only(bottom: bottomSafeArea))
                : (widget.padding ?? EdgeInsets.zero),
            child: ElevatedButton.icon(
              onPressed: () {
                DataService.tutor.moveToFollowUp();
              },
              icon: const Icon(Icons.next_plan),
              label: Text('Continue'),
            ),
          ),
        ],
      ),
    );

    return Positioned(
      left: widget.left,
      right: widget.right,
      top: widget.top,
      bottom: widget.bottom,
      child: ClipRect(
        child: shouldUseBackdropFilter
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
                child: content,
              )
            : content,
      ),
    );
  }

  void _measure() {
    if (!mounted) return;

    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      final bottomSafeArea = MediaQuery.of(context).padding.bottom;

      context.read<ComposerHeightNotifier>().setHeight(
        // only set real height of the composer, ignoring safe area
        widget.handleSafeArea == true ? height - bottomSafeArea : height,
      );
    }
  }
}
