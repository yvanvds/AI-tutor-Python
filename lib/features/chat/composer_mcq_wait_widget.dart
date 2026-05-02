import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:provider/provider.dart';

/// Composer shown while a multiple-choice question is awaiting a tap.
/// Disables typing so the student must click one of the option buttons.
class ComposerMcqWaitWidget extends StatefulWidget {
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
  State<ComposerMcqWaitWidget> createState() => _ComposerMcqWaitWidgetState();
}

class _ComposerMcqWaitWidgetState extends State<ComposerMcqWaitWidget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant ComposerMcqWaitWidget oldWidget) {
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
        widget.handleSafeArea == true ? height - bottomSafeArea : height,
      );
    }
  }
}
