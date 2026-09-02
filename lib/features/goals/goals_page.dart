import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
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
import 'goal_import_plan.dart';
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
    final l = AppLocalizations.of(context);
    // A Material (not a coloured Container) so the ListTile rows inside — the
    // root and subgoal lists, and the editor's switches — paint their tile
    // colour and ink splashes on this surface. A ColoredBox here would sit in
    // front of the nearest Material and hide both, which is exactly what the
    // selected-row highlight was losing (#68).
    return Material(
      color: AppColors.ink0,
      child: Column(
        children: [
          const _GoalsHeader(),
          Divider(height: 1, thickness: 1, color: AppColors.ink2),
          Expanded(
            child: Row(
              children: [
                Expanded(child: RootPane(rootsAsync: _rootsStream)),
                VerticalDivider(width: 1, color: AppColors.ink2),
                const Expanded(child: ChildPane()),
                VerticalDivider(width: 1, color: AppColors.ink2),
                const SizedBox(width: 720, child: EditGoalPanel()),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.ink2),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.s,
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: Text(l.goals_action_export),
                  onPressed: _busy ? null : _exportGoals,
                ),
                const SizedBox(width: AppSpacing.s),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: Text(l.goals_action_import),
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
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final goals = await ref.read(goalsServiceProvider).getAllGoalsOnce();
      if (goals.isEmpty) {
        if (mounted) _showSnack(l.goals_snack_noGoalsToExport);
        return;
      }

      final entries = _buildExportEntries(goals);
      final payload = {
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'goals': entries,
      };
      final json = const JsonEncoder.withIndent('  ').convert(payload);

      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final file = File(p.join(dir.path, 'goals-export-$stamp.json'));
      await file.writeAsString(json);

      if (mounted) _showSnack(l.goals_snack_exportedTo(file.path));
    } catch (e) {
      if (mounted) _showSnack(l.goals_snack_exportFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importGoals() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final entries = await _pickAndParseGoalsFile();
      if (entries == null) return;

      final totalCount = _countNodes(entries);
      if (totalCount == 0) {
        if (mounted) _showSnack(l.goals_snack_fileEmpty);
        return;
      }

      final mode = await _askImportMode(totalCount, entries.length);
      if (mode == null) return;

      final svc = ref.read(goalsServiceProvider);
      final existing = await svc.getAllGoalsOnce();
      final existingIds = {for (final g in existing) g.id};
      final importedIds = _collectIds(entries);

      if (mode == _ImportMode.add) {
        final collisions = importedIds.intersection(existingIds);
        if (collisions.isNotEmpty) {
          if (mounted) {
            _showSnack(
              l.goals_snack_addAborted(
                collisions.length,
                collisions.take(3).join(', '),
              ),
            );
          }
          return;
        }
        await _insertEntriesAdd(entries);
        if (mounted) _showSnack(l.goals_snack_imported(totalCount));
        return;
      }

      if (mode == _ImportMode.replace) {
        // Scoped replace (#85): each root entry in the file replaces one
        // existing set; sets the file does not name are never touched.
        await _replaceScoped(svc, existing, entries, totalCount);
        return;
      }

      // Replace all: the old wipe-and-reload across every set, kept as a
      // distinct explicit action (#85) — upsert by id (preserves contentId),
      // then delete every goal not in the file, after a confirmed preview.
      final leftovers = existingIds.difference(importedIds).toList();
      final confirmed = mounted && await _confirmReplaceAll(leftovers.length);
      if (!confirmed) return;
      await _insertEntriesReplace(entries);
      if (leftovers.isNotEmpty) {
        await svc.deleteGoalsByIds(leftovers);
      }
      if (mounted) {
        _showSnack(
          leftovers.isEmpty
              ? l.goals_snack_imported(totalCount)
              : l.goals_snack_importedWithRemoved(totalCount, leftovers.length),
        );
      }
    } catch (e) {
      if (mounted) _showSnack(l.goals_snack_importFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Replace scoped to root sets (#85): resolve every root entry in the file
  /// to one existing root (by id, else by unique title, else by asking),
  /// preview what will be removed, and only then write — deleting exclusively
  /// inside the subtrees the user has seen named in the preview.
  Future<void> _replaceScoped(
    GoalsService svc,
    List<Goal> existing,
    List<Map<String, dynamic>> entries,
    int totalCount,
  ) async {
    final l = AppLocalizations.of(context);
    final plan = buildReplacePlan(existing, entries);
    final targets = [...plan.resolved];
    final claimed = <String>{
      for (final t in targets)
        if (t.existingRoot != null) t.existingRoot!.id,
    };
    final roots = existing.where((g) => g.parentId == null).toList();

    for (final entry in plan.unmatched) {
      if (!mounted) return;
      final available = roots.where((r) => !claimed.contains(r.id)).toList();
      final choice = await _askUnmatchedRoot(entry, available);
      if (choice == null) return; // Cancel aborts the whole import.
      final target = choice.target;
      if (target == null) {
        targets.add(ReplaceTarget(entry: entry));
      } else {
        claimed.add(target.id);
        targets.add(resolveTarget(existing, entry, target));
      }
    }

    final removedIds = <String>{for (final t in targets) ...t.removedIds};
    if (!mounted) return;
    final confirmed = await _confirmReplacePreview(targets);
    if (!confirmed) return;

    await _insertEntriesReplace(entries);
    if (removedIds.isNotEmpty) {
      await svc.deleteGoalsByIds(removedIds.toList());
    }
    if (mounted) {
      _showSnack(
        removedIds.isEmpty
            ? l.goals_snack_imported(totalCount)
            : l.goals_snack_importedWithRemoved(totalCount, removedIds.length),
      );
    }
  }

  Future<_ImportMode?> _askImportMode(int total, int rootCount) async {
    return showDialog<_ImportMode>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.goals_import_dialog_title),
          content: Text(l.goals_import_dialog_message(rootCount, total)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(l.goals_import_action_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_ImportMode.add),
              child: Text(l.goals_import_action_add),
            ),
            // The global wipe stays available, but as a distinct, explicitly
            // labelled action — never the default filled button (#85).
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_ImportMode.replaceAll),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l.goals_import_action_replaceAll),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_ImportMode.replace),
              child: Text(l.goals_import_action_replace),
            ),
          ],
        );
      },
    );
  }

  /// The file's root [entry] matched no existing set: add as a new set,
  /// replace a set chosen from the dropdown, or cancel the import (#85).
  Future<_UnmatchedChoice?> _askUnmatchedRoot(
    Map<String, dynamic> entry,
    List<Goal> availableRoots,
  ) {
    final importedTitle = ((entry['goal'] as Map)['title'] as String?) ?? '';
    var selectedId = ''; // '' = add as a new set.
    return showDialog<_UnmatchedChoice>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(l.goals_import_unmatched_title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.goals_import_unmatched_message(importedTitle)),
                const SizedBox(height: AppSpacing.m),
                DropdownButton<String>(
                  value: selectedId,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(l.goals_import_unmatched_addAsNew),
                    ),
                    for (final r in availableRoots)
                      DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          l.goals_import_unmatched_replaceOption(r.title),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => selectedId = v ?? ''),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l.goals_import_action_cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(
                  _UnmatchedChoice(
                    selectedId.isEmpty
                        ? null
                        : availableRoots.firstWhere((r) => r.id == selectedId),
                  ),
                ),
                child: Text(l.goals_import_action_continue),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shows what a scoped Replace is about to do — per set, how many goals the
  /// file ships and how many existing ones will be removed — *before* any
  /// write happens (#85). Returns true when the user confirms.
  Future<bool> _confirmReplacePreview(List<ReplaceTarget> targets) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        final lines = [
          for (final t in targets)
            t.existingRoot == null
                ? l.goals_import_preview_newSetLine(t.importedTitle)
                : l.goals_import_preview_replaceLine(
                    t.existingRoot!.title,
                    t.importedCount,
                    t.removedIds.length,
                  ),
        ];
        return AlertDialog(
          title: Text(l.goals_import_preview_title),
          content: Text(lines.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.goals_import_action_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.goals_import_action_replace),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// Confirms the global wipe with its removal count shown up front (#85).
  Future<bool> _confirmReplaceAll(int removedCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.goals_import_previewAll_title),
          content: Text(l.goals_import_previewAll_message(removedCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.goals_import_action_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.goals_import_action_replaceAll),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<List<Map<String, dynamic>>?> _pickAndParseGoalsFile() async {
    final l = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l.goals_import_filePicker_title,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return null;

    final path = result.files.single.path;
    if (path == null) {
      if (mounted) _showSnack(l.goals_snack_couldNotRead);
      return null;
    }

    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      if (mounted) _showSnack(l.goals_snack_invalidFile);
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
          .map(
            (e) => {
              'goal': Map<String, dynamic>.from(e['goal'] as Map),
              'subgoals': (e['subgoals'] as List)
                  .whereType<Map>()
                  .map((s) => Map<String, dynamic>.from(s))
                  .toList(),
            },
          )
          .toList();
      if (entries.isEmpty) {
        if (mounted) _showSnack(l.goals_snack_invalidFile);
        return null;
      }
    } else {
      if (mounted) _showSnack(l.goals_snack_invalidFile);
      return null;
    }

    return entries;
  }

  Future<void> _insertEntriesAdd(List<Map<String, dynamic>> entries) async {
    final svc = ref.read(goalsServiceProvider);
    for (final entry in entries) {
      final goal = entry['goal'] as Map<String, dynamic>;
      final goalId = await svc.createGoalWithFields(
        id: (goal['id'] as String?)?.trim().isEmpty == false
            ? goal['id'] as String
            : null,
        title: (goal['title'] as String?) ?? '',
        description: goal['description'] as String?,
        parentId: null,
        order: (goal['order'] as num?)?.toInt() ?? 0,
        optional: goal['optional'] as bool? ?? false,
        moduleId: (goal['moduleId'] as String?) ?? '',
      );

      final subgoals = (entry['subgoals'] as List).cast<Map<String, dynamic>>();
      for (final sg in subgoals) {
        await svc.createGoalWithFields(
          id: (sg['id'] as String?)?.trim().isEmpty == false
              ? sg['id'] as String
              : null,
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

  Future<void> _insertEntriesReplace(List<Map<String, dynamic>> entries) async {
    final svc = ref.read(goalsServiceProvider);
    for (final entry in entries) {
      final goal = entry['goal'] as Map<String, dynamic>;
      final rawGoalId = goal['id'] as String?;
      // Replace mode requires a stable id per doc to preserve content links.
      // Fall back to a hash-stable id derived from title only as a last resort
      // — but the goal-generator JSON always provides one.
      if (rawGoalId == null || rawGoalId.trim().isEmpty) {
        throw StateError(
          'Goal "${goal['title']}" has no id; Replace mode requires an id '
          'on every imported goal/subgoal. Use Add instead.',
        );
      }
      final goalId = rawGoalId;
      await svc.upsertGoalWithFields(
        id: goalId,
        title: (goal['title'] as String?) ?? '',
        description: goal['description'] as String?,
        parentId: null,
        order: (goal['order'] as num?)?.toInt() ?? 0,
        optional: goal['optional'] as bool? ?? false,
        moduleId: (goal['moduleId'] as String?) ?? '',
      );

      final subgoals = (entry['subgoals'] as List).cast<Map<String, dynamic>>();
      for (final sg in subgoals) {
        final rawSgId = sg['id'] as String?;
        if (rawSgId == null || rawSgId.trim().isEmpty) {
          throw StateError(
            'Subgoal "${sg['title']}" has no id; Replace mode requires an id '
            'on every imported goal/subgoal. Use Add instead.',
          );
        }
        await svc.upsertGoalWithFields(
          id: rawSgId,
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

  /// Collects every `id` referenced in the import payload (root goals and
  /// their subgoals), skipping entries that don't carry one.
  Set<String> _collectIds(List<Map<String, dynamic>> entries) {
    final ids = <String>{};
    for (final entry in entries) {
      final goal = entry['goal'] as Map<String, dynamic>;
      final gid = goal['id'];
      if (gid is String && gid.trim().isNotEmpty) ids.add(gid);

      final subgoals =
          (entry['subgoals'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      for (final sg in subgoals) {
        final sid = sg['id'];
        if (sid is String && sid.trim().isNotEmpty) ids.add(sid);
      }
    }
    return ids;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  return const [];
}

enum _ImportMode { add, replace, replaceAll }

/// Outcome of [_GoalsPageState._askUnmatchedRoot]: replace [target], or add
/// the entry as a new set when [target] is null.
class _UnmatchedChoice {
  const _UnmatchedChoice(this.target);

  final Goal? target;
}

class _GoalsHeader extends StatelessWidget {
  const _GoalsHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      alignment: Alignment.centerLeft,
      child: Text(
        AppLocalizations.of(context).goals_header_title,
        style: TextStyle(
          color: AppColors.fg,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
