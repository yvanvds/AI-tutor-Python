import 'package:flutter/material.dart';

/// Editor for a list of free-form text entries (e.g. a subgoal's teaching
/// tips). Each entry is a full-width row whose text wraps, with edit and
/// delete actions; editing happens in place in a multi-line field with
/// Save / Cancel, so the original text is never lost. New entries are added
/// from the field at the bottom (Enter or the Add button).
class TextListEditor extends StatefulWidget {
  const TextListEditor({
    super.key,
    required this.values,
    required this.label,
    required this.onChanged,
    required this.addLabel,
    required this.editTooltip,
    required this.deleteTooltip,
    required this.saveLabel,
    required this.cancelLabel,
    this.emptyText,
    this.hintText,
  });

  final List<String> values;
  final String label;
  final ValueChanged<List<String>> onChanged;
  final String addLabel;
  final String editTooltip;
  final String deleteTooltip;
  final String saveLabel;
  final String cancelLabel;
  final String? emptyText;
  final String? hintText;

  @override
  State<TextListEditor> createState() => _TextListEditorState();
}

class _TextListEditorState extends State<TextListEditor> {
  late List<String> _items;
  final _addCtrl = TextEditingController();

  /// Index of the row currently being edited, if any.
  int? _editing;
  TextEditingController? _editCtrl;

  @override
  void initState() {
    super.initState();
    _items = [...widget.values];
  }

  @override
  void didUpdateWidget(covariant TextListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values) {
      _items = [...widget.values];
      if (_editing != null && _editing! >= _items.length) _stopEditing();
    }
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    _editCtrl?.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    if (_items.contains(t)) return;
    setState(() => _items.add(t));
    widget.onChanged(List.unmodifiable(_items));
    _addCtrl.clear();
  }

  void _remove(int index) {
    setState(() {
      _items.removeAt(index);
      if (_editing == index) {
        _stopEditing();
      } else if (_editing != null && _editing! > index) {
        _editing = _editing! - 1;
      }
    });
    widget.onChanged(List.unmodifiable(_items));
  }

  void _startEditing(int index) {
    _editCtrl?.dispose();
    setState(() {
      _editing = index;
      _editCtrl = TextEditingController(text: _items[index]);
    });
  }

  void _stopEditing() {
    _editCtrl?.dispose();
    _editCtrl = null;
    _editing = null;
  }

  void _cancelEditing() => setState(_stopEditing);

  void _saveEditing() {
    final index = _editing;
    final ctrl = _editCtrl;
    if (index == null || ctrl == null) return;
    final t = ctrl.text.trim();
    if (t.isEmpty) {
      _cancelEditing();
      return;
    }
    final changed = t != _items[index];
    setState(() {
      _items[index] = t;
      _stopEditing();
    });
    if (changed) widget.onChanged(List.unmodifiable(_items));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 8, 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_items.isEmpty && widget.emptyText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.emptyText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.disabledColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          for (var i = 0; i < _items.length; i++) ...[
            if (_editing == i) _buildEditRow(theme) else _buildRow(i, theme),
            if (i < _items.length - 1) const Divider(height: 8),
          ],
          if (_items.isNotEmpty) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _addCtrl,
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _add,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _add(_addCtrl.text),
                child: Text(widget.addLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int index, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _items[index],
              style: theme.textTheme.bodyMedium,
              softWrap: true,
            ),
          ),
        ),
        IconButton(
          tooltip: widget.editTooltip,
          icon: const Icon(Icons.edit_outlined, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: () => _startEditing(index),
        ),
        IconButton(
          tooltip: widget.deleteTooltip,
          icon: const Icon(Icons.delete_outline, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: () => _remove(index),
        ),
      ],
    );
  }

  Widget _buildEditRow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: _editCtrl,
          autofocus: true,
          maxLines: null,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saveEditing(),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _cancelEditing,
              child: Text(widget.cancelLabel),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _saveEditing,
              child: Text(widget.saveLabel),
            ),
          ],
        ),
      ],
    );
  }
}
