import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/content/content_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/module/module.dart';
import 'package:ai_tutor_python/services/module/module_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:uuid/uuid.dart';

/// Teacher-only "Lesinhoud" view: a tree of module → root goals → subgoals
/// rendered from the goal tree, paired with a markdown editor for the
/// selected subgoal's authored content. The tree is read-only ordering;
/// reorder still happens in `GoalsPage`.
class LessonContentPage extends ConsumerStatefulWidget {
  const LessonContentPage({super.key});

  @override
  ConsumerState<LessonContentPage> createState() => _LessonContentPageState();
}

class _LessonContentPageState extends ConsumerState<LessonContentPage> {
  static const Uuid _uuid = Uuid();

  String? _selectedGoalId;
  Content? _original;
  String _workingTitle = '';
  String _workingBody = '';

  late final CodeController _bodyCtrl;
  late final TextEditingController _titleCtrl;
  late final Stream<List<Goal>> _goalsStream;
  bool _bootstrapping = true;

  @override
  void initState() {
    super.initState();
    _bodyCtrl = CodeController(text: '', language: markdown);
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

    final id = goal.contentId ?? _uuid.v4();
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
    _showSnack('Opgeslagen');
  }

  Future<void> _clearLink() async {
    final goalId = _selectedGoalId;
    if (goalId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lesinhoud loskoppelen?'),
        content: const Text(
          'Het content-document blijft bestaan, maar dit subdoel verwijst er '
          'niet meer naar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Loskoppelen'),
          ),
        ],
      ),
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
    final modules = ref.watch(moduleServiceProvider);
    final contentList = ref.watch(contentServiceProvider);

    return Container(
      color: AppColors.ink0,
      child: Column(
        children: [
          _Toolbar(
            isDirty: _isDirty,
            hasSelection: _selectedGoalId != null,
            onSave: _isDirty ? _save : null,
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
                                    'Fout bij laden: ${snap.error}',
                                  ),
                                ),
                              );
                            }
                            return _GoalTree(
                              goals: snap.data ?? const [],
                              modules: modules,
                              contentById: {
                                for (final c in contentList) c.id: c,
                              },
                              selectedGoalId: _selectedGoalId,
                              onSelect: _selectGoal,
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
    if (_selectedGoalId == null) {
      return const Center(
        child: Text(
          'Kies een subdoel om de lesinhoud te bewerken.',
          style: TextStyle(color: AppColors.fgMute),
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
                  decoration: const InputDecoration(
                    labelText: 'Titel',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              if (_original != null)
                TextButton.icon(
                  onPressed: _clearLink,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('Loskoppelen'),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.ink2),
        Expanded(
          child: Container(
            color: AppColors.ink1,
            child: CodeTheme(
              data: CodeThemeData(styles: const {}),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.m,
                  vertical: AppSpacing.s,
                ),
                child: CodeField(
                  controller: _bodyCtrl,
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.isDirty,
    required this.hasSelection,
    required this.onSave,
  });

  final bool isDirty;
  final bool hasSelection;
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
            'Lesinhoud',
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            onPressed: hasSelection ? onSave : null,
            label: Text(isDirty ? 'Opslaan *' : 'Opslaan'),
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
        title: 'Python basics',
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
        : '(geen lesinhoud)';

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
