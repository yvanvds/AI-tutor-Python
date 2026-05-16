import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/module/module.dart';
import 'package:ai_tutor_python/services/module/module_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/lesson_html_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot signal from other pages (e.g. the goals editor) to pre-select
/// a specific subgoal on the next mount of `LessonContentPage`. The page
/// consumes and clears the value on bootstrap so the selection only fires
/// once per navigation event.
final pendingLessonContentGoalIdProvider = StateProvider<String?>((_) => null);

/// Teacher-only "Lesinhoud" view: a tree of module → root goals → subgoals
/// rendered from the goal tree, paired with a raw-HTML editor + WebView
/// preview for the selected subgoal's authored content. The tree is
/// read-only ordering; reorder still happens in `GoalsPage`.
class LessonContentPage extends ConsumerStatefulWidget {
  const LessonContentPage({super.key});

  @override
  ConsumerState<LessonContentPage> createState() => _LessonContentPageState();
}

class _LessonContentPageState extends ConsumerState<LessonContentPage> {
  String? _selectedGoalId;
  Content? _original;
  String _workingTitle = '';
  String _workingBody = '';

  late final TextEditingController _bodyCtrl;
  late final TextEditingController _titleCtrl;
  late final Stream<List<Goal>> _goalsStream;
  bool _bootstrapping = true;

  @override
  void initState() {
    super.initState();
    _bodyCtrl = TextEditingController();
    _bodyCtrl.addListener(_onEditorChanged);
    _titleCtrl = TextEditingController();
    _titleCtrl.addListener(_onTitleChanged);
    // Stable subscription — recreating the stream per build re-triggers
    // ConnectionState.waiting on every setState and flickers the tree.
    _goalsStream = ref.read(goalsServiceProvider).streamAllGoals();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _bodyCtrl.removeListener(_onEditorChanged);
    _bodyCtrl.dispose();
    _titleCtrl.removeListener(_onTitleChanged);
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final modules = ref.read(moduleServiceProvider.notifier);
    final goals = ref.read(goalsServiceProvider);
    final defaultId = await modules.ensureDefaultModule();
    await goals.backfillModuleIds(defaultId);
    if (!mounted) return;
    setState(() => _bootstrapping = false);
    await _consumePendingSelection();
  }

  Future<void> _consumePendingSelection() async {
    final pendingId = ref.read(pendingLessonContentGoalIdProvider);
    if (pendingId == null) return;
    ref.read(pendingLessonContentGoalIdProvider.notifier).state = null;
    final goal = await ref.read(goalsServiceProvider).getGoalOnce(pendingId);
    if (!mounted || goal == null) return;
    await _selectGoal(goal);
  }

  bool get _isDirty {
    if (_selectedGoalId == null) return false;
    if (_original == null) {
      return _workingTitle.isNotEmpty || _workingBody.isNotEmpty;
    }
    return _original!.title != _workingTitle ||
        _original!.body != _workingBody;
  }

  void _onEditorChanged() {
    final text = _bodyCtrl.text;
    if (text == _workingBody) return;
    setState(() => _workingBody = text);
  }

  void _onTitleChanged() {
    final text = _titleCtrl.text;
    if (text == _workingTitle) return;
    setState(() => _workingTitle = text);
  }

  Future<void> _selectGoal(Goal goal) async {
    final cid = goal.contentId;
    Content? loaded;
    if (cid != null && cid.isNotEmpty) {
      // Cache fast-path; fall back to a fetch if not in the latest poll.
      final cached = ref.read(contentServiceProvider);
      loaded = cached.where((c) => c.id == cid).cast<Content?>().firstWhere(
            (c) => true,
            orElse: () => null,
          );
      loaded ??= await ref.read(contentServiceProvider.notifier).getById(cid);
    }

    setState(() {
      _selectedGoalId = goal.id;
      _original = loaded;
      _workingTitle = loaded?.title ?? goal.title;
      _workingBody = loaded?.body ?? '';
      _titleCtrl.value = TextEditingValue(
        text: _workingTitle,
        selection: TextSelection.collapsed(offset: _workingTitle.length),
      );
      _bodyCtrl.text = _workingBody;
    });
  }

  Future<void> _save() async {
    final goalId = _selectedGoalId;
    if (goalId == null) return;
    final goalsSvc = ref.read(goalsServiceProvider);
    final contentSvc = ref.read(contentServiceProvider.notifier);

    final goal = await goalsSvc.getGoalOnce(goalId);
    if (goal == null) return;

    // Content id mirrors the subgoal id so the link is structural — no
    // separate UUID to drift, and re-imports of the goal tree can't orphan
    // the lesinhoud.
    final id = goalId;
    final content = Content(
      id: id,
      title: _workingTitle.trim().isEmpty ? goal.title : _workingTitle.trim(),
      body: _workingBody,
    );
    await contentSvc.upsert(content);
    if (goal.contentId != id) {
      await goalsSvc.setContentId(goalId, id);
    }
    if (!mounted) return;
    setState(() => _original = content);
    _showSnack(AppLocalizations.of(context).lesson_snack_saved);
  }

  Future<void> _uploadHtml() async {
    if (_selectedGoalId == null) return;
    final couldNotReadMessage =
        AppLocalizations.of(context).lesson_snack_couldNotRead;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['html', 'htm'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    String text;
    final bytes = file.bytes;
    if (bytes != null) {
      text = utf8.decode(bytes, allowMalformed: true);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    } else {
      _showSnack(couldNotReadMessage);
      return;
    }

    final fragment = _extractBodyFragment(text);
    setState(() {
      _workingBody = fragment;
      _bodyCtrl.text = fragment;
    });
  }

  /// If [source] looks like a full HTML document, returns the body's inner
  /// HTML. Otherwise returns [source] unchanged. Match is case-insensitive
  /// and dot-all so multi-line bodies work.
  static String _extractBodyFragment(String source) {
    final match = RegExp(
      r'<body\b[^>]*>([\s\S]*?)</body\s*>',
      caseSensitive: false,
    ).firstMatch(source);
    if (match == null) return source;
    return match.group(1)!.trim();
  }

  Future<void> _clearLink() async {
    final goalId = _selectedGoalId;
    if (goalId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l.lesson_unlink_dialog_title),
          content: Text(l.lesson_unlink_dialog_message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.lesson_unlink_dialog_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.lesson_unlink_dialog_confirm),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    await ref.read(goalsServiceProvider).setContentId(goalId, null);
    if (!mounted) return;
    setState(() {
      _original = null;
      _workingTitle = '';
      _workingBody = '';
      _titleCtrl.clear();
      _bodyCtrl.text = '';
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Don't watch poll-driven providers at this level — they tick every 5s
    // and would rebuild the preview WebView along with the tree. The tree
    // watches them inside its own Consumer below.
    return Container(
      color: AppColors.ink0,
      child: Column(
        children: [
          _Toolbar(
            isDirty: _isDirty,
            hasSelection: _selectedGoalId != null,
            onSave: _isDirty ? _save : null,
            onUpload: _selectedGoalId != null ? _uploadHtml : null,
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.ink2),
          Expanded(
            child: _bootstrapping
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      SizedBox(
                        width: 320,
                        child: StreamBuilder<List<Goal>>(
                          stream: _goalsStream,
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                    ConnectionState.waiting &&
                                !snap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snap.hasError) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    AppLocalizations.of(context).lesson_loadError(
                                        snap.error.toString()),
                                  ),
                                ),
                              );
                            }
                            final goals = snap.data ?? const <Goal>[];
                            return Consumer(
                              builder: (context, ref, _) {
                                final modules =
                                    ref.watch(moduleServiceProvider);
                                final contentList =
                                    ref.watch(contentServiceProvider);
                                return _GoalTree(
                                  goals: goals,
                                  modules: modules,
                                  contentById: {
                                    for (final c in contentList) c.id: c,
                                  },
                                  selectedGoalId: _selectedGoalId,
                                  onSelect: _selectGoal,
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const VerticalDivider(width: 1, color: AppColors.ink2),
                      Expanded(child: _buildEditorPane()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPane() {
    final l = AppLocalizations.of(context);
    if (_selectedGoalId == null) {
      return Center(
        child: Text(
          l.lesson_editor_empty_pickSubgoal,
          style: const TextStyle(color: AppColors.fgMute),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.m,
            AppSpacing.lg,
            AppSpacing.s,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: l.lesson_editor_field_title,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              if (_original != null)
                TextButton.icon(
                  onPressed: _clearLink,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: Text(l.lesson_editor_button_unlink),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.ink2),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildHtmlEditor()),
              const VerticalDivider(width: 1, color: AppColors.ink2),
              Expanded(child: _buildPreview()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHtmlEditor() {
    return Container(
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      child: TextField(
        controller: _bodyCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
          color: AppColors.fg,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }

  Widget _buildPreview() {
    if (_workingBody.isEmpty) {
      return Container(
        color: AppColors.ink0,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            AppLocalizations.of(context).lesson_preview_empty,
            style: const TextStyle(color: AppColors.fgFaint, fontSize: 12),
          ),
        ),
      );
    }
    return LessonHtmlView(fragment: _workingBody);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.isDirty,
    required this.hasSelection,
    required this.onSave,
    required this.onUpload,
  });

  final bool isDirty;
  final bool hasSelection;
  final VoidCallback? onSave;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      height: 48,
      color: AppColors.ink1,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Text(
            l.lesson_toolbar_title,
            style: const TextStyle(
              color: AppColors.fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file, size: 16),
            onPressed: onUpload,
            label: Text(l.lesson_toolbar_upload),
          ),
          const SizedBox(width: AppSpacing.s),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            onPressed: hasSelection ? onSave : null,
            label: Text(
                isDirty ? l.lesson_toolbar_save_dirty : l.lesson_toolbar_save),
          ),
        ],
      ),
    );
  }
}

class _GoalTree extends StatelessWidget {
  const _GoalTree({
    required this.goals,
    required this.modules,
    required this.contentById,
    required this.selectedGoalId,
    required this.onSelect,
  });

  final List<Goal> goals;
  final List<Module> modules;
  final Map<String, Content> contentById;
  final String? selectedGoalId;
  final ValueChanged<Goal> onSelect;

  @override
  Widget build(BuildContext context) {
    final byParent = <String?, List<Goal>>{};
    for (final g in goals) {
      byParent.putIfAbsent(g.parentId, () => []).add(g);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => a.order.compareTo(b.order));
    }
    final roots = byParent[null] ?? const <Goal>[];

    final byModule = <String, List<Goal>>{};
    for (final r in roots) {
      final mid = r.moduleId.isEmpty ? Module.defaultId : r.moduleId;
      byModule.putIfAbsent(mid, () => []).add(r);
    }

    final ordered = [...modules]..sort((a, b) => a.order.compareTo(b.order));
    if (ordered.isEmpty || !ordered.any((m) => m.id == Module.defaultId)) {
      ordered.add(Module(
        id: Module.defaultId,
        title: AppLocalizations.of(context).lesson_default_moduleTitle,
        order: 0,
      ));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      children: [
        for (final m in ordered) ...[
          _ModuleHeader(title: m.title),
          for (final root in byModule[m.id] ?? const <Goal>[]) ...[
            _RootRow(goal: root),
            for (final child
                in (byParent[root.id] ?? const <Goal>[]))
              _SubgoalRow(
                goal: child,
                content: child.contentId == null
                    ? null
                    : contentById[child.contentId!],
                selected: selectedGoalId == child.id,
                onTap: () => onSelect(child),
              ),
          ],
        ],
      ],
    );
  }
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.m,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.fgFaint,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _RootRow extends StatelessWidget {
  const _RootRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.s,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        goal.title,
        style: const TextStyle(
          color: AppColors.fg,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SubgoalRow extends StatefulWidget {
  const _SubgoalRow({
    required this.goal,
    required this.content,
    required this.selected,
    required this.onTap,
  });

  final Goal goal;
  final Content? content;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SubgoalRow> createState() => _SubgoalRowState();
}

class _SubgoalRowState extends State<_SubgoalRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final hasContent = widget.goal.contentId != null;
    final label = hasContent
        ? (widget.content?.title ?? widget.goal.title)
        : AppLocalizations.of(context).lesson_subgoal_noContent;

    final bg = widget.selected
        ? AppColors.ink2
        : (_hovering ? AppColors.ink2.withValues(alpha: 0.6) : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 6,
          ),
          color: bg,
          child: Row(
            children: [
              const SizedBox(width: AppSpacing.m),
              Icon(
                hasContent
                    ? Icons.article_outlined
                    : Icons.add_circle_outline,
                size: 14,
                color: hasContent ? AppColors.accent : AppColors.fgFaint,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasContent
                            ? AppColors.fgMute
                            : AppColors.fgFaint,
                        fontSize: 11,
                        fontStyle: hasContent
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
