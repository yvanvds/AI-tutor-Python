import 'dart:async';

import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/features/account/students_selection.dart';
import 'package:ai_tutor_python/features/account/students_sort.dart';
import 'package:ai_tutor_python/features/account/students_sort_prefs.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sentinel values for the class filter dropdown (#86). Real class names
/// never collide with these: they are trimmed, non-empty teacher text.
const String _kClassFilterAll = '__all__';
const String _kClassFilterNone = '__none__';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _rowsPerPage = 25;
  int _pageIndex = 0;
  String _classFilter = _kClassFilterAll;

  /// Header sort state (#87). Null column index = storage order.
  int? _sortColumnIndex;
  bool _sortAscending = true;

  /// Uids checked for a bulk action (#91). Survives filter/search changes so
  /// a selection can be built up across filters; pruned when an account
  /// disappears from the stream.
  final Set<String> _selectedUids = <String>{};

  final ValueNotifier<Account?> _drawerAccount = ValueNotifier<Account?>(null);

  late final Stream<List<Account>> _accountsStream;
  late final Stream<Map<String, List<Progress>>> _progressStream;
  late final Stream<List<Goal>> _goalsStream;

  @override
  void initState() {
    super.initState();
    _restoreSortChoice();
    _accountsStream = ref
        .read(accountServiceProvider.notifier)
        .streamAllAccounts();
    _progressStream = ref.read(progressServiceProvider).watchAllProgress();
    _goalsStream = ref.read(goalsServiceProvider).streamAllGoals();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hCtrl.dispose();
    _vCtrl.dispose();
    _drawerAccount.dispose();
    super.dispose();
  }

  void _resetPaging() {
    setState(() {
      _pageIndex = 0;
    });
  }

  void _openDrawerFor(Account account) {
    _drawerAccount.value = account;
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.ink0,
      endDrawer: ValueListenableBuilder<Account?>(
        valueListenable: _drawerAccount,
        builder: (context, account, _) {
          if (account == null) return const Drawer(child: SizedBox.shrink());
          return StudentDetailDrawer(account: account);
        },
      ),
      onEndDrawerChanged: (open) {
        if (!open) _drawerAccount.value = null;
      },
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxxl,
          AppSpacing.xxl,
          AppSpacing.xxxl,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PageHeader(),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: StreamBuilder<List<Account>>(
                stream: _accountsStream,
                builder: (context, accountsSnap) {
                  return StreamBuilder<Map<String, List<Progress>>>(
                    stream: _progressStream,
                    builder: (context, progressSnap) {
                      return StreamBuilder<List<Goal>>(
                        stream: _goalsStream,
                        builder: (context, goalsSnap) {
                          return _buildContent(
                            accountsSnap: accountsSnap,
                            progressByUid: progressSnap.data ?? const {},
                            goals: goalsSnap.data ?? const [],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    required AsyncSnapshot<List<Account>> accountsSnap,
    required Map<String, List<Progress>> progressByUid,
    required List<Goal> goals,
  }) {
    if (accountsSnap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (accountsSnap.hasError) {
      return Center(
        child: Text(
          AppLocalizations.of(context)
              .accounts_loadError(accountsSnap.error.toString()),
        ),
      );
    }
    final all = accountsSnap.data ?? [];
    final classes = _distinctClasses(all);
    // A previously selected class may have disappeared (last member
    // reassigned/deleted); fall back to "All" so the dropdown value stays
    // valid — same in-build normalization as `_paginate` does for the page.
    if (_classFilter != _kClassFilterAll &&
        _classFilter != _kClassFilterNone &&
        !classes.contains(_classFilter)) {
      _classFilter = _kClassFilterAll;
    }
    // Same in-build normalization for the bulk selection (#91): drop uids
    // whose account no longer exists so a bulk action can never patch a
    // deleted doc.
    final allUids = {for (final a in all) a.uid};
    _selectedUids.removeWhere((uid) => !allUids.contains(uid));
    final goalById = {for (final g in goals) g.id: g};
    final parentByChild = <String, String?>{
      for (final g in goals) g.id: g.parentId,
    };

    // Per-account derived values (progress, goal titles, status), computed
    // once per account so sorting over the full list and rendering the
    // visible page share the same numbers (#87).
    final rows = [
      for (final a in all)
        StudentRowData.compute(
          a,
          progress: progressByUid[a.uid] ?? const [],
          goalById: goalById,
          parentByChild: parentByChild,
        ),
    ];

    // Pipeline: class filter → search → sort → paginate (#86, #87). Sorting
    // runs on the full filtered set, before pagination, so the order holds
    // across pages.
    final filtered = _searchRows(_filterByClass(rows));
    final sortKey = _sortKeyForColumn(_sortColumnIndex);
    if (sortKey != null) {
      sortStudentRows(filtered, key: sortKey, ascending: _sortAscending);
    }
    final page = _paginate(filtered);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchAndPageSizeRow(classes),
        if (_selectedUids.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          _buildBulkActionBar(),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _buildAccountsTable(
            page.items,
            filteredUids: [for (final r in filtered) r.account.uid],
          ),
        ),
        _buildPaginationBar(page),
      ],
    );
  }

  /// Distinct class names present across all accounts, sorted
  /// case-insensitively; feeds the filter dropdown's options.
  List<String> _distinctClasses(List<Account> all) {
    final names = <String>{
      for (final a in all)
        if (a.className.isNotEmpty) a.className,
    };
    return names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Stage 1 of the list pipeline: narrow to one class, to the accounts
  /// without a class, or pass everything through ("All").
  List<StudentRowData> _filterByClass(List<StudentRowData> all) {
    switch (_classFilter) {
      case _kClassFilterAll:
        return all;
      case _kClassFilterNone:
        return all.where((r) => r.account.className.isEmpty).toList();
      default:
        return all.where((r) => r.account.className == _classFilter).toList();
    }
  }

  /// Stage 2 of the list pipeline: free-text search on name / email.
  List<StudentRowData> _searchRows(List<StudentRowData> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((r) {
      final a = r.account;
      return a.email.toLowerCase().contains(q) ||
          a.firstName.toLowerCase().contains(q) ||
          a.lastName.toLowerCase().contains(q);
    }).toList();
  }

  /// `DataColumn` index per sort key (#87), the one place the table layout
  /// and the sort model meet. The leading select column (#91), Streak, Key
  /// and Actions are not sortable; Status doubles as the last-active sort
  /// (the severity buckets are tie-broken by the last-active timestamp).
  /// The persisted sort (#92) stores the key's *name* and re-derives the
  /// column index through this map, so reordering columns — as #91 did —
  /// can never point a stored choice at the wrong column.
  static const Map<StudentsSortKey, int> _columnBySortKey = {
    StudentsSortKey.email: 1,
    StudentsSortKey.name: 2,
    StudentsSortKey.className: 3,
    StudentsSortKey.currentGoal: 5,
    StudentsSortKey.progress: 6,
    StudentsSortKey.status: 7,
  };

  /// Maps a `DataColumn` index back onto its sort key; null for the
  /// non-sortable columns and for "no sort".
  StudentsSortKey? _sortKeyForColumn(int? columnIndex) {
    for (final entry in _columnBySortKey.entries) {
      if (entry.value == columnIndex) return entry.key;
    }
    return null;
  }

  /// Applies the sort stored on this device (#92), if any. Runs once from
  /// `initState`; until the prefs read completes the table shows storage
  /// order, same as a device with no stored choice.
  Future<void> _restoreSortChoice() async {
    final choice = await loadStudentsSortChoice();
    if (choice == null || !mounted) return;
    setState(() {
      _sortColumnIndex = _columnBySortKey[choice.key];
      _sortAscending = choice.ascending;
    });
  }

  void _handleSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      // A new order means "page 1" is a different slice; jumping back keeps
      // the result deterministic instead of showing a mid-list page.
      _pageIndex = 0;
    });
    // Remember the choice per device (#92). Fire-and-forget: the UI state
    // above is already applied, and a failed prefs write should not block
    // or break the sort itself.
    final key = _sortKeyForColumn(columnIndex);
    if (key != null) {
      unawaited(saveStudentsSortChoice((key: key, ascending: ascending)));
    }
  }

  _PageView _paginate(List<StudentRowData> filtered) {
    final total = filtered.length;
    final maxPage = (total == 0) ? 0 : ((total - 1) ~/ _rowsPerPage);
    if (_pageIndex > maxPage) _pageIndex = 0;
    final start = _pageIndex * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, total);
    final items = (total == 0)
        ? <StudentRowData>[]
        : filtered.sublist(start, end);
    return _PageView(
      items: items,
      total: total,
      start: start,
      end: end,
      maxPage: maxPage,
    );
  }

  Widget _buildSearchAndPageSizeRow(List<String> classes) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l.accounts_search_hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(_resetPaging),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          key: const Key('class-filter'),
          value: _classFilter,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _classFilter = v;
              _pageIndex = 0;
            });
          },
          items: [
            DropdownMenuItem(
              value: _kClassFilterAll,
              child: Text(l.accounts_classFilter_all),
            ),
            DropdownMenuItem(
              value: _kClassFilterNone,
              child: Text(l.accounts_classFilter_none),
            ),
            ...classes.map((c) => DropdownMenuItem(value: c, child: Text(c))),
          ],
        ),
        const SizedBox(width: 12),
        DropdownButton<int>(
          value: _rowsPerPage,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _rowsPerPage = v;
              _pageIndex = 0;
            });
          },
          items: const [10, 25, 50, 100]
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(l.accounts_pageSize_label(v)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  /// Bar shown while a bulk selection exists (#91): the count, the bulk
  /// "assign class" action and a way out.
  Widget _buildBulkActionBar() {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Text(
          l.accounts_bulk_selectedCount(_selectedUids.length),
          style: TextStyle(color: AppColors.fgMute, fontSize: 13),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          key: const Key('bulk-assign-class'),
          onPressed: _bulkAssignClass,
          icon: const Icon(Icons.group_add_outlined, size: 18),
          label: Text(l.accounts_bulk_assignClass),
        ),
        const SizedBox(width: 12),
        TextButton(
          key: const Key('bulk-clear-selection'),
          onPressed: () => setState(_selectedUids.clear),
          child: Text(l.accounts_bulk_clearSelection),
        ),
      ],
    );
  }

  Widget _buildAccountsTable(
    List<StudentRowData> pageItems, {
    required List<String> filteredUids,
  }) {
    return Scrollbar(
      controller: _hCtrl,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _hCtrl,
        primary: false,
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1200),
          child: Scrollbar(
            controller: _vCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              controller: _vCtrl,
              primary: false,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: AppColors.ink2,
                  dataTableTheme: DataTableThemeData(
                    dividerThickness: 1,
                    headingRowHeight: 40,
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 56,
                    headingRowColor: WidgetStatePropertyAll(Colors.transparent),
                    dataRowColor: WidgetStatePropertyAll(Colors.transparent),
                    headingTextStyle: TextStyle(
                      color: AppColors.fgFaint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                    ),
                    dataTextStyle: TextStyle(color: AppColors.fg, fontSize: 13),
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    final l = AppLocalizations.of(context);
                    return DataTable(
                      showCheckboxColumn: false,
                      sortColumnIndex: _sortColumnIndex,
                      sortAscending: _sortAscending,
                      columns: [
                        // Select column (#91). The header checkbox is
                        // scoped to the FULL filtered set (all pages), so
                        // "filter, select all, assign" tags every match in
                        // one action.
                        DataColumn(
                          label: Checkbox(
                            key: const Key('select-all-students'),
                            tristate: true,
                            value: selectAllState(_selectedUids, filteredUids),
                            onChanged: (_) => setState(() {
                              final next = toggleSelectAll(
                                _selectedUids,
                                filteredUids,
                              );
                              _selectedUids
                                ..clear()
                                ..addAll(next);
                            }),
                          ),
                        ),
                        DataColumn(
                          label: Text(l.accounts_column_email),
                          onSort: _handleSort,
                        ),
                        DataColumn(
                          label: Text(l.accounts_column_name),
                          onSort: _handleSort,
                        ),
                        DataColumn(
                          label: Text(l.accounts_column_class),
                          onSort: _handleSort,
                        ),
                        DataColumn(label: Text(l.accounts_column_streak)),
                        DataColumn(
                          label: Text(l.accounts_column_currentGoal),
                          onSort: _handleSort,
                        ),
                        DataColumn(
                          label: Text(l.accounts_column_progress),
                          onSort: _handleSort,
                        ),
                        DataColumn(
                          label: Text(l.accounts_column_status),
                          onSort: _handleSort,
                        ),
                        DataColumn(label: Text(l.accounts_column_key)),
                        DataColumn(label: Text(l.accounts_column_actions)),
                      ],
                      rows: pageItems.map(_buildAccountRow).toList(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildAccountRow(StudentRowData row) {
    // All derived values (goal titles, active-root progress (#89), status)
    // were computed once per account in `_buildContent` so sorting and
    // rendering agree by construction (#87).
    final a = row.account;
    final lastActiveStr = row.lastActive == null
        ? '—'
        : formatTs(row.lastActive!, context);

    final goalTitles = row.goalTitles;
    final overall = row.overallProgress;
    final status = row.status;

    final fullName = [
      a.firstName,
      a.lastName,
    ].where((s) => s.trim().isNotEmpty).join(' ');

    return DataRow(
      onSelectChanged: (_) => _openDrawerFor(a),
      cells: [
        DataCell(
          Checkbox(
            key: Key('select-student-${a.uid}'),
            value: _selectedUids.contains(a.uid),
            onChanged: (v) => setState(() {
              if (v == true) {
                _selectedUids.add(a.uid);
              } else {
                _selectedUids.remove(a.uid);
              }
            }),
          ),
        ),
        DataCell(_EmailCell(email: a.email, lastActive: lastActiveStr)),
        DataCell(Text(fullName.isEmpty ? '—' : fullName)),
        DataCell(
          _ClassBadge(key: Key('class-cell-${a.uid}'), className: a.className),
          showEditIcon: true,
          onTap: () => _editClass(a),
        ),
        DataCell(Text('—', style: TextStyle(color: AppColors.fgFaint))),
        DataCell(
          goalTitles == null
              ? const Text('—')
              : _CurrentGoalCell(
                  rootTitle: goalTitles.rootTitle,
                  subgoalTitle: goalTitles.subgoalTitle,
                ),
        ),
        DataCell(_OverallProgressBar(value: overall)),
        DataCell(_StatusCell(status: status, uid: a.uid)),
        DataCell(
          Switch(
            value: a.mayUseGlobalKey,
            onChanged: (v) => ref
                .read(accountServiceProvider.notifier)
                .setMayUseGlobalKey(uid: a.uid, value: v),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: AppLocalizations.of(context)
                    .accounts_tooltip_deleteAccount,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, a),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaginationBar(_PageView page) {
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l.accounts_pagination_showing(
            page.total == 0 ? 0 : page.start + 1,
            page.end,
            page.total,
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: l.accounts_tooltip_firstPage,
              onPressed: _pageIndex > 0
                  ? () => setState(() => _pageIndex = 0)
                  : null,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: l.accounts_tooltip_previousPage,
              onPressed: _pageIndex > 0
                  ? () => setState(() => _pageIndex -= 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              l.accounts_pagination_pageOf(_pageIndex + 1, page.maxPage + 1),
            ),
            IconButton(
              tooltip: l.accounts_tooltip_nextPage,
              onPressed: _pageIndex < page.maxPage
                  ? () => setState(() => _pageIndex += 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: l.accounts_tooltip_lastPage,
              onPressed: _pageIndex < page.maxPage
                  ? () => setState(() => _pageIndex = page.maxPage)
                  : null,
              icon: const Icon(Icons.last_page),
            ),
          ],
        ),
      ],
    );
  }

  /// Opens the class-assignment dialog once and persists the result to every
  /// selected account (#91) — one [AccountService.setClassName] patch per
  /// account, same as the per-row edit. Saving an empty name clears the
  /// assignment for all of them. On a failure the loop stops and the
  /// selection is kept so the teacher can retry; accounts patched before the
  /// failure keep their new class (each patch is independent).
  Future<void> _bulkAssignClass() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final uids = _selectedUids.toList();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _ClassNameDialog(initial: ''),
    );
    if (result == null) return;
    final service = ref.read(accountServiceProvider.notifier);
    try {
      for (final uid in uids) {
        await service.setClassName(uid: uid, className: result);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.accounts_class_saveFailed(e.toString()))),
      );
      return;
    }
    if (mounted) setState(_selectedUids.clear);
    messenger.showSnackBar(
      SnackBar(content: Text(l.accounts_bulk_assignSuccess(uids.length))),
    );
  }

  /// Opens the class-assignment dialog for one student and persists the
  /// result. Saving an empty name clears the assignment.
  Future<void> _editClass(Account a) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _ClassNameDialog(initial: a.className),
    );
    if (result == null) return;
    try {
      await ref
          .read(accountServiceProvider.notifier)
          .setClassName(uid: a.uid, className: result);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.accounts_class_saveFailed(e.toString()))),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, Account a) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.accounts_delete_dialog_title),
          content: Text(ld.accounts_delete_dialog_message(a.email)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ld.accounts_delete_dialog_cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ld.accounts_delete_dialog_confirm),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await ref.read(accountServiceProvider.notifier).deleteAccountDoc(a.uid);
      messenger.showSnackBar(
        SnackBar(content: Text(l.accounts_delete_success(a.email))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.accounts_delete_failed(e.toString()))),
      );
    }
  }
}

class _PageView {
  final List<StudentRowData> items;
  final int total;
  final int start;
  final int end;
  final int maxPage;
  const _PageView({
    required this.items,
    required this.total,
    required this.start,
    required this.end,
    required this.maxPage,
  });
}

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.accounts_page_title,
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
          l.accounts_page_subtitle,
          style: TextStyle(color: AppColors.fgFaint, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}

/// Class tag shown in the students table: a small pill when assigned,
/// a faint dash when not.
class _ClassBadge extends StatelessWidget {
  const _ClassBadge({super.key, required this.className});

  final String className;

  @override
  Widget build(BuildContext context) {
    if (className.isEmpty) {
      return Text('—', style: TextStyle(color: AppColors.fgFaint));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.ink2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        className,
        style: TextStyle(
          color: AppColors.fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Modal editor for one student's class name. Owns its text controller so
/// disposal happens with the dialog's own lifecycle, not mid-animation.
class _ClassNameDialog extends StatefulWidget {
  const _ClassNameDialog({required this.initial});

  final String initial;

  @override
  State<_ClassNameDialog> createState() => _ClassNameDialogState();
}

class _ClassNameDialogState extends State<_ClassNameDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.accounts_class_dialog_title),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.accounts_class_dialog_hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.accounts_class_dialog_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(l.accounts_class_dialog_save),
        ),
      ],
    );
  }
}

class _EmailCell extends StatelessWidget {
  const _EmailCell({required this.email, required this.lastActive});
  final String email;
  final String lastActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          email,
          style: TextStyle(color: AppColors.fg, fontSize: 13, height: 1.3),
        ),
        if (lastActive != '—')
          Text(
            AppLocalizations.of(context).accounts_email_lastActive(lastActive),
            style: TextStyle(
              color: AppColors.fgFaint,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
      ],
    );
  }
}

/// Two-line "Current goal" cell (#88), same pattern as [_EmailCell]: the
/// root goal's title, then the active subgoal in the smaller/fainter style
/// of the "last active" line. One line when the active goal is a root. Both
/// lines ellipsize inside a bounded width; the tooltip carries the full
/// titles. Root and subgoal stay separate fields so sorting (#87) can key
/// on the root title alone.
class _CurrentGoalCell extends StatelessWidget {
  const _CurrentGoalCell({required this.rootTitle, this.subgoalTitle});

  final String rootTitle;
  final String? subgoalTitle;

  @override
  Widget build(BuildContext context) {
    final sub = subgoalTitle;
    return Tooltip(
      message: sub == null ? rootTitle : '$rootTitle\n$sub',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rootTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.fg, fontSize: 13, height: 1.3),
            ),
            if (sub != null)
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.fgFaint,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverallProgressBar extends StatelessWidget {
  const _OverallProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(color: AppColors.ink2),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Text(
            '${(value * 100).round()}%',
            style: TextStyle(color: AppColors.fgMute, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Status dot + "needs attention" badge per CONDUCTOR_POLICY §8.2. Badge
/// shows the count of unacknowledged strong-signal events for the student;
/// hidden when zero.
class _StatusCell extends ConsumerWidget {
  const _StatusCell({required this.status, required this.uid});

  final StudentStatus status;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final color = switch (status) {
      StudentStatus.active => AppColors.accent2,
      StudentStatus.idle => AppColors.fgFaint,
    };
    final tip = switch (status) {
      StudentStatus.active => l.accounts_status_tooltip_active,
      StudentStatus.idle => l.accounts_status_tooltip_idle,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tip,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        StreamBuilder<int>(
          stream: ref
              .read(turnHistoryServiceProvider)
              .watchStrongUnacknowledgedFor(uid),
          builder: (context, snap) {
            final n = snap.data ?? 0;
            if (n <= 0) return const SizedBox.shrink();
            return Tooltip(
              message: l.accounts_badge_unackTooltip,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
