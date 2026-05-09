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

      final entries = _buildExportEntries(goals);
      final payload = {
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'goals': entries,
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
      final entries = await _pickAndParseGoalsFile();
      if (entries == null) return;

      final totalCount = _countNodes(entries);
      if (totalCount == 0) {
        if (mounted) _showSnack('File contained no goals');
        return;
      }

      final mode = await _askImportMode(totalCount, entries.length);
      if (mode == null) return;

      var deletedCount = 0;
      if (mode == _ImportMode.replace) {
        deletedCount = await _deleteAllGoals();
      }

      await _insertEntries(entries);

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
    if (decoded is! Map<String, dynamic>) {
      if (mounted) _showSnack('Invalid goals file');
      return null;
    }

    // Two accepted envelopes:
    //   single-goal authoring  → { goal: {...}, subgoals: [...] }
    //   multi-goal collection  → { goals: [ { goal, subgoals }, ... ] }
    final List<Map<String, dynamic>> entries;
    if (decoded['goal'] is Map && decoded['subgoals'] is List) {
      entries = [
        {
          'goal': Map<String, dynamic>.from(decoded['goal'] as Map),
          'subgoals': (decoded['subgoals'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        },
      ];
    } else if (decoded['goals'] is List) {
      entries = (decoded['goals'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['goal'] is Map && e['subgoals'] is List)
          .map((e) => {
                'goal': Map<String, dynamic>.from(e['goal'] as Map),
                'subgoals': (e['subgoals'] as List)
                    .whereType<Map>()
                    .map((s) => Map<String, dynamic>.from(s))
                    .toList(),
              })
          .toList();
      if (entries.isEmpty) {
        if (mounted) _showSnack('Invalid goals file');
        return null;
      }
    } else {
      if (mounted) _showSnack('Invalid goals file');
      return null;
    }

    return entries;
  }

  Future<void> _insertEntries(List<Map<String, dynamic>> entries) async {
    final svc = ref.read(goalsServiceProvider);
    for (final entry in entries) {
      final goal = entry['goal'] as Map<String, dynamic>;
      final goalId = await svc.createGoalWithFields(
        title: (goal['title'] as String?) ?? '',
        description: goal['description'] as String?,
        parentId: null,
        order: (goal['order'] as num?)?.toInt() ?? 0,
        optional: goal['optional'] as bool? ?? false,
        moduleId: (goal['moduleId'] as String?) ?? '',
      );

      final subgoals = (entry['subgoals'] as List)
          .cast<Map<String, dynamic>>();
      for (final sg in subgoals) {
        await svc.createGoalWithFields(
          title: (sg['title'] as String?) ?? '',
          description: sg['description'] as String?,
          parentId: goalId,
          order: (sg['order'] as num?)?.toInt() ?? 0,
          optional: sg['optional'] as bool? ?? false,
          teachingTips: _stringList(sg['teachingTips']),
          allowChains: sg['allowChains'] as bool? ?? false,
          objectives: _objectiveList(sg['objectives']),
          contentId: sg['contentId'] as String?,
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

List<Map<String, dynamic>> _buildExportEntries(List<Goal> goals) {
  final byParent = <String?, List<Goal>>{};
  for (final g in goals) {
    byParent.putIfAbsent(g.parentId, () => []).add(g);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.order.compareTo(b.order));
  }

  Map<String, dynamic> goalMap(Goal g) => {
        'title': g.title,
        'description': g.description,
        'moduleId': g.moduleId,
        'order': g.order,
        'optional': g.optional,
      };

  Map<String, dynamic> subgoalMap(Goal g) => {
        'title': g.title,
        'description': g.description,
        'order': g.order,
        'optional': g.optional,
        'contentId': g.contentId,
        'teachingTips': g.teachingTips,
        'allowChains': g.allowChains,
        'objectives': g.objectives.map((o) => o.toMap()).toList(),
      };

  final roots = byParent[null] ?? const <Goal>[];
  return roots.map((root) {
    final subgoals = byParent[root.id] ?? const <Goal>[];
    return {
      'goal': goalMap(root),
      'subgoals': subgoals.map(subgoalMap).toList(),
    };
  }).toList();
}

int _countNodes(List<Map<String, dynamic>> entries) {
  var n = 0;
  for (final entry in entries) {
    n += 1; // the root goal
    final subgoals = entry['subgoals'];
    if (subgoals is List) n += subgoals.length;
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
