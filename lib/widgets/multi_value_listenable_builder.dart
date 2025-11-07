import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MultiValueListenableBuilder extends StatefulWidget {
  const MultiValueListenableBuilder({
    super.key,
    required this.listenables,
    required this.builder,
  });

  final List<ValueListenable<dynamic>> listenables;
  final Widget Function(BuildContext, List<dynamic>) builder;

  @override
  State<MultiValueListenableBuilder> createState() =>
      _MultiValueListenableBuilderState();
}

class _MultiValueListenableBuilderState
    extends State<MultiValueListenableBuilder> {
  @override
  void initState() {
    super.initState();
    for (final l in widget.listenables) {
      l.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    for (final l in widget.listenables) {
      l.removeListener(_onChange);
    }
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final values = widget.listenables.map((l) => l.value).toList();
    return widget.builder(context, values);
  }
}
