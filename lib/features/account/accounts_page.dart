import 'package:ai_tutor_python/core/date_format.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
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

  final ValueNotifier<Account?> _drawerAccount = ValueNotifier<Account?>(null);

  late final Stream<List<Account>> _accountsStream;
  late final Stream<Map<String, List<Progress>>> _progressStream;
  late final Stream<List<Goal>> _goalsStream;

  @override
  void initState() {
    super.initState();
    _accountsStream =
        ref.read(accountServiceProvider.notifier).streamAllAccounts();
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
                (v) => DropdownMenuItem(value: v, child: Text('$v / page')),
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
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: AppColors.ink2,
                  dataTableTheme: const DataTableThemeData(
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
                    dataTextStyle: TextStyle(
                      color: AppColors.fg,
                      fontSize: 13,
                    ),
                  ),
                ),
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const [
                    DataColumn(label: Text('EMAIL')),
                    DataColumn(label: Text('NAAM')),
                    DataColumn(label: Text('STREAK')),
                    DataColumn(label: Text('HUIDIG DOEL')),
                    DataColumn(label: Text('VOORTGANG')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('SLEUTEL')),
                    DataColumn(label: Text('ACTIES')),
                  ],
                  rows: pageItems
                      .map(
                        (a) => _buildAccountRow(
                          a,
                          progress: progressByUid[a.uid] ?? const [],
                          rootIds: rootIds,
                          rootById: rootById,
                          goalById: goalById,
                          parentByChild: parentByChild,
                        ),
                      )
                      .toList(),
                ),
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
    final lastActive = a.updatedAt ?? a.createdAt;
    final lastActiveStr = lastActive == null ? '—' : formatTs(lastActive);

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

    final fullName = [a.firstName, a.lastName]
        .where((s) => s.trim().isNotEmpty)
        .join(' ');

    return DataRow(
      onSelectChanged: (_) => _openDrawerFor(a),
      cells: [
        DataCell(_EmailCell(email: a.email, lastActive: lastActiveStr)),
        DataCell(Text(fullName.isEmpty ? '—' : fullName)),
        DataCell(
          Text(
            '—',
            style: const TextStyle(color: AppColors.fgFaint),
          ),
        ),
        DataCell(Text(activeRootTitle ?? '—')),
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
    final activeRef = mostRecentlyActive(progress);
    if (activeRef == null) return null;
    final goal = goalById[activeRef.goalID];
    if (goal == null) return null;
    if (goal.parentId == null) return goal.title;
    final parentId = parentByChild[goal.id];
    if (parentId == null) return goal.title;
    return goalById[parentId]?.title ?? goal.title;
  }

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
              onPressed:
                  _pageIndex > 0 ? () => setState(() => _pageIndex = 0) : null,
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
      await ref
          .read(accountServiceProvider.notifier)
          .deleteAccountDoc(a.uid);
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

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Studenten',
          style: TextStyle(
            color: AppColors.fg,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Beheer accounts en volg de voortgang van je studenten.',
          style: TextStyle(
            color: AppColors.fgFaint,
            fontSize: 13,
            height: 1.4,
          ),
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
          style: const TextStyle(
            color: AppColors.fg,
            fontSize: 13,
            height: 1.3,
          ),
        ),
        if (lastActive != '—')
          Text(
            'laatst actief: $lastActive',
            style: const TextStyle(
              color: AppColors.fgFaint,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
      ],
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
            style: const TextStyle(
              color: AppColors.fgMute,
              fontSize: 12,
            ),
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
    final color = switch (status) {
      StudentStatus.active => AppColors.accent2,
      StudentStatus.idle => AppColors.fgFaint,
    };
    final tip = switch (status) {
      StudentStatus.active => 'Recent vooruitgang geboekt.',
      StudentStatus.idle => 'Geen vooruitgang in de laatste 7 dagen.',
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
              message: 'Onbevestigde signaaleventjes',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
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
