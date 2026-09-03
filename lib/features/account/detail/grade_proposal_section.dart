// "Puntvoorstel" section of the teacher detail drawer (#99): pick a
// milestone, compute the deterministic proposal, ask the model for the
// justification, adjust for what the system cannot see, sign off.
//
// Teacher-only by construction — the drawer is part of the Students page.
// Nothing here is reachable from the student shell, which is how the
// "students never see a live score" constraint is kept.

import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal_service.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/milestone_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GradeProposalSection extends ConsumerStatefulWidget {
  const GradeProposalSection({super.key, required this.account});

  final Account account;

  @override
  ConsumerState<GradeProposalSection> createState() =>
      _GradeProposalSectionState();
}

class _GradeProposalSectionState extends ConsumerState<GradeProposalSection> {
  late final Stream<List<Milestone>> _milestones;
  Milestone? _milestone;
  GradeProposal? _proposal;
  bool _busy = false;
  String? _error;
  final _gradeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _milestones = ref.read(milestoneServiceProvider).watchAll();
  }

  @override
  void dispose() {
    _gradeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  GradeProposalService get _service => ref.read(gradeProposalServiceProvider);

  Future<void> _selectMilestone(Milestone m) async {
    setState(() {
      _milestone = m;
      _proposal = null;
      _error = null;
    });
    final stored = await _service.getStored(widget.account.uid, m.id);
    if (!mounted || _milestone?.id != m.id) return;
    _show(stored);
  }

  void _show(GradeProposal? p) {
    setState(() {
      _proposal = p;
      if (p != null) {
        _gradeCtrl.text = '${p.finalGrade}';
        _noteCtrl.text = p.adjustmentNote;
      }
    });
  }

  Future<void> _run(Future<GradeProposal> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      _show(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compute() => _run(
    () => _service.compute(uid: widget.account.uid, milestone: _milestone!),
  );

  Future<void> _justify() => _run(
    () => _service.writeJustification(
      proposal: _proposal!,
      milestone: _milestone!,
      studentName: widget.account.firstName.isEmpty
          ? widget.account.email
          : widget.account.firstName,
      calibrationLevel: widget.account.calibration.difficulty.name,
      languageCode: Localizations.localeOf(context).languageCode,
    ),
  );

  Future<void> _signOff() async {
    final l = AppLocalizations.of(context);
    final grade = int.tryParse(_gradeCtrl.text.trim());
    if (grade == null || grade < 0 || grade > 100) {
      setState(() => _error = l.drawer_grade_adjusted_invalid);
      return;
    }
    await _run(
      () => _service.signOff(
        proposal: _proposal!,
        adjustedGrade: grade,
        note: _noteCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.drawer_grade_title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          StreamBuilder<List<Milestone>>(
            stream: _milestones,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              final items = snap.data!;
              if (items.isEmpty) {
                return Text(
                  l.drawer_grade_noMilestones,
                  style: theme.textTheme.bodySmall,
                );
              }
              // Nothing picked yet: default to the earliest milestone.
              if (_milestone == null ||
                  !items.any((m) => m.id == _milestone!.id)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _milestone?.id != items.first.id) {
                    _selectMilestone(items.first);
                  }
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('grade-milestone'),
                    initialValue: items.any((m) => m.id == _milestone?.id)
                        ? _milestone!.id
                        : items.first.id,
                    decoration: InputDecoration(
                      labelText: l.drawer_grade_milestone_label,
                      isDense: true,
                    ),
                    items: [
                      for (final m in items)
                        DropdownMenuItem(value: m.id, child: Text(m.title)),
                    ],
                    onChanged: _busy
                        ? null
                        : (id) {
                            final m = items.firstWhere((m) => m.id == id);
                            _selectMilestone(m);
                          },
                  ),
                  const SizedBox(height: 8),
                  if (_milestone != null) _body(theme, l),
                ],
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              key: const Key('grade-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(ThemeData theme, AppLocalizations l) {
    final p = _proposal;
    final signed = p?.isSignedOff ?? false;
    String pct(double v) => v.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!signed)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              key: const Key('grade-compute'),
              onPressed: _busy ? null : _compute,
              child: Text(
                _busy
                    ? l.drawer_grade_button_busy
                    : (p == null
                          ? l.drawer_grade_button_compute
                          : l.drawer_grade_button_recompute),
              ),
            ),
          ),
        if (p != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${p.proposal}',
                key: const Key('grade-proposal'),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/100 · ${l.drawer_grade_proposal_label}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          Text(
            l.drawer_grade_masteryEnd(pct(p.mEnd)),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.drawer_grade_masteryStart(pct(p.mStart)),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.drawer_grade_growth(p.g.toStringAsFixed(2)),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.drawer_grade_core(p.coreCounted, p.coreTotal),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.drawer_grade_extension(p.extensionMastered, p.extensionTotal),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.drawer_grade_hard(p.hardCount, p.masteredTotal),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            l.drawer_grade_reliability(
              p.staleLoCount,
              p.neverProbedCount,
              p.supervisedTurns,
              p.homeTurns,
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.drawer_grade_formulaVersion(
              p.formulaVersion,
              formatTs(p.computedAt, context),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l.drawer_grade_justification_title,
            style: theme.textTheme.titleSmall,
          ),
          if (p.justification != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              p.justification!,
              key: const Key('grade-justification'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (!signed) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const Key('grade-justify'),
                onPressed: _busy ? null : _justify,
                child: Text(
                  _busy
                      ? l.drawer_grade_button_busy
                      : l.drawer_grade_button_justify,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const Key('grade-adjusted'),
                    controller: _gradeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.drawer_grade_adjusted_label,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('grade-note'),
                    controller: _noteCtrl,
                    decoration: InputDecoration(
                      labelText: l.drawer_grade_note_label,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const Key('grade-sign-off'),
                onPressed: _busy ? null : _signOff,
                child: Text(l.drawer_grade_button_signOff),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              l.drawer_grade_signed(
                formatTs(p.signedOffAt!, context),
                p.finalGrade,
              ),
              key: const Key('grade-signed'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (p.adjustmentNote.isNotEmpty)
              Text(
                l.drawer_grade_signed_note(p.adjustmentNote),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ],
    );
  }
}
