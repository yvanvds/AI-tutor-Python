// Teacher-only "Mijlpalen" page (#99, PUNTENFORMULE §2.1): declare, per
// grading period, which subgoals' learning objectives should be known by
// which report date, and answer the Angoff question per objective — does a
// student who *just* passes master it (core, gates the 50) or not
// (extension, buys points above it) — plus the level the core has to be
// demonstrated at.
//
// Left: the list of milestones. Right: the editor for the selected one.
// Dates are typed as `YYYY-MM-DD` (a calendar button fills the field), so
// the form is driveable without a picker dialog.

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/milestone_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// `YYYY-MM-DD` of the local calendar day.
String formatIsoDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

/// Parses `YYYY-MM-DD` as local midnight; anything else is `null`.
DateTime? parseIsoDate(String text) {
  final m = RegExp(r'^\s*(\d{4})-(\d{2})-(\d{2})\s*$').firstMatch(text);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final parsed = DateTime(y, mo, d);
  if (parsed.year != y || parsed.month != mo || parsed.day != d) return null;
  return parsed;
}

String difficultyLabel(AppLocalizations l, QuestionDifficulty d) {
  switch (d) {
    case QuestionDifficulty.easy:
      return l.milestones_difficulty_easy;
    case QuestionDifficulty.medium:
      return l.milestones_difficulty_medium;
    case QuestionDifficulty.hard:
      return l.milestones_difficulty_hard;
  }
}

class MilestonesPage extends ConsumerStatefulWidget {
  const MilestonesPage({super.key});

  @override
  ConsumerState<MilestonesPage> createState() => _MilestonesPageState();
}

class _MilestonesPageState extends ConsumerState<MilestonesPage> {
  static const Uuid _uuid = Uuid();

  late final Stream<List<Milestone>> _milestonesStream;
  late final Stream<List<Goal>> _goalsStream;

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _periodStartCtrl = TextEditingController();
  final _dueAtCtrl = TextEditingController();

  /// Id of the milestone being edited; `null` when nothing is selected.
  String? _editingId;
  bool _isNew = false;
  QuestionDifficulty _difficulty = QuestionDifficulty.medium;
  final List<String> _subgoalIds = <String>[];
  final Set<String> _coreKeys = <String>{};
  bool _busy = false;
  String? _goalsError;

  @override
  void initState() {
    super.initState();
    _milestonesStream = ref.read(milestoneServiceProvider).watchAll();
    _goalsStream = ref.read(goalsServiceProvider).streamAllGoals();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _periodStartCtrl.dispose();
    _dueAtCtrl.dispose();
    super.dispose();
  }

  void _startNew() {
    setState(() {
      _editingId = _uuid.v4();
      _isNew = true;
      _titleCtrl.text = '';
      _periodStartCtrl.text = formatIsoDate(DateTime.now());
      _dueAtCtrl.text = '';
      _difficulty = QuestionDifficulty.medium;
      _subgoalIds.clear();
      _coreKeys.clear();
      _goalsError = null;
    });
  }

  void _select(Milestone m) {
    setState(() {
      _editingId = m.id;
      _isNew = false;
      _titleCtrl.text = m.title;
      _periodStartCtrl.text = formatIsoDate(m.periodStart);
      _dueAtCtrl.text = formatIsoDate(m.dueAt);
      _difficulty = m.expectedDifficulty;
      _subgoalIds
        ..clear()
        ..addAll(m.subgoalIds);
      _coreKeys
        ..clear()
        ..addAll(m.coreLoKeys);
      _goalsError = null;
    });
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final initial = parseIsoDate(ctrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 2),
    );
    if (picked == null) return;
    setState(() => ctrl.text = formatIsoDate(picked));
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final id = _editingId;
    if (id == null) return;
    final valid = _formKey.currentState?.validate() ?? false;
    final start = parseIsoDate(_periodStartCtrl.text);
    final due = parseIsoDate(_dueAtCtrl.text);
    if (!valid || start == null || due == null) return;
    if (_subgoalIds.isEmpty) {
      setState(() => _goalsError = l.milestones_validation_goals);
      return;
    }
    final milestone = Milestone(
      id: id,
      title: _titleCtrl.text.trim(),
      periodStart: start,
      dueAt: due,
      expectedDifficulty: _difficulty,
      subgoalIds: List.of(_subgoalIds),
      coreLoKeys: Set.of(_coreKeys),
    );
    setState(() => _busy = true);
    try {
      await ref.read(milestoneServiceProvider).upsert(milestone);
      if (!mounted) return;
      setState(() => _isNew = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.milestones_saved)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final id = _editingId;
    if (id == null || _isNew) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.milestones_delete_dialog_title),
        content: Text(l.milestones_delete_dialog_message(_titleCtrl.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.milestones_delete_dialog_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.milestones_delete_dialog_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(milestoneServiceProvider).delete(id);
      if (!mounted) return;
      setState(() {
        _editingId = null;
        _isNew = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.milestones_deleted)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSubgoal(Goal subgoal, bool included, List<Goal> ordered) {
    setState(() {
      _goalsError = null;
      if (included) {
        if (!_subgoalIds.contains(subgoal.id)) {
          _subgoalIds.add(subgoal.id);
          // Keep curriculum order, which is what the formula and the
          // justification list them in.
          final position = {
            for (var i = 0; i < ordered.length; i++) ordered[i].id: i,
          };
          _subgoalIds.sort(
            (a, b) =>
                (position[a] ?? 1 << 30).compareTo(position[b] ?? 1 << 30),
          );
        }
      } else {
        _subgoalIds.remove(subgoal.id);
        _coreKeys.removeWhere((k) => k.startsWith('${subgoal.id}/'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.milestones_page_title,
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.milestones_page_subtitle,
            style: TextStyle(
              color: AppColors.fgFaint,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 300, child: _buildList(l)),
                const VerticalDivider(width: 24),
                Expanded(child: _buildEditor(l)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _startNew,
          icon: const Icon(Icons.add),
          label: Text(l.milestones_button_new),
        ),
        const SizedBox(height: AppSpacing.m),
        Expanded(
          child: StreamBuilder<List<Milestone>>(
            stream: _milestonesStream,
            builder: (context, snap) {
              final items = snap.data ?? const <Milestone>[];
              if (!snap.hasData) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              if (items.isEmpty && !_isNew) {
                return Text(
                  l.milestones_list_empty,
                  style: TextStyle(color: AppColors.fgFaint),
                );
              }
              return ListView(
                children: [
                  for (final m in items)
                    ListTile(
                      key: Key('milestone-row-${m.id}'),
                      selected: m.id == _editingId,
                      title: Text(m.title),
                      subtitle: Text(formatIsoDate(m.dueAt)),
                      onTap: _busy ? null : () => _select(m),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(AppLocalizations l) {
    if (_editingId == null) {
      return Center(
        child: Text(
          l.milestones_placeholder,
          style: TextStyle(color: AppColors.fgFaint),
        ),
      );
    }
    return StreamBuilder<List<Goal>>(
      stream: _goalsStream,
      builder: (context, snap) {
        final goals = snap.data ?? const <Goal>[];
        final roots = goals.where((g) => g.parentId == null).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        final childrenByParent = <String, List<Goal>>{};
        for (final g in goals.where((g) => g.parentId != null)) {
          childrenByParent.putIfAbsent(g.parentId!, () => []).add(g);
        }
        for (final list in childrenByParent.values) {
          list.sort((a, b) => a.order.compareTo(b.order));
        }
        final ordered = <Goal>[
          for (final r in roots) ...?childrenByParent[r.id],
        ];
        final goalById = {for (final g in goals) g.id: g};
        var core = 0;
        var extension = 0;
        for (final sid in _subgoalIds) {
          for (final o in goalById[sid]?.objectives ?? const []) {
            if (_coreKeys.contains(Milestone.loKey(sid, o.id))) {
              core += 1;
            } else {
              extension += 1;
            }
          }
        }

        return Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                key: const Key('milestone-title'),
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: l.milestones_field_title,
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? l.milestones_validation_title
                    : null,
              ),
              const SizedBox(height: AppSpacing.m),
              Row(
                children: [
                  Expanded(
                    child: _dateField(
                      l,
                      key: const Key('milestone-period-start'),
                      controller: _periodStartCtrl,
                      label: l.milestones_field_periodStart,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: _dateField(
                      l,
                      key: const Key('milestone-due-at'),
                      controller: _dueAtCtrl,
                      label: l.milestones_field_dueAt,
                      validator: (v) {
                        final due = parseIsoDate(v ?? '');
                        if (due == null) return l.milestones_validation_date;
                        final start = parseIsoDate(_periodStartCtrl.text);
                        if (start != null && !due.isAfter(start)) {
                          return l.milestones_validation_order;
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                l.milestones_field_expectedDifficulty,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.s),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<QuestionDifficulty>(
                  segments: [
                    for (final d in QuestionDifficulty.values)
                      ButtonSegment(
                        value: d,
                        label: Text(difficultyLabel(l, d)),
                      ),
                  ],
                  selected: {_difficulty},
                  onSelectionChanged: (s) =>
                      setState(() => _difficulty = s.first),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l.milestones_goals_heading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                l.milestones_goals_hint,
                style: TextStyle(color: AppColors.fgFaint, fontSize: 12),
              ),
              if (_goalsError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _goalsError!,
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: AppSpacing.s),
              for (final root in roots) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s),
                  child: Text(
                    root.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final sub in childrenByParent[root.id] ?? const <Goal>[])
                  _subgoalRow(l, sub, ordered),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  FilledButton(
                    key: const Key('milestone-save'),
                    onPressed: _busy ? null : _save,
                    child: Text(l.milestones_button_save),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  if (!_isNew)
                    OutlinedButton(
                      onPressed: _busy ? null : _delete,
                      child: Text(l.milestones_button_delete),
                    ),
                  const Spacer(),
                  Text(
                    l.milestones_summary(core, extension),
                    style: TextStyle(color: AppColors.fgFaint, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }

  Widget _dateField(
    AppLocalizations l, {
    required Key key,
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: l.milestones_field_pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () => _pickDate(controller),
        ),
      ),
      validator:
          validator ??
          (v) => parseIsoDate(v ?? '') == null
              ? l.milestones_validation_date
              : null,
    );
  }

  Widget _subgoalRow(AppLocalizations l, Goal sub, List<Goal> ordered) {
    final included = _subgoalIds.contains(sub.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: Key('milestone-subgoal-${sub.id}'),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: included,
          title: Text(sub.title),
          onChanged: (v) => _toggleSubgoal(sub, v ?? false, ordered),
        ),
        if (included)
          for (final o in sub.objectives)
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 8, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      o.statement,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  _CoreToggle(
                    key: Key('milestone-lo-${Milestone.loKey(sub.id, o.id)}'),
                    isCore: _coreKeys.contains(Milestone.loKey(sub.id, o.id)),
                    coreLabel: l.milestones_lo_core,
                    extensionLabel: l.milestones_lo_extension,
                    onChanged: (core) => setState(() {
                      final key = Milestone.loKey(sub.id, o.id);
                      if (core) {
                        _coreKeys.add(key);
                      } else {
                        _coreKeys.remove(key);
                      }
                    }),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// The Angoff answer for one learning objective.
class _CoreToggle extends StatelessWidget {
  const _CoreToggle({
    super.key,
    required this.isCore,
    required this.coreLabel,
    required this.extensionLabel,
    required this.onChanged,
  });

  final bool isCore;
  final String coreLabel;
  final String extensionLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        ButtonSegment(value: true, label: Text(coreLabel)),
        ButtonSegment(value: false, label: Text(extensionLabel)),
      ],
      selected: {isCore},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
