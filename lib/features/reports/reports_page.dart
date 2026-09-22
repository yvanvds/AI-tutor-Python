// Teacher-only "Rapporten" page (#148): the per-student grade proposal of
// #99 turned into a class-wide workflow.
//
// Until now the whole chain — compute, justify, adjust, sign off — existed
// only inside the Students drawer, one student at a time, so a passed
// milestone produced nothing until the teacher opened twenty-five drawers.
// This is the same chain as a master-detail page:
//
//   top    milestone selector + class filter + "Genereer rapporten";
//   left   one row per student — name, grade, status chip;
//   right  the full report for the selected student, with next/prev so the
//          class can be walked without going back to the list.
//
// The justification in the right-hand pane is editable (#149): the model
// writes the first draft, the teacher rewrites what they disagree with —
// before signing, and after, once a conversation with the student has made
// the first wording wrong.
//
// The batch itself lives in `ReportBatchService` (#148): the deterministic
// number for everyone in one pass, then the model calls a few at a time,
// with a per-row error state and a per-row retry. This page only drives it
// and shows what comes back.
//
// Publication is the last step (#150), and it is a *milestone* action, not a
// per-student one: sign-off happens student by student over a couple of
// evenings, and "Release" is pressed once, when the grades go into the
// report card, so no student reads their grade days before a classmate.
// `PublishedReportService` writes the frozen, student-facing copies; this
// page shows which rows are out. A rewrite of the prose after release
// (#149) republishes that one student's copy, because leaving the old
// wording on their page would make the app contradict the conversation that
// produced the new one.
//
// Teacher-only by construction, like the drawer section it replaces: the
// section is `isTeacherOnly`, so a student's shell never routes here and
// the "students never see a live score" constraint is kept.
//
// The proposals are loaded once when a milestone is picked, and updated in
// place by the batch and by sign-off, rather than polled: this client is
// the one writing them, and a 5 s poll would fight the run it is watching.

import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal_service.dart';
import 'package:ai_tutor_python/services/grading/milestone.dart';
import 'package:ai_tutor_python/services/grading/milestone_service.dart';
import 'package:ai_tutor_python/services/grading/published_report.dart';
import 'package:ai_tutor_python/services/grading/published_report_service.dart';
import 'package:ai_tutor_python/services/grading/report_batch.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sentinel values for the class filter, same convention as the Students
/// page (#86): a real class name is trimmed, non-empty teacher text and can
/// never collide with these.
const String kReportsClassAll = '__all__';
const String kReportsClassNone = '__none__';

/// Students of one class, in the order the list shows them: by last name,
/// then first name, then email — deterministic for a teacher walking the
/// class with next/prev.
List<Account> reportsStudentsOf(List<Account> all, String classFilter) {
  final filtered = switch (classFilter) {
    kReportsClassAll => all,
    kReportsClassNone => all.where((a) => a.className.isEmpty),
    _ => all.where((a) => a.className == classFilter),
  }.toList();
  filtered.sort((a, b) {
    final last = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
    if (last != 0) return last;
    final first = a.firstName.toLowerCase().compareTo(
      b.firstName.toLowerCase(),
    );
    return first != 0 ? first : a.email.compareTo(b.email);
  });
  return filtered;
}

/// Distinct class names across [all], sorted case-insensitively.
List<String> reportsClassesOf(List<Account> all) {
  final names = <String>{
    for (final a in all)
      if (a.className.isNotEmpty) a.className,
  };
  return names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

String reportStatusLabel(AppLocalizations l, ReportStatus status) =>
    switch (status) {
      ReportStatus.noData => l.reports_status_noData,
      ReportStatus.computed => l.reports_status_computed,
      ReportStatus.justified => l.reports_status_justified,
      ReportStatus.signedOff => l.reports_status_signedOff,
    };

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late final Stream<List<Milestone>> _milestones;
  late final Stream<List<Account>> _accounts;

  String? _milestoneId;
  String _classFilter = kReportsClassAll;
  String? _selectedUid;

  /// The stored docs of the selected milestone, by uid. Seeded from Cosmos
  /// when a milestone is picked and kept up to date by the batch, the
  /// per-row retry and sign-off.
  final Map<String, GradeProposal> _proposals = <String, GradeProposal>{};

  /// Whatever the last run had to say about a row that failed.
  final Map<String, Object> _errors = <String, Object>{};

  /// The published copies of the selected milestone, by uid (#150). A uid
  /// that is absent has not been released: their report exists only on the
  /// teacher's side.
  final Map<String, PublishedReport> _published = <String, PublishedReport>{};

  bool _loading = false;
  bool _running = false;
  int _done = 0;
  int _total = 0;

  /// The release action is in flight.
  bool _releasing = false;

  /// Why the last release failed, if it did.
  String? _releaseError;

  /// Guards the detail pane while a single-student action is in flight.
  bool _busy = false;

  /// The justification of the selected student is open for rewriting (#149).
  bool _editingJustification = false;

  final _gradeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _justificationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _milestones = ref.read(milestoneServiceProvider).watchAll();
    _accounts = ref.read(accountServiceProvider.notifier).streamAllAccounts();
  }

  @override
  void dispose() {
    _gradeCtrl.dispose();
    _noteCtrl.dispose();
    _justificationCtrl.dispose();
    super.dispose();
  }

  GradeProposalService get _service => ref.read(gradeProposalServiceProvider);
  ReportBatchService get _batch => ref.read(reportBatchServiceProvider);

  /// The publication side (#150) — the `reports` container, not to be
  /// confused with [_published], the copies this page has already loaded.
  PublishedReportService get _reports =>
      ref.read(publishedReportServiceProvider);

  /// The signed-off proposals of the selected milestone — what "Release"
  /// publishes. Whole milestone, not the class filter: the filter narrows
  /// what the teacher *looks at*, while only a signature decides what goes
  /// out, so an unsigned class can never be released by accident.
  List<GradeProposal> get _approved => [
    for (final p in _proposals.values)
      if (p.isSignedOff) p,
  ];

  Future<void> _selectMilestone(String id) async {
    setState(() {
      _milestoneId = id;
      _proposals.clear();
      _published.clear();
      _errors.clear();
      _releaseError = null;
      _editingJustification = false;
      _loading = true;
    });
    List<GradeProposal> stored;
    try {
      stored = await _service.getForMilestone(id);
    } catch (_) {
      stored = const [];
    }
    List<PublishedReport> published;
    try {
      published = await _reports.getForMilestone(id);
    } catch (_) {
      published = const [];
    }
    if (!mounted || _milestoneId != id) return;
    setState(() {
      _loading = false;
      for (final p in stored) {
        _proposals[p.uid] = p;
      }
      for (final r in published) {
        _published[r.uid] = r;
      }
      _syncControllers();
    });
  }

  void _selectStudent(String uid) {
    setState(() {
      _selectedUid = uid;
      _editingJustification = false;
      _syncControllers();
    });
  }

  /// Mirrors the selected student's stored text into the edit fields.
  ///
  /// The justification box is left alone while it is open: a batch result
  /// landing on the selected row must not eat half a sentence the teacher
  /// is in the middle of typing.
  void _syncControllers() {
    final p = _selectedUid == null ? null : _proposals[_selectedUid];
    _gradeCtrl.text = p == null ? '' : '${p.finalGrade}';
    _noteCtrl.text = p?.adjustmentNote ?? '';
    if (!_editingJustification) {
      _justificationCtrl.text = p?.justification ?? '';
    }
  }

  void _apply(String uid, ReportBatchResult result) {
    if (!mounted) return;
    setState(() {
      if (result.proposal != null) _proposals[uid] = result.proposal!;
      if (result.error != null) {
        _errors[uid] = result.error!;
      } else {
        _errors.remove(uid);
      }
      if (uid == _selectedUid) _syncControllers();
    });
  }

  Future<void> _generate(Milestone milestone, List<Account> students) async {
    setState(() {
      _running = true;
      _done = 0;
      _total = students.length;
      _errors.clear();
    });
    final language = Localizations.localeOf(context).languageCode;
    try {
      await _batch.run(
        milestone: milestone,
        students: students,
        languageCode: language,
        onResult: (uid, result) {
          _apply(uid, result);
          if (mounted) setState(() => _done += 1);
        },
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _retry(Milestone milestone, Account student) async {
    setState(() => _busy = true);
    try {
      final result = await _batch.runOne(
        milestone: milestone,
        student: student,
        languageCode: Localizations.localeOf(context).languageCode,
      );
      _apply(student.uid, result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stores the teacher's own justification text (#149). The number is not
  /// touched — not the proposal, not the adjustment, not the signature.
  ///
  /// When this student's report is already out, the published copy is
  /// rewritten too (#150): the app must not keep showing the student prose
  /// the teacher has just replaced.
  Future<void> _saveJustification(Milestone milestone, Account student) async {
    final proposal = _proposals[student.uid];
    if (proposal == null) return;
    final text = _justificationCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final edited = await _service.editJustification(
        proposal: proposal,
        text: text,
      );
      if (mounted) setState(() => _editingJustification = false);
      _apply(student.uid, ReportBatchResult(proposal: edited));
      final republished = await _reports.republish(
        milestone: milestone,
        proposal: edited,
      );
      if (republished != null && mounted) {
        setState(() => _published[student.uid] = republished);
      }
    } catch (error) {
      _apply(student.uid, ReportBatchResult(proposal: proposal, error: error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Publishes every approved report of [milestone] (#150).
  ///
  /// One action per milestone, pressed when the grades go into the report
  /// card: sign-off runs student by student over a couple of evenings, and
  /// releasing per student would let one read their grade on Tuesday while
  /// a classmate waits until Thursday. A student with nothing signed is not
  /// published, so a milestone nobody has signed shows a student nothing.
  Future<void> _release(Milestone milestone) async {
    final l = AppLocalizations.of(context);
    final approved = _approved;
    if (approved.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.reports_release_dialog_title),
        content: Text(l.reports_release_dialog_message(approved.length)),
        actions: [
          TextButton(
            key: const Key('reports-release-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.reports_release_dialog_cancel),
          ),
          FilledButton(
            key: const Key('reports-release-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.reports_release_dialog_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _milestoneId != milestone.id) return;
    setState(() {
      _releasing = true;
      _releaseError = null;
    });
    try {
      final published = await _reports.publish(
        milestone: milestone,
        proposals: approved,
      );
      if (!mounted || _milestoneId != milestone.id) return;
      setState(() {
        for (final r in published) {
          _published[r.uid] = r;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _releaseError = '$error');
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  Future<void> _signOff(Account student) async {
    final l = AppLocalizations.of(context);
    final proposal = _proposals[student.uid];
    if (proposal == null) return;
    final grade = int.tryParse(_gradeCtrl.text.trim());
    if (grade == null || grade < 0 || grade > 100) {
      setState(() => _errors[student.uid] = l.reports_grade_adjusted_invalid);
      return;
    }
    setState(() => _busy = true);
    try {
      final signed = await _service.signOff(
        proposal: proposal,
        adjustedGrade: grade,
        note: _noteCtrl.text,
      );
      _apply(student.uid, ReportBatchResult(proposal: signed));
    } catch (error) {
      _apply(student.uid, ReportBatchResult(proposal: proposal, error: error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            l.reports_page_title,
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
            l.reports_page_subtitle,
            style: TextStyle(
              color: AppColors.fgFaint,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Both streams are single-subscription (`pollingStream`), so their
          // builders sit *outside* every conditional branch: a
          // `StreamBuilder` that unmounts and comes back — say because the
          // teacher deleted the last milestone and made a new one — would
          // try to listen a second time and throw.
          Expanded(
            child: StreamBuilder<List<Account>>(
              stream: _accounts,
              builder: (context, accountSnap) {
                final accounts = accountSnap.data ?? const <Account>[];
                final students = reportsStudentsOf(accounts, _classFilter);
                return StreamBuilder<List<Milestone>>(
                  stream: _milestones,
                  builder: (context, milestoneSnap) {
                    if (!milestoneSnap.hasData) {
                      return const LinearProgressIndicator(minHeight: 2);
                    }
                    final milestones = milestoneSnap.data!;
                    if (milestones.isEmpty) {
                      return Text(
                        l.reports_grade_noMilestones,
                        style: TextStyle(color: AppColors.fgFaint),
                      );
                    }
                    // Nothing picked yet, or the pick is gone: fall back to
                    // the earliest milestone.
                    final selected = milestones.firstWhere(
                      (m) => m.id == _milestoneId,
                      orElse: () => milestones.first,
                    );
                    if (_milestoneId != selected.id) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _milestoneId != selected.id) {
                          _selectMilestone(selected.id);
                        }
                      });
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _toolbar(l, milestones, selected, accounts, students),
                        const SizedBox(height: AppSpacing.m),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 320, child: _list(l, students)),
                              const VerticalDivider(width: 24),
                              Expanded(child: _detail(l, selected, students)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(
    AppLocalizations l,
    List<Milestone> milestones,
    Milestone selected,
    List<Account> accounts,
    List<Account> students,
  ) {
    final classes = reportsClassesOf(accounts);
    // A stored class that no longer exists falls back to "all" for display,
    // the way the Students page does it.
    final classValue =
        _classFilter == kReportsClassAll ||
            _classFilter == kReportsClassNone ||
            classes.contains(_classFilter)
        ? _classFilter
        : kReportsClassAll;
    final labelStyle = TextStyle(color: AppColors.fgMute, fontSize: 13);
    final hintStyle = TextStyle(color: AppColors.fgMute, fontSize: 12);
    // A `Wrap`, not a `Row`: the toolbar carries two dropdowns, two actions
    // and their status lines, which is more than a narrow window fits on one
    // line. Each label is grouped with its control so a wrap never separates
    // the two.
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${l.reports_grade_milestone_label}: ', style: labelStyle),
            DropdownButton<String>(
              key: const Key('reports-milestone'),
              value: selected.id,
              onChanged: _running || _releasing
                  ? null
                  : (id) {
                      if (id != null) _selectMilestone(id);
                    },
              items: [
                for (final m in milestones)
                  DropdownMenuItem(value: m.id, child: Text(m.title)),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${l.reports_class_label}: ', style: labelStyle),
            DropdownButton<String>(
              key: const Key('reports-class-filter'),
              value: classValue,
              onChanged: _running
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _classFilter = v);
                    },
              items: [
                DropdownMenuItem(
                  value: kReportsClassAll,
                  child: Text(l.accounts_classFilter_all),
                ),
                DropdownMenuItem(
                  value: kReportsClassNone,
                  child: Text(l.accounts_classFilter_none),
                ),
                ...classes.map(
                  (c) => DropdownMenuItem(value: c, child: Text(c)),
                ),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('reports-generate'),
              onPressed: _running || _releasing || students.isEmpty
                  ? null
                  : () => _generate(selected, students),
              child: Text(l.reports_generate),
            ),
            if (_running) ...[
              const SizedBox(width: AppSpacing.m),
              Text(
                l.reports_generating(_done, _total),
                key: const Key('reports-progress'),
                style: hintStyle,
              ),
            ],
          ],
        ),
        // Release: the milestone's batch action (#150). Enabled once
        // something is signed off — an unapproved class has nothing to
        // publish, and a re-press only refreshes what actually changed.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonal(
              key: const Key('reports-release'),
              onPressed: _running || _releasing || _approved.isEmpty
                  ? null
                  : () => _release(selected),
              child: Text(l.reports_release),
            ),
            if (_published.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.m),
              Text(
                l.reports_release_count(_published.length),
                key: const Key('reports-release-count'),
                style: hintStyle,
              ),
            ],
            if (_releaseError != null) ...[
              const SizedBox(width: AppSpacing.m),
              Text(
                l.reports_release_failed(_releaseError!),
                key: const Key('reports-release-error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _list(AppLocalizations l, List<Account> students) {
    if (_loading) return const LinearProgressIndicator(minHeight: 2);
    if (students.isEmpty) {
      return Text(
        l.reports_noStudents,
        style: TextStyle(color: AppColors.fgFaint),
      );
    }
    return ListView(
      children: [
        for (final student in students)
          _StudentRow(
            key: Key('reports-row-${student.uid}'),
            student: student,
            proposal: _proposals[student.uid],
            failed: _errors.containsKey(student.uid),
            published: _published.containsKey(student.uid),
            selected: student.uid == _selectedUid,
            onTap: () => _selectStudent(student.uid),
          ),
      ],
    );
  }

  Widget _detail(
    AppLocalizations l,
    Milestone milestone,
    List<Account> students,
  ) {
    final index = students.indexWhere((a) => a.uid == _selectedUid);
    if (index < 0) {
      return Center(
        child: Text(
          l.reports_placeholder,
          style: TextStyle(color: AppColors.fgFaint),
        ),
      );
    }
    final student = students[index];
    final theme = Theme.of(context);
    final p = _proposals[student.uid];
    final error = _errors[student.uid];
    final signed = p?.isSignedOff ?? false;
    final published = _published[student.uid];
    String pct(double v) => v.toStringAsFixed(1);

    return ListView(
      padding: const EdgeInsets.only(right: AppSpacing.s),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                student.fullName.trim().isEmpty
                    ? student.email
                    : student.fullName,
                key: const Key('reports-detail-name'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const Key('reports-previous'),
              tooltip: l.reports_previous,
              icon: const Icon(Icons.chevron_left),
              onPressed: index == 0
                  ? null
                  : () => _selectStudent(students[index - 1].uid),
            ),
            IconButton(
              key: const Key('reports-next'),
              tooltip: l.reports_next,
              icon: const Icon(Icons.chevron_right),
              onPressed: index == students.length - 1
                  ? null
                  : () => _selectStudent(students[index + 1].uid),
            ),
          ],
        ),
        Text(
          l.reports_grade_title,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        if (error != null) ...[
          Text(
            l.reports_rowError('$error'),
            key: const Key('reports-detail-error'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (!signed)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              key: const Key('reports-run-one'),
              onPressed: _busy || _running
                  ? null
                  : () => _retry(milestone, student),
              child: Text(
                _busy
                    ? l.reports_grade_button_busy
                    : (p == null
                          ? l.reports_grade_button_compute
                          : l.reports_grade_button_recompute),
              ),
            ),
          ),
        if (p == null) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            l.reports_status_noData,
            key: const Key('reports-detail-noData'),
            style: theme.textTheme.bodySmall,
          ),
        ] else ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${p.proposal}',
                key: const Key('reports-detail-proposal'),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/100 · ${l.reports_grade_proposal_label}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          Text(
            l.reports_grade_masteryEnd(pct(p.mEnd)),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.reports_grade_masteryStart(pct(p.mStart)),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            switch (p.mStartSource) {
              MStartSource.snapshot when p.mStartInexactCount == 0 =>
                l.reports_grade_startSource_snapshot,
              MStartSource.snapshot => l.reports_grade_startSource_snapshotLate(
                p.mStartInexactCount,
              ),
              MStartSource.history => l.reports_grade_startSource_history,
            },
            key: const Key('reports-detail-start-source'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            l.reports_grade_growth(p.g.toStringAsFixed(2)),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.reports_grade_core(p.coreCounted, p.coreTotal),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.reports_grade_extension(p.extensionMastered, p.extensionTotal),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.reports_grade_hard(p.hardCount, p.masteredTotal),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            l.reports_grade_reliability(
              p.staleLoCount,
              p.neverProbedCount,
              p.supervisedTurns,
              p.homeTurns,
            ),
            style: theme.textTheme.bodySmall,
          ),
          Text(
            l.reports_grade_formulaVersion(
              p.formulaVersion,
              formatTs(p.computedAt, context),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l.reports_grade_justification_title,
            style: theme.textTheme.titleSmall,
          ),
          // The prose is the teacher's to rewrite (#149) — before signing,
          // and after, once a conversation with the student has made the
          // first wording wrong. §5 freezes the grade, not the sentence
          // explaining it, and §3.3 keeps the text out of the number, so
          // rewriting one never moves the other.
          if (p.justificationStale) ...[
            const SizedBox(height: 4),
            Text(
              l.reports_grade_justification_stale,
              key: const Key('reports-justification-stale'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_editingJustification) ...[
            const SizedBox(height: 4),
            TextField(
              key: const Key('reports-justification-field'),
              controller: _justificationCtrl,
              minLines: 4,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                labelText: l.reports_grade_justification_field_label,
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilledButton.tonal(
                  key: const Key('reports-justification-save'),
                  onPressed: _busy
                      ? null
                      : () => _saveJustification(milestone, student),
                  child: Text(l.reports_grade_justification_save),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('reports-justification-cancel'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _editingJustification = false;
                          _justificationCtrl.text = p.justification ?? '';
                        }),
                  child: Text(l.reports_grade_justification_cancel),
                ),
              ],
            ),
          ] else ...[
            if (p.justification != null) ...[
              const SizedBox(height: 4),
              SelectableText(
                p.justification!,
                key: const Key('reports-detail-justification'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (p.justificationSource == JustificationSource.edited &&
                p.justificationEditedAt != null)
              Text(
                l.reports_grade_justification_edited(
                  formatTs(p.justificationEditedAt!, context),
                ),
                key: const Key('reports-justification-edited'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('reports-justification-edit'),
                onPressed: _busy || _running
                    ? null
                    : () => setState(() {
                        _editingJustification = true;
                        _justificationCtrl.text = p.justification ?? '';
                      }),
                child: Text(l.reports_grade_justification_edit),
              ),
            ),
          ],
          if (!signed) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const Key('reports-adjusted'),
                    controller: _gradeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.reports_grade_adjusted_label,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('reports-note'),
                    controller: _noteCtrl,
                    decoration: InputDecoration(
                      labelText: l.reports_grade_note_label,
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
                key: const Key('reports-sign-off'),
                onPressed: _busy || _running ? null : () => _signOff(student),
                child: Text(l.reports_grade_button_signOff),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              l.reports_grade_signed(
                formatTs(p.signedOffAt!, context),
                p.finalGrade,
              ),
              key: const Key('reports-signed'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (p.adjustmentNote.isNotEmpty)
              Text(
                l.reports_grade_signed_note(p.adjustmentNote),
                style: theme.textTheme.bodySmall,
              ),
            // Whether this report has actually reached its student (#150).
            // Signed is not published: release is one action per milestone.
            if (published != null) ...[
              const SizedBox(height: 4),
              Text(
                l.reports_published_at(
                  formatTs(published.publishedAt, context),
                ),
                key: const Key('reports-published'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (published.isRepublished)
                Text(
                  l.reports_published_revised(
                    formatTs(published.updatedAt, context),
                  ),
                  key: const Key('reports-published-revised'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ],
        ],
      ],
    );
  }
}

/// One row of the class list: who, what they scored, and where the report
/// stands.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    super.key,
    required this.student,
    required this.proposal,
    required this.failed,
    required this.published,
    required this.selected,
    required this.onTap,
  });

  final Account student;
  final GradeProposal? proposal;
  final bool failed;

  /// The student can read this report (#150).
  final bool published;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = reportStatusOf(proposal);
    final name = student.fullName.trim().isEmpty
        ? student.email
        : student.fullName;
    return ListTile(
      dense: true,
      selected: selected,
      onTap: onTap,
      title: Text(name, overflow: TextOverflow.ellipsis),
      leading: SizedBox(
        width: 34,
        child: Text(
          proposal == null ? '—' : '${proposal!.finalGrade}',
          key: Key('reports-grade-${student.uid}'),
          textAlign: TextAlign.right,
          style: theme.textTheme.titleSmall,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.error_outline,
                key: Key('reports-failed-${student.uid}'),
                size: 16,
                color: theme.colorScheme.error,
              ),
            ),
          if (published)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                key: Key('reports-published-${student.uid}'),
                message: l.reports_published_tooltip,
                child: Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: AppColors.accent,
                ),
              ),
            ),
          _StatusChip(
            key: Key('reports-status-${student.uid}'),
            label: reportStatusLabel(l, status),
            status: status,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.label, required this.status});

  final String label;
  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ReportStatus.noData => AppColors.fgFaint,
      ReportStatus.computed => AppColors.fgMute,
      ReportStatus.justified => AppColors.accent2,
      ReportStatus.signedOff => AppColors.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, height: 1.3),
      ),
    );
  }
}
