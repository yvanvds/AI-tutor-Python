import 'package:flutter/material.dart';

class AddInput extends StatefulWidget {
  const AddInput({super.key, required this.hint, required this.onSubmit});
  final String hint;
  final Future<void> Function(String text) onSubmit;

  @override
  State<AddInput> createState() => _AddInputState();
}

class _AddInputState extends State<AddInput> {
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(t);
      _c.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onSubmitted: _handleSubmit,
      decoration: InputDecoration(
        hintText: widget.hint,
        suffixIcon:
            _busy
                ? const Padding(
                  padding: EdgeInsets.all(10.0),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                : const Icon(Icons.keyboard_return),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
