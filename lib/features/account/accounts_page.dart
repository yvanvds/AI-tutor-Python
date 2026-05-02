import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:flutter/material.dart';
import '../../services/account/account.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  final ScrollController _hCtrl = ScrollController(); // horizontal
  final ScrollController _vCtrl = ScrollController(); // vertical

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _rowsPerPage = 25;
  int _pageIndex = 0;

  /// Drives the `endDrawer`'s contents. We keep the endDrawer always present
  /// in the tree (an empty placeholder when no row is selected) so that
  /// `openEndDrawer()` works on the first row tap — Scaffold ignores the
  /// call when its `endDrawer` arg is null at build time.
  final ValueNotifier<Account?> _drawerAccount =
      ValueNotifier<Account?>(null);

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
      appBar: AppBar(title: const Text('Accounts')),
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
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<List<Account>>(
          stream: DataService.account.streamAllAccounts(),
          builder: (context, accountsSnap) {
            return StreamBuilder<Map<String, List<Progress>>>(
              stream: DataService.progress.watchAllProgress(),
              builder: (context, progressSnap) {
                return StreamBuilder<List<Goal>>(
                  stream: DataService.goals.streamAllGoals(),
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
        child: Text('Error loading accounts:\n${accountsSnap.error}'),
      );
    }
    final filtered = _filterAccounts(accountsSnap.data ?? []);
    final page = _paginate(filtered);

    final goalById = {for (final g in goals) g.id: g};
    final rootIds = goals
        .where((g) => g.parentId == null && !g.optional)
        .map((g) => g.id)
        .toSet();
    final rootById = {for (final g in goals) if (g.parentId == null) g.id: g};
    final parentByChild = <String, String?>{
      for (final g in goals) g.id: g.parentId,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchAndPageSizeRow(),
        const SizedBox(height: 12),
        Expanded(
          child: _buildAccountsTable(
            page.items,
            progressByUid: progressByUid,
            rootIds: rootIds,
            rootById: rootById,
            goalById: goalById,
            parentByChild: parentByChild,
          ),
        ),
        _buildPaginationBar(page),
      ],
    );
  }

  List<Account> _filterAccounts(List<Account> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((a) {
      return a.email.toLowerCase().contains(q) ||
          a.firstName.toLowerCase().contains(q) ||
          a.lastName.toLowerCase().contains(q);
    }).toList();
  }

  _PageView _paginate(List<Account> filtered) {
    final total = filtered.length;
    final maxPage = (total == 0) ? 0 : ((total - 1) ~/ _rowsPerPage);
    if (_pageIndex > maxPage) _pageIndex = 0;
    final start = _pageIndex * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, total);
    final items = (total == 0) ? <Account>[] : filtered.sublist(start, end);
    return _PageView(
      items: items,
      total: total,
      start: start,
      end: end,
      maxPage: maxPage,
    );
  }

  Widget _buildSearchAndPageSizeRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or email…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(_resetPaging),
          ),
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
                  child: Text('$v / page'),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildAccountsTable(
    List<Account> pageItems, {
    required Map<String, List<Progress>> progressByUid,
    required Set<String> rootIds,
    required Map<String, Goal> rootById,
    required Map<String, Goal> goalById,
    required Map<String, String?> parentByChild,
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
          constraints: const BoxConstraints(minWidth: 1100),
          child: Scrollbar(
            controller: _vCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              controller: _vCtrl,
              primary: false,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('First name')),
                  DataColumn(label: Text('Last name')),
                  DataColumn(label: Text('Last active')),
                  DataColumn(label: Text('Huidig doel')),
                  DataColumn(label: Text('Voortgang')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Global key')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: pageItems
                    .map((a) => _buildAccountRow(
                          a,
                          progress: progressByUid[a.uid] ?? const [],
                          rootIds: rootIds,
                          rootById: rootById,
                          goalById: goalById,
                          parentByChild: parentByChild,
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildAccountRow(
    Account a, {
    required List<Progress> progress,
    required Set<String> rootIds,
    required Map<String, Goal> rootById,
    required Map<String, Goal> goalById,
    required Map<String, String?> parentByChild,
  }) {
    final lastActive = _resolveLastActive(a);
    final lastActiveStr = lastActive == null ? '—' : _formatTs(lastActive);

    final activeRootTitle = _activeRootTitle(
      progress: progress,
      goalById: goalById,
      parentByChild: parentByChild,
    );

    final overall = _overallRootProgress(
      progress: progress,
      rootIds: rootIds,
      goalById: goalById,
      parentByChild: parentByChild,
    );

    final status = computeStudentStatus(progress: progress);

    return DataRow(
      onSelectChanged: (_) => _openDrawerFor(a),
      cells: [
        DataCell(SelectableText(a.email)),
        DataCell(Text(a.firstName)),
        DataCell(Text(a.lastName)),
        DataCell(Text(lastActiveStr)),
        DataCell(Text(activeRootTitle ?? '—')),
        DataCell(_OverallProgressBar(value: overall)),
        DataCell(_StatusDot(status: status)),
        DataCell(
          Switch(
            value: a.mayUseGlobalKey,
            onChanged: (v) => DataService.account
                .setMayUseGlobalKey(uid: a.uid, value: v),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Delete account',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, a),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String? _activeRootTitle({
    required List<Progress> progress,
    required Map<String, Goal> goalById,
    required Map<String, String?> parentByChild,
  }) {
    final ref = mostRecentlyActive(progress);
    if (ref == null) return null;
    final goal = goalById[ref.goalID];
    if (goal == null) return null;
    if (goal.parentId == null) return goal.title;
    final parentId = parentByChild[goal.id];
    if (parentId == null) return goal.title;
    return goalById[parentId]?.title ?? goal.title;
  }

  /// Average of root progress, where each root's progress is the average of
  /// its non-optional children. Empty input → 0.0.
  double _overallRootProgress({
    required List<Progress> progress,
    required Set<String> rootIds,
    required Map<String, Goal> goalById,
    required Map<String, String?> parentByChild,
  }) {
    if (progress.isEmpty || rootIds.isEmpty) return 0.0;
    final byChildOfRoot = <String, List<double>>{};
    for (final p in progress) {
      final goal = goalById[p.goalID];
      if (goal == null) continue;
      // Skip root progress docs (we recompute roots from children).
      if (goal.parentId == null) continue;
      if (goal.optional) continue;
      final parentId = goal.parentId!;
      if (!rootIds.contains(parentId)) continue;
      byChildOfRoot.putIfAbsent(parentId, () => []).add(p.progress);
    }
    if (byChildOfRoot.isEmpty) return 0.0;
    double total = 0;
    for (final list in byChildOfRoot.values) {
      total += list.reduce((a, b) => a + b) / list.length;
    }
    return total / byChildOfRoot.length;
  }

  Widget _buildPaginationBar(_PageView page) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Showing ${page.total == 0 ? 0 : page.start + 1}–${page.end} of ${page.total}',
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'First page',
              onPressed: _pageIndex > 0
                  ? () => setState(() => _pageIndex = 0)
                  : null,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: 'Previous page',
              onPressed: _pageIndex > 0
                  ? () => setState(() => _pageIndex -= 1)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Page ${_pageIndex + 1} / ${page.maxPage + 1}'),
            IconButton(
              tooltip: 'Next page',
              onPressed: _pageIndex < page.maxPage
                  ? () => setState(() => _pageIndex += 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'Last page',
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

  DateTime? _resolveLastActive(Account a) {
    // If you later add `lastLoginAt` to the Account map, prefer it here.
    // For now, fall back to updatedAt or createdAt.
    return a.updatedAt ?? a.createdAt;
  }

  String _formatTs(DateTime ts) {
    final dt = ts.toLocal();
    // Simple readable format without extra deps:
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _confirmDelete(BuildContext context, Account a) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: Text(
          'This will delete the account profile for:\n\n'
          '${a.email}\n\n'
          'This does NOT remove the user from the school account directory. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await DataService.account.deleteAccountDoc(a.uid);
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted account: ${a.email}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }
}

class _PageView {
  final List<Account> items;
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
            child: LinearProgressIndicator(value: value.clamp(0.0, 1.0)),
          ),
          const SizedBox(width: 8),
          Text('${(value * 100).round()}%'),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final StudentStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      StudentStatus.struggling => Colors.red.shade400,
      StudentStatus.active => Colors.green.shade400,
      StudentStatus.idle => Colors.grey.shade400,
    };
    final tip = switch (status) {
      StudentStatus.struggling =>
        'Recente antwoorden tonen veel fouten op dit subdoel.',
      StudentStatus.active => 'Recent vooruitgang geboekt.',
      StudentStatus.idle => 'Geen vooruitgang in de laatste 7 dagen.',
    };
    return Tooltip(
      message: tip,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
