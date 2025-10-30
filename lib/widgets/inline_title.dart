import 'package:flutter/material.dart';
import '../core/debounce.dart';

typedef TitleChanged = Future<void> Function(String newTitle);

class InlineTitle extends StatefulWidget {
  const InlineTitle({
    super.key,
    required this.initial,
    required this.onChangedDebounced,
    this.placeholder = 'Untitled',
  });

  final String initial;
  final TitleChanged onChangedDebounced;
  final String placeholder;

  @override
  State<InlineTitle> createState() => _InlineTitleState();
}

class _InlineTitleState extends State<InlineTitle> {
  late final TextEditingController _c;
  late final Debouncer _debouncer;
  String _lastSaved = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
    _lastSaved = widget.initial;
    _debouncer = Debouncer(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _c.dispose();
    super.dispose();
  }

  void _scheduleSave(String text) {
    _debouncer.run(() async {
      final trimmed = text.trim();
      if (trimmed == _lastSaved) return;
      setState(() => _busy = true);
      try {
        await widget.onChangedDebounced(
          trimmed.isEmpty ? widget.placeholder : trimmed,
        );
        _lastSaved = trimmed;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        TextField(
          controller: _c,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
          ),
          onChanged: _scheduleSave,
        ),
        if (_busy)
          const Positioned(
            right: 0,
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}
