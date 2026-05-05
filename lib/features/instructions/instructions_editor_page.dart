// lib/features/instructions/instructions_editor_page.dart
import 'dart:io';

import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:ai_tutor_python/features/instructions/doc_header.dart';
import 'package:ai_tutor_python/features/instructions/doc_list.dart';
import 'package:ai_tutor_python/features/instructions/editor_pane.dart';
import 'package:ai_tutor_python/features/instructions/section_header.dart';
import 'package:ai_tutor_python/features/instructions/sections_list.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class InstructionsEditorPage extends ConsumerStatefulWidget {
  const InstructionsEditorPage({super.key});

  @override
  ConsumerState<InstructionsEditorPage> createState() =>
      _InstructionsEditorPageState();
}

class _InstructionsEditorPageState
    extends ConsumerState<InstructionsEditorPage> {
  String? _selectedDocId;
  Instruction? _original;
  Map<String, String> _workingSections = {};
  String? _selectedSectionKey;

  late final Stream<List<Instruction>> _docsStream;
  late CodeController _codeCtrl;

  bool get _hasDocSelected => _selectedDocId != null;
  bool get _hasSectionSelected => _selectedSectionKey != null;

  bool get _isDirty {
    if (_original == null) return _workingSections.isNotEmpty;
    return !_mapEquals(_original!.sections, _workingSections);
  }

  InstructionsService get _svc =>
      ref.read(instructionsServiceProvider.notifier);

  @override
  void initState() {
    super.initState();
    _docsStream = ref.read(instructionsServiceProvider.notifier).watchAll();
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

    final confirm = await _confirm(
      context,
      'Delete "$_selectedDocId"?',
      'This will permanently delete the document.',
    );
    if (confirm != true) return;
    await _svc.delete(_selectedDocId!);

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
    final toSave = Instruction(id: _selectedDocId!, sections: _workingSections);
    await _svc.upsert(toSave);

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
      _showSnackBar(context, 'Section "$k" already exists');
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
      'Delete "$k"?',
      'This removes the section from the document.',
    );
    if (confirm != true) return;

    setState(() {
      final newMap = Map<String, String>.from(_workingSections);
      newMap.remove(k);
      _workingSections = newMap;

      _selectedSectionKey = _workingSections.isEmpty
          ? null
          : _workingSections.keys.first;
      _refreshEditorFromSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink0,
      child: Column(
        children: [
          _Toolbar(
            isDirty: _isDirty,
            hasDocSelected: _hasDocSelected,
            onNew: _newDocument,
            onDelete: _hasDocSelected ? _deleteDocument : null,
            onExport: _exportAllToMarkdown,
            onImport: _importFromMarkdown,
            onSave: _hasDocSelected ? _saveDocument : null,
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.ink2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Row(
        children: [
          SizedBox(
            width: 280,
            child: StreamBuilder<List<Instruction>>(
              stream: _docsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error loading documents: ${snapshot.error}'),
                    ),
                  );
                }
                final docs = snapshot.data ?? [];
                return DocsList(
                  docs: docs,
                  selectedId: _selectedDocId,
                  onSelect: (doc) => _selectDocument(doc),
                );
              },
            ),
          ),

          const VerticalDivider(width: 1),

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
    );
  }

  Future<void> _exportAllToMarkdown() async {
    try {
      final docs = await _svc.getAll();
      if (docs.isEmpty) {
        if (mounted) _showSnackBar(context, 'No documents to export');
        return;
      }

      final sortedDocs = [...docs]
        ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));
      final markdown = _buildMarkdownExport(sortedDocs);

      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File(p.join(dir.path, 'instructions-export-$stamp.md'));
      await file.writeAsString(markdown);

      if (mounted) _showSnackBar(context, 'Exported to ${file.path}');
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Export failed: $e');
    }
  }

  Future<void> _importFromMarkdown() async {
    try {
      final path = await _pickMarkdownPath();
      if (path == null) return;

      final parsed = _parseMarkdownImport(await File(path).readAsString());
      if (parsed.isEmpty) {
        if (mounted) _showSnackBar(context, 'No documents found in file');
        return;
      }

      final mode = await _askInstructionsImportMode(parsed.length);
      if (mode == null) return;

      final stats = await _applyMarkdownImport(parsed, mode);
      if (stats.refreshSelected) await _reloadSelectedDocument();

      if (!mounted) return;
      _showSnackBar(context, _formatImportSummary(stats, mode));
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Import failed: $e');
    }
  }

  Future<_InstructionsImportMode?> _askInstructionsImportMode(
    int docCount,
  ) async {
    return showDialog<_InstructionsImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import instructions'),
        content: Text(
          'The file contains $docCount document(s).\n\n'
          "• Add: only insert sections that don't already exist; keep current values.\n"
          "• Replace: overwrite each imported document's sections with the file's contents. Documents not in the file are left alone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_InstructionsImportMode.add),
            child: const Text('Add'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_InstructionsImportMode.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickMarkdownPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Markdown file to import',
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown'],
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) {
      if (mounted) _showSnackBar(context, 'Could not read selected file');
      return null;
    }
    return path;
  }

  Future<_ImportStats> _applyMarkdownImport(
    Map<String, Map<String, String>> parsed,
    _InstructionsImportMode mode,
  ) async {
    final existing = await _svc.getAll();
    final byId = {for (final d in existing) d.id: d};

    final stats = _ImportStats();
    for (final entry in parsed.entries) {
      final touched =
          await _importDocEntry(entry.key, entry.value, byId, stats, mode);
      if (touched && entry.key == _selectedDocId) stats.refreshSelected = true;
    }
    return stats;
  }

  Future<bool> _importDocEntry(
    String id,
    Map<String, String> importedSections,
    Map<String, Instruction> byId,
    _ImportStats stats,
    _InstructionsImportMode mode,
  ) async {
    final current = byId[id];
    if (current == null) {
      if (importedSections.isEmpty) return false;
      await _svc.upsert(Instruction(id: id, sections: importedSections));
      stats.newDocs++;
      stats.addedSections += importedSections.length;
      return true;
    }

    if (mode == _InstructionsImportMode.replace) {
      if (_mapEquals(current.sections, importedSections)) return false;
      await _svc.upsert(Instruction(id: id, sections: importedSections));
      stats.updatedDocs++;
      stats.replacedSections += importedSections.length;
      return true;
    }

    final merged = Map<String, String>.from(current.sections);
    var changed = 0;
    for (final s in importedSections.entries) {
      if (!merged.containsKey(s.key)) {
        merged[s.key] = s.value;
        changed++;
      }
    }
    if (changed == 0) return false;
    await _svc.upsert(Instruction(id: id, sections: merged));
    stats.updatedDocs++;
    stats.addedSections += changed;
    return true;
  }

  Future<void> _reloadSelectedDocument() async {
    final id = _selectedDocId;
    if (id == null) return;
    final refreshed = await _svc.getAll();
    for (final d in refreshed) {
      if (d.id == id) {
        _selectDocument(d);
        return;
      }
    }
  }

  String _formatImportSummary(
    _ImportStats stats,
    _InstructionsImportMode mode,
  ) {
    if (mode == _InstructionsImportMode.replace) {
      if (stats.replacedSections == 0 && stats.newDocs == 0) {
        return 'Nothing changed (file matched existing content)';
      }
      final parts = <String>[];
      if (stats.newDocs > 0) parts.add('${stats.newDocs} new doc(s)');
      if (stats.updatedDocs > 0) parts.add('${stats.updatedDocs} replaced');
      if (stats.addedSections > 0) {
        parts.add('${stats.addedSections} added section(s)');
      }
      if (stats.replacedSections > 0) {
        parts.add('${stats.replacedSections} replaced section(s)');
      }
      return parts.join(', ');
    }
    if (stats.addedSections == 0) {
      return 'Nothing imported (all sections already exist)';
    }
    final parts = ['Imported ${stats.addedSections} section(s)'];
    if (stats.newDocs > 0) parts.add('${stats.newDocs} new doc(s)');
    if (stats.updatedDocs > 0) parts.add('${stats.updatedDocs} updated');
    return parts.join(', ');
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

    final data = Instruction(id: target, sections: _workingSections);
    await _svc.upsert(data);
    await _svc.delete(_selectedDocId!);

    setState(() {
      _selectedDocId = target;
      _original = data;
    });
    if (mounted) {
      _showSnackBar(context, 'Renamed to "$target"');
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
        SnackBar(content: Text('A section named "$nk" already exists')),
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Map<String, Map<String, String>> _parseMarkdownImport(String md) {
  return _MarkdownImportParser().parse(md);
}

class _MarkdownImportParser {
  static final _fenceRe = RegExp(r'^\s*(```|~~~)');
  static final _h1Re = RegExp(r'^#\s+(.+?)\s*$');
  static final _h2Re = RegExp(r'^##\s+(.+?)\s*$');
  static final _leadingNewlinesRe = RegExp(r'^\n+');

  final result = <String, Map<String, String>>{};
  final body = StringBuffer();
  String? currentDoc;
  String? currentSection;
  bool inFence = false;

  Map<String, Map<String, String>> parse(String md) {
    for (final raw in md.split('\n')) {
      _processLine(raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw);
    }
    _flushSection();
    return result;
  }

  void _processLine(String line) {
    if (_fenceRe.hasMatch(line)) {
      inFence = !inFence;
      if (currentSection != null) body.writeln(line);
      return;
    }
    if (!inFence && _tryHandleHeader(line)) return;
    if (currentSection != null) body.writeln(line);
  }

  bool _tryHandleHeader(String line) {
    final m2 = _h2Re.firstMatch(line);
    if (m2 != null) {
      _startSection(m2.group(1)!.trim());
      return true;
    }
    final m1 = _h1Re.firstMatch(line);
    if (m1 != null) {
      _startDocument(m1.group(1)!.trim());
      return true;
    }
    return false;
  }

  void _startSection(String key) {
    _flushSection();
    currentSection = key;
    final doc = currentDoc;
    if (doc != null) result.putIfAbsent(doc, () => <String, String>{});
  }

  void _startDocument(String id) {
    _flushSection();
    currentDoc = id;
    currentSection = null;
    result.putIfAbsent(id, () => <String, String>{});
  }

  void _flushSection() {
    final doc = currentDoc;
    final section = currentSection;
    if (doc != null && section != null) {
      final text =
          body.toString().replaceFirst(_leadingNewlinesRe, '').trimRight();
      result.putIfAbsent(doc, () => <String, String>{})[section] = text;
    }
    body.clear();
  }
}

String _buildMarkdownExport(List<Instruction> docs) {
  final buf = StringBuffer();
  for (var i = 0; i < docs.length; i++) {
    final doc = docs[i];
    if (i > 0) buf.writeln();
    buf.writeln('# ${doc.id}');

    final sectionKeys = doc.sections.keys.toList()..sort(_compareSectionKeys);
    for (final key in sectionKeys) {
      buf.writeln();
      buf.writeln('## $key');
      buf.writeln();
      final body = _bumpHeadersToMin3(doc.sections[key] ?? '');
      buf.writeln(body.trimRight());
    }
  }
  return buf.toString();
}

int _compareSectionKeys(String a, String b) {
  final na = _leadingNumber(a);
  final nb = _leadingNumber(b);
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

int? _leadingNumber(String key) {
  final match = RegExp(r'^\s*(\d+)').firstMatch(key);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

final _headerRe = RegExp(r'^(#{1,6})(\s|$)');
final _fenceRe = RegExp(r'^\s*(```|~~~)');

String _bumpHeadersToMin3(String text) {
  final lines = text.split('\n');
  final minLevel = _minHeaderLevel(lines);
  if (minLevel == null || minLevel >= 3) return text;
  final shift = 3 - minLevel;
  return _rewriteHeaders(lines, shift).join('\n');
}

int? _minHeaderLevel(List<String> lines) {
  int? minLevel;
  var inFence = false;
  for (final line in lines) {
    if (_fenceRe.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = _headerRe.firstMatch(line);
    if (m == null) continue;
    final level = m.group(1)!.length;
    if (minLevel == null || level < minLevel) minLevel = level;
  }
  return minLevel;
}

List<String> _rewriteHeaders(List<String> lines, int shift) {
  final out = <String>[];
  var inFence = false;
  for (final line in lines) {
    if (_fenceRe.hasMatch(line)) {
      inFence = !inFence;
      out.add(line);
      continue;
    }
    final m = inFence ? null : _headerRe.firstMatch(line);
    if (m == null) {
      out.add(line);
      continue;
    }
    final level = m.group(1)!.length;
    final newLevel = (level + shift).clamp(1, 6);
    out.add('${'#' * newLevel}${line.substring(level)}');
  }
  return out;
}

class _ImportStats {
  int addedSections = 0;
  int replacedSections = 0;
  int newDocs = 0;
  int updatedDocs = 0;
  bool refreshSelected = false;
}

enum _InstructionsImportMode { add, replace }

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.isDirty,
    required this.hasDocSelected,
    required this.onNew,
    required this.onDelete,
    required this.onExport,
    required this.onImport,
    required this.onSave,
  });

  final bool isDirty;
  final bool hasDocSelected;
  final VoidCallback onNew;
  final VoidCallback? onDelete;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          const Text(
            'Instructies',
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'New document',
            icon: const Icon(Icons.add, size: 18),
            onPressed: onNew,
          ),
          IconButton(
            tooltip: 'Delete document',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
          ),
          IconButton(
            tooltip: 'Export all to Markdown',
            icon: const Icon(Icons.file_download_outlined, size: 18),
            onPressed: onExport,
          ),
          IconButton(
            tooltip: 'Import from Markdown',
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            onPressed: onImport,
          ),
          const SizedBox(width: AppSpacing.s),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            onPressed: onSave,
            label: Text(isDirty ? 'Save *' : 'Save'),
          ),
        ],
      ),
    );
  }
}
