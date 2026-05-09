import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'child_pane.dart';
import 'editor/edit_goal_panel.dart';
import 'root_pane.dart';

class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key});

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  bool _busy = false;
  late final Stream<List<Goal>> _rootsStream;

  @override
  void initState() {
    super.initState();
    _rootsStream = ref.read(goalsServiceProvider).streamRoots!;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink0,
      child: Column(
        children: [
          _GoalsHeader(),
          const Divider(height: 1, thickness: 1, color: AppColors.ink2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: RootPane(rootsAsync: _rootsStream)),
                const VerticalDivider(width: 1, color: AppColors.ink2),
                const Expanded(child: ChildPane()),
                const VerticalDivider(width: 1, color: AppColors.ink2),
                const SizedBox(width: 720, child: EditGoalPanel()),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.ink2),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.s,
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Export goals'),
                  onPressed: _busy ? null : _exportGoals,
                ),
                const SizedBox(width: AppSpacing.s),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Import goals'),
                  onPressed: _busy ? null : _importGoals,
                ),
                if (_busy) ...const [
                  SizedBox(width: AppSpacing.m),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportGoals() async {
    setState(() => _busy = true);
    try {
      final goals = await ref.read(goalsServiceProvider).getAllGoalsOnce();
      if (goals.isEmpty) {
        if (mounted) _showSnack('No goals to export');
        return;
      }

      final tree = _buildTree(goals);
      final payload = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'goals': tree,
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);

      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File(p.join(dir.path, 'goals-export-$stamp.json'));
      await file.writeAsString(json);

      if (mounted) _showSnack('Exported to ${file.path}');
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importGoals() async {
    setState(() => _busy = true);
    try {
      final tree = await _pickAndParseGoalsFile();
      if (tree == null) return;

      final totalCount = _countNodes(tree);
      if (totalCount == 0) {
        if (mounted) _showSnack('File contained no goals');
        return;
      }

      final mode = await _askImportMode(totalCount, tree.length);
      if (mode == null) return;

      var deletedCount = 0;
      if (mode == _ImportMode.replace) {
        deletedCount = await _deleteAllGoals();
      }

      await _insertTree(tree, parentId: null);

      if (mounted) {
        final suffix = mode == _ImportMode.replace
            ? ' (replaced $deletedCount existing)'
            : '';
        _showSnack('Imported $totalCount goal(s)$suffix');
      }
    } catch (e) {
      if (mounted) _showSnack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _deleteAllGoals() async {
    final svc = ref.read(goalsServiceProvider);
    final all = await svc.getAllGoalsOnce();
    final roots = await svc.getRootGoalsOnce();
    for (final root in roots) {
      await svc.deleteSubtree(root.id);
    }
    return all.length;
  }

  Future<_ImportMode?> _askImportMode(int total, int rootCount) async {
    return showDialog<_ImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import goals'),
        content: Text(
          'The file contains $rootCount root goal(s) and $total total node(s).\n\n'
          '• Add: append to your existing goals (new ids assigned).\n'
          '• Replace: delete all current goals first, then import.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ImportMode.add),
            child: const Text('Add'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(_ImportMode.replace),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>?> _pickAndParseGoalsFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select goals JSON to import',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) {
      if (mounted) _showSnack('Could not read selected file');
      return null;
    }

    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['goals'] is! List) {
      if (mounted) _showSnack('Invalid goals file');
      return null;
    }

    return (decoded['goals'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _insertTree(
    List<Map<String, dynamic>> nodes, {
    required String? parentId,
  }) async {
    final svc = ref.read(goalsServiceProvider);
    for (final node in nodes) {
      final newId = await svc.createGoalWithFields(
        title: (node['title'] as String?) ?? '',
        description: node['description'] as String?,
        parentId: parentId,
        order: (node['order'] as num?)?.toInt() ?? 0,
        optional: node['optional'] as bool? ?? false,
        teachingTips: _stringList(node['teachingTips']),
        allowChains: node['allowChains'] as bool? ?? false,
        objectives: _objectiveList(node['objectives']),
      );
      final children = node['children'];
      if (children is List && children.isNotEmpty) {
        await _insertTree(
          children.cast<Map<String, dynamic>>(),
          parentId: newId,
        );
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

List<Map<String, dynamic>> _buildTree(List<Goal> goals) {
  final byParent = <String?, List<Goal>>{};
  for (final g in goals) {
    byParent.putIfAbsent(g.parentId, () => []).add(g);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.order.compareTo(b.order));
  }

  Map<String, dynamic> nodeFor(Goal g) {
    final children = byParent[g.id] ?? const <Goal>[];
    final isSubgoal = g.parentId != null;
    return {
      'title': g.title,
      'description': g.description,
      'order': g.order,
      'optional': g.optional,
      if (isSubgoal) 'teachingTips': g.teachingTips,
      if (isSubgoal) 'allowChains': g.allowChains,
      if (isSubgoal) 'objectives': g.objectives.map((o) => o.toMap()).toList(),
      'children': children.map(nodeFor).toList(),
    };
  }

  final roots = byParent[null] ?? const <Goal>[];
  return roots.map(nodeFor).toList();
}

int _countNodes(List<Map<String, dynamic>> nodes) {
  var n = 0;
  for (final node in nodes) {
    n += 1;
    final children = node['children'];
    if (children is List && children.isNotEmpty) {
      n += _countNodes(children.cast<Map<String, dynamic>>());
    }
  }
  return n;
}

List<String> _stringList(dynamic v) {
  if (v is List) return v.map((e) => e?.toString() ?? '').toList();
  return const [];
}

List<Map<String, dynamic>> _objectiveList(dynamic v) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return const [];
}

enum _ImportMode { add, replace }

class _GoalsHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      alignment: Alignment.centerLeft,
      child: const Text(
        'Doelen',
        style: TextStyle(
          color: AppColors.fg,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
