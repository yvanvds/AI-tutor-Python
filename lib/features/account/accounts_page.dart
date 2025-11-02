import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/account/account.dart';
import '../../data/account/account_providers.dart';

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  final ScrollController _hCtrl = ScrollController(); // horizontal
  final ScrollController _vCtrl = ScrollController(); // vertical

  int _rowsPerPage = 25;
  int _pageIndex = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  void _resetPaging() {
    setState(() {
      _pageIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAv = ref.watch(allAccountsProviderStream);

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: accountsAv.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error loading accounts:\n$e')),
          data: (all) {
            // Filter by search query (email, firstName, lastName)
            final q = _searchCtrl.text.trim().toLowerCase();
            List<Account> filtered = q.isEmpty
                ? all
                : all.where((a) {
                    final email = a.email.toLowerCase();
                    final fn = a.firstName.toLowerCase();
                    final ln = a.lastName.toLowerCase();
                    return email.contains(q) ||
                        fn.contains(q) ||
                        ln.contains(q);
                  }).toList();

            // Pagination
            final total = filtered.length;
            final maxPage = (total == 0) ? 0 : ((total - 1) ~/ _rowsPerPage);
            if (_pageIndex > maxPage) _pageIndex = 0;
            final start = _pageIndex * _rowsPerPage;
            final end = (start + _rowsPerPage).clamp(0, total);
            final pageItems = (total == 0)
                ? <Account>[]
                : filtered.sublist(start, end);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search + rows-per-page
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search by name or email…',
                          border: const OutlineInputBorder(),
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
                ),
                const SizedBox(height: 12),

                // Table header + rows
                Expanded(
                  child: Scrollbar(
                    controller: _hCtrl,
                    thumbVisibility: true,
                    notificationPredicate: (n) =>
                        n.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _hCtrl,
                      primary: false,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 900),
                        child: Scrollbar(
                          controller: _vCtrl,
                          thumbVisibility: true,
                          notificationPredicate: (n) =>
                              n.metrics.axis == Axis.vertical,
                          child: SingleChildScrollView(
                            controller: _vCtrl,
                            primary: false,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Email')),
                                DataColumn(label: Text('First name')),
                                DataColumn(label: Text('Last name')),
                                DataColumn(label: Text('Last active')),
                                DataColumn(label: Text('Global key')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: pageItems.map((a) {
                                final lastActive = _resolveLastActive(a);
                                final lastActiveStr = lastActive == null
                                    ? '—'
                                    : _formatTs(lastActive);

                                return DataRow(
                                  cells: [
                                    DataCell(SelectableText(a.email)),
                                    DataCell(Text(a.firstName)),
                                    DataCell(Text(a.lastName)),
                                    DataCell(Text(lastActiveStr)),
                                    DataCell(
                                      Switch(
                                        value: a.mayUseGlobalKey,
                                        onChanged: (v) async {
                                          await ref.read(
                                            setMayUseGlobalKeyProvider,
                                          )(a.uid, v);
                                          // no need to refresh; stream updates
                                        },
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Delete account',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed: () =>
                                                _confirmDelete(context, a),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Pagination controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${total == 0 ? 0 : start + 1}–$end of $total',
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'First page',
                          onPressed: (_pageIndex > 0)
                              ? () => setState(() => _pageIndex = 0)
                              : null,
                          icon: const Icon(Icons.first_page),
                        ),
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: (_pageIndex > 0)
                              ? () => setState(() => _pageIndex -= 1)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Page ${(_pageIndex + 1)} / ${maxPage + 1}'),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: (_pageIndex < maxPage)
                              ? () => setState(() => _pageIndex += 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                        IconButton(
                          tooltip: 'Last page',
                          onPressed: (_pageIndex < maxPage)
                              ? () => setState(() => _pageIndex = maxPage)
                              : null,
                          icon: const Icon(Icons.last_page),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Timestamp? _resolveLastActive(Account a) {
    // If you later add `lastLoginAt` to the Account map, prefer it here.
    // For now, fall back to updatedAt or createdAt.
    return a.updatedAt ?? a.createdAt;
  }

  String _formatTs(Timestamp ts) {
    final dt = ts.toDate().toLocal();
    // Simple readable format without extra deps:
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _confirmDelete(BuildContext context, Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: Text(
          'This will delete the account profile for:\n\n'
          '${a.email}\n\n'
          'This does NOT delete the FirebaseAuth user. Continue?',
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
      await ref.read(deleteAccountProvider)(a.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted account: ${a.email}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }
}
