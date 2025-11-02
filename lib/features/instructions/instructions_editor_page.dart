// lib/features/instructions/instructions_editor_page.dart
import 'package:ai_tutor_python/data/instructions/instruction.dart';
import 'package:ai_tutor_python/data/instructions/instructions_provider.dart';
import 'package:ai_tutor_python/features/instructions/doc_header.dart';
import 'package:ai_tutor_python/features/instructions/doc_list.dart';
import 'package:ai_tutor_python/features/instructions/editor_pane.dart';
import 'package:ai_tutor_python/features/instructions/section_header.dart';
import 'package:ai_tutor_python/features/instructions/sections_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:highlight/languages/markdown.dart';

class InstructionsEditorPage extends ConsumerStatefulWidget {
  const InstructionsEditorPage({super.key});

  @override
  ConsumerState<InstructionsEditorPage> createState() =>
      _InstructionsEditorPageState();
}

class _InstructionsEditorPageState
    extends ConsumerState<InstructionsEditorPage> {
  String? _selectedDocId;
  Instruction? _original; // last fetched/saved version
  Map<String, String> _workingSections = {};
  String? _selectedSectionKey;

  late CodeController _codeCtrl;

  bool get _hasDocSelected => _selectedDocId != null;
  bool get _hasSectionSelected => _selectedSectionKey != null;

  bool get _isDirty {
    if (_original == null) return _workingSections.isNotEmpty;
    return !_mapEquals(_original!.sections, _workingSections);
  }

  @override
  void initState() {
    super.initState();
    _codeCtrl = CodeController(text: '', language: markdown);
    _codeCtrl.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _codeCtrl.removeListener(_onEditorChanged);
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    if (!_hasSectionSelected) return;
    final key = _selectedSectionKey!;
    final newText = _codeCtrl.text;
    // Avoid churning the map if nothing changed
    if (_workingSections[key] != newText) {
      setState(() {
        _workingSections = Map<String, String>.from(_workingSections)
          ..[key] = newText;
      });
    }
  }

  void _selectDocument(Instruction? doc) {
    setState(() {
      _selectedDocId = doc?.id;
      _original = doc;
      _workingSections = Map<String, String>.from(doc?.sections ?? {});
      // Keep selected section if still present; else pick first or clear
      if (_selectedSectionKey == null ||
          !_workingSections.containsKey(_selectedSectionKey)) {
        _selectedSectionKey = _workingSections.isEmpty
            ? null
            : _workingSections.keys.first;
      }
      _refreshEditorFromSelection();
    });
  }

  void _refreshEditorFromSelection() {
    final text = _hasSectionSelected
        ? _workingSections[_selectedSectionKey!] ?? ''
        : '';
    _codeCtrl.clear();
    _codeCtrl.text = text;
  }

  Future<void> _newDocument() async {
    final id = await _promptForText(
      context,
      title: 'New document',
      label: 'Document id (e.g. system_prompt)',
    );
    if (id == null || id.trim().isEmpty) return;

    setState(() {
      _selectedDocId = id.trim();
      _original = Instruction(id: _selectedDocId!, sections: {});
      _workingSections = {};
      _selectedSectionKey = null;
      _refreshEditorFromSelection();
    });
  }

  Future<void> _deleteDocument() async {
    if (!_hasDocSelected) return;
    final repo = ref.read(instructionsRepositoryProvider);
    final confirm = await _confirm(
      context,
      'Delete “${_selectedDocId!}”?',
      'This will permanently delete the document.',
    );
    if (confirm != true) return;
    await repo.delete(_selectedDocId!);
    setState(() {
      _selectedDocId = null;
      _original = null;
      _workingSections = {};
      _selectedSectionKey = null;
      _refreshEditorFromSelection();
    });
    if (mounted) {
      _showSnackBar(context, 'Document deleted');
    }
  }

  Future<void> _saveDocument() async {
    if (!_hasDocSelected) return;
    final repo = ref.read(instructionsRepositoryProvider);
    final toSave = Instruction(id: _selectedDocId!, sections: _workingSections);
    await repo.upsert(toSave);
    setState(() {
      _original = toSave;
    });
    if (mounted) {
      _showSnackBar(context, 'Saved');
    }
  }

  Future<void> _addSection() async {
    if (!_hasDocSelected) return;
    final key = await _promptForText(
      context,
      title: 'Add section',
      label: 'Section key (e.g. current_context)',
    );
    if (key == null) return;
    final k = key.trim();
    if (k.isEmpty) return;

    if (_workingSections.containsKey(k)) {
      if (!mounted) return;
      _showSnackBar(context, 'Section “$k” already exists');
      return;
    }

    setState(() {
      _workingSections = Map<String, String>.from(_workingSections)..[k] = '';
      _selectedSectionKey = k;
      _refreshEditorFromSelection();
    });
  }

  Future<void> _deleteSection() async {
    if (!_hasDocSelected || !_hasSectionSelected) return;
    final k = _selectedSectionKey!;
    final confirm = await _confirm(
      context,
      'Delete “$k”?',
      'This removes the section from the document.',
    );
    if (confirm != true) return;

    setState(() {
      final newMap = Map<String, String>.from(_workingSections);
      newMap.remove(k);
      _workingSections = newMap;

      // Select another section if any
      _selectedSectionKey = _workingSections.isEmpty
          ? null
          : _workingSections.keys.first;
      _refreshEditorFromSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(instructionsListProviderStream);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Instructions Editor'),
        actions: [
          IconButton(
            tooltip: 'New document',
            icon: const Icon(Icons.add),
            onPressed: _newDocument,
          ),
          IconButton(
            tooltip: 'Delete document',
            icon: const Icon(Icons.delete_outline),
            onPressed: _hasDocSelected ? _deleteDocument : null,
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            onPressed: _hasDocSelected ? _saveDocument : null,
            label: Text(_isDirty ? 'Save *' : 'Save'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // Left: documents list
          SizedBox(
            width: 280,
            child: docsAsync.when(
              data: (docs) => DocsList(
                docs: docs,
                selectedId: _selectedDocId,
                onSelect: (doc) => _selectDocument(doc),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading documents: $e'),
                ),
              ),
            ),
          ),

          const VerticalDivider(width: 1),

          // Middle: sections list + controls
          SizedBox(
            width: 280,
            child: Column(
              children: [
                DocHeader(
                  selectedDocId: _selectedDocId,
                  onRename: _renameDocument,
                ),
                const Divider(height: 1),
                Expanded(
                  child: SectionsList(
                    sections: _workingSections,
                    selectedKey: _selectedSectionKey,
                    onSelect: (k) {
                      setState(() {
                        _selectedSectionKey = k;
                        _refreshEditorFromSelection();
                      });
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _hasDocSelected ? _addSection : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Add section'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _hasDocSelected && _hasSectionSelected
                            ? _deleteSection
                            : null,
                        icon: const Icon(Icons.remove),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const VerticalDivider(width: 1),

          // Right: editor
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  keyName: _selectedSectionKey,
                  onRename: _renameSection,
                  enabled: _hasSectionSelected,
                ),
                const Divider(height: 1),
                Expanded(child: EditorPane(controller: _codeCtrl)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDocument() async {
    if (!_hasDocSelected) return;
    final newId = await _promptForText(
      context,
      title: 'Rename document',
      label: 'New document id',
      initial: _selectedDocId,
    );
    if (newId == null) return;
    final target = newId.trim();
    if (target.isEmpty || target == _selectedDocId) return;

    // Implement "rename" by copy + delete for simplicity.
    final repo = ref.read(instructionsRepositoryProvider);
    final data = Instruction(id: target, sections: _workingSections);
    await repo.upsert(data);
    await repo.delete(_selectedDocId!);

    setState(() {
      _selectedDocId = target;
      _original = data;
    });
    if (mounted) {
      _showSnackBar(context, 'Renamed to “$target”');
    }
  }

  Future<void> _renameSection() async {
    if (!_hasSectionSelected) return;
    final oldKey = _selectedSectionKey!;
    final newKey = await _promptForText(
      context,
      title: 'Rename section',
      label: 'New section key',
      initial: oldKey,
    );
    if (newKey == null) return;
    final nk = newKey.trim();
    if (nk.isEmpty || nk == oldKey) return;
    if (_workingSections.containsKey(nk)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A section named “$nk” already exists')),
      );
      return;
    }

    setState(() {
      final value = _workingSections[oldKey] ?? '';
      final newMap = Map<String, String>.from(_workingSections)
        ..remove(oldKey)
        ..[nk] = value;
      _workingSections = newMap;
      _selectedSectionKey = nk;
      _refreshEditorFromSelection();
    });
  }
}

/// Helpers

Future<String?> _promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String? initial,
}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

Future<bool?> _confirm(BuildContext context, String title, String body) async {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
