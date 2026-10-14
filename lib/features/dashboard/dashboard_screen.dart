import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';
import '../petty_cash/petty_cash_screen.dart';
import '../transactions/txn_form_screen.dart';
import '../transactions/txn_list_screen.dart' show txnListProvider;

/// Dashboard mirroring the Devniques Expense Tracker:
/// Net Balance / Raised Capital / Operational Expenses / Cash Runway,
/// ledger table, cash-velocity trend, expense allocation, category totals,
/// top-10 expenses and the investors portfolio.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'add_only':
        return 'Add only';
      case 'view_only':
        return 'View only';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(txnListProvider);
    final profile = ref.watch(profileProvider);
    final sync = ref.watch(syncProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final canAdd =
        profile.whenData((p) => p?.canAdd ?? false).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devniques Finance'),
        actions: [
          if (sync.pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text('${sync.pending} pending'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            icon: sync.status == SyncStatus.syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: () =>
                ref.read(syncProvider.notifier).syncNow(),
          ),
        ],
      ),
      body: txns.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => RefreshIndicator(
          onRefresh: () =>
              ref.read(syncProvider.notifier).syncNow(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              profile.when(
                data: (p) => p == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Assalam-o-Alaikum, ${p.name.isEmpty ? p.email : p.name} '
                          '(${_roleLabel(p.role)})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              _KpiGrid(txns: list),
              const SizedBox(height: 16),
              _LedgerCard(txns: list, isAdmin: isAdmin),
              const SizedBox(height: 16),
              _CashSection(txns: list),
              const SizedBox(height: 16),
              _VelocityChart(txns: list),
              const SizedBox(height: 16),
              _CategoryPie(txns: list),
              const SizedBox(height: 16),
              _CategoryTable(txns: list),
              const SizedBox(height: 16),
              _TopExpenses(txns: list),
              const SizedBox(height: 16),
              _InvestorPortfolio(txns: list),
              const SizedBox(height: 16),
              const _PettyCashSummary(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const TxnFormScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add entry'),
            )
          : null,
    );
  }
}

class _KpiGrid extends ConsumerWidget {
  final List<Txn> txns;
  const _KpiGrid({required this.txns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Total Raised Capital: ALL money that came in (credits + investments).
    // NEVER decreases — it's the total capital raised so far.
    final raised = txns
        .where((t) => t.isInflow)
        .fold(0.0, (a, t) => a + t.amount);
    final inflow =
        txns.where((t) => t.isInflow).fold(0.0, (a, t) => a + t.amount);
    final expenses =
        txns.where((t) => t.isDebit).fold(0.0, (a, t) => a + t.amount);
    // Current Net Balance: goes UP on credit, DOWN on expense.
    final balance = inflow - expenses;

    // Petty cash balance: funded − spent (its own separate pot).
    final petty = ref.watch(pettyCashListProvider);
    final pettyBalance = petty.when(
      data: (items) => items.fold(
          0.0, (a, p) => a + (p.isFund ? p.amount : -p.amount)),
      loading: () => 0.0,
      error: (_, __) => 0.0,
    );

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.2,
      children: [
        _Kpi('Current Net Balance', fmtMoney(balance), AppTheme.primary),
        _Kpi('Total Raised Capital', fmtMoney(raised), AppTheme.investment),
        _Kpi('Total Operational Expenses', fmtMoney(expenses),
            AppTheme.expense),
        _Kpi('Petty Cash', fmtMoney(pettyBalance), AppTheme.income),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 17)),
          ],
        ),
      ),
    );
  }
}

/// Full ledger table like Devniques_Account_Management.html:
/// Date | Particulars | Category/Scope badge | Debit | Credit |
/// running Balance | Doc | Action (admin only: Edit | Delete).
class _LedgerCard extends ConsumerWidget {
  final List<Txn> txns;
  final bool isAdmin;
  const _LedgerCard({required this.txns, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Oldest first so the running balance matches the HTML ledger.
    final sorted = txns.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    double running = 0;
    final rows = <_LedgerRow>[];
    for (final t in sorted) {
      running += t.isInflow ? t.amount : -t.amount;
      rows.add(_LedgerRow(txn: t, balance: running));
    }
    // Newest first for display.
    final display = rows.reversed.toList();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Ledger',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (display.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No entries yet.',
                    style: TextStyle(fontSize: 13)),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      AppTheme.primary.withValues(alpha: 0.08)),
                  columnSpacing: 16,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 56,
                  columns: [
                    const DataColumn(
                        label: Text('Date',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                    const DataColumn(
                        label: Text('Particulars',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                    const DataColumn(
                        label: Text('Category / Scope',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                    const DataColumn(
                        numeric: true,
                        label: Text('Debit (Rs.)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                    const DataColumn(
                        numeric: true,
                        label: Text('Credit (Rs.)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                    const DataColumn(
                        numeric: true,
                        label: Text('Balance (Rs.)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                    const DataColumn(
                        label: Text('Doc',
                            style: TextStyle(
                                fontWeight: FontWeight.bold))),
                    if (isAdmin)
                      const DataColumn(
                          label: Text('Action',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold))),
                  ],
                  rows: [
                    for (final r in display)
                      DataRow(cells: [
                        DataCell(Text(fmtDate(r.txn.date),
                            style:
                                const TextStyle(fontSize: 12))),
                        DataCell(SizedBox(
                          width: 170,
                          child: Text(
                            r.txn.description.isEmpty
                                ? '—'
                                : r.txn.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 12),
                          ),
                        )),
                        DataCell(_ScopeBadge(txn: r.txn)),
                        DataCell(Text(
                            r.txn.isDebit
                                ? fmtMoney(r.txn.amount)
                                : '-',
                            style:
                                const TextStyle(fontSize: 12))),
                        DataCell(Text(
                            r.txn.isInflow
                                ? fmtMoney(r.txn.amount)
                                : '-',
                            style:
                                const TextStyle(fontSize: 12))),
                        DataCell(Text(fmtMoney(r.balance),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold))),
                        DataCell((r.txn.receiptUrl ?? '').isEmpty
                            ? const Text('-',
                                style: TextStyle(fontSize: 12))
                            : const Icon(Icons.attach_file,
                                size: 16,
                                color: AppTheme.primary)),
                        if (isAdmin)
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      const Color(0xFFB45309),
                                  padding: EdgeInsets.zero,
                                  minimumSize:
                                      const Size(40, 32),
                                ),
                                onPressed: () =>
                                    Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          TxnFormScreen(
                                              existing:
                                                  r.txn)),
                                ),
                                child: const Text('Edit',
                                    style: TextStyle(
                                        fontSize: 12)),
                              ),
                              const Text('|',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.muted)),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      AppTheme.expense,
                                  padding: EdgeInsets.zero,
                                  minimumSize:
                                      const Size(48, 32),
                                ),
                                onPressed: () =>
                                    _confirmDelete(
                                        context, ref, r.txn),
                                child: const Text('Delete',
                                    style: TextStyle(
                                        fontSize: 12)),
                              ),
                            ],
                          )),
                      ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Txn txn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
            '"${txn.description.isEmpty ? 'this entry' : txn.description}" (${fmtMoney(txn.amount)}) will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.expense),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(txnRepoProvider).remove(txn.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Entry deleted.')));
      }
    }
  }
}

class _LedgerRow {
  final Txn txn;
  final double balance;
  _LedgerRow({required this.txn, required this.balance});
}

/// Category / Scope badge: purple for investor, grey for category —
/// like the HTML ledger.
class _ScopeBadge extends StatelessWidget {
  final Txn txn;
  const _ScopeBadge({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isInv = txn.isInvestment && txn.investor.isNotEmpty;
    final label = isInv
        ? txn.investor
        : (txn.categoryName.isEmpty ? '—' : txn.categoryName);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:
            isInv ? const Color(0xFF7C3AED) : Colors.grey[600],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// Cash-only section: cash in hand, cash used, cash spending grouped
/// by the person who added each entry, and top cash expense categories.
class _CashSection extends ConsumerWidget {
  final List<Txn> txns;
  const _CashSection({required this.txns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(userListProvider);
    final cash = txns.where((t) => t.paymentMethod == 'Cash').toList();
    final cashIn =
        cash.where((t) => t.isInflow).fold(0.0, (a, t) => a + t.amount);
    final cashOut =
        cash.where((t) => t.isDebit).fold(0.0, (a, t) => a + t.amount);
    final inHand = cashIn - cashOut;

    final userMap = users.when(
      data: (list) =>
          {for (final u in list) u.id: u.name.isEmpty ? u.email : u.name},
      loading: () => <String, String>{},
      error: (_, __) => <String, String>{},
    );

    final byPerson = <String, double>{};
    for (final t in cash.where((t) => t.isDebit)) {
      byPerson[t.createdBy] = (byPerson[t.createdBy] ?? 0) + t.amount;
    }
    final personEntries = byPerson.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byCat = <String, double>{};
    for (final t in cash.where((t) => t.isDebit)) {
      final k =
          t.categoryName.isEmpty ? 'Uncategorized' : t.categoryName;
      byCat[k] = (byCat[k] ?? 0) + t.amount;
    }
    final catEntries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cash',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _CashKpi(
                        'Cash in Hand', inHand, AppTheme.income)),
                const SizedBox(width: 12),
                Expanded(
                    child: _CashKpi(
                        'Cash Used', cashOut, AppTheme.expense)),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Cash used by person',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            if (personEntries.isEmpty)
              const Text('No cash spending yet.',
                  style: TextStyle(fontSize: 13)),
            for (final e in personEntries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(userMap[e.key] ?? e.key,
                          style: const TextStyle(fontSize: 13))),
                  Text(fmtMoney(e.value),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.expense)),
                ]),
              ),
            const SizedBox(height: 12),
            const Text('Top cash categories',
                style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            if (catEntries.isEmpty)
              const Text('No cash spending yet.',
                  style: TextStyle(fontSize: 13)),
            for (final e in catEntries.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontSize: 13))),
                  Text(fmtMoney(e.value),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.expense)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _CashKpi extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _CashKpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(fmtMoney(value),
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ],
    );
  }
}

class _VelocityChart extends StatelessWidget {
  final List<Txn> txns;
  const _VelocityChart({required this.txns});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months =
        List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));
    double maxV = 1;
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      final inM = txns
          .where((t) =>
              t.isInflow &&
              t.date.year == m.year &&
              t.date.month == m.month)
          .fold(0.0, (a, t) => a + t.amount);
      final outM = txns
          .where((t) =>
              t.isDebit && t.date.year == m.year && t.date.month == m.month)
          .fold(0.0, (a, t) => a + t.amount);
      if (inM > maxV) maxV = inM;
      if (outM > maxV) maxV = outM;
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: inM, color: AppTheme.income, width: 8),
        BarChartRodData(toY: outM, color: AppTheme.expense, width: 8),
      ]));
    }
    const labels = [
      'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Monthly Cash Velocity Trend',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Row(
              children: [
                _Legend(AppTheme.income, 'Inflow'),
                SizedBox(width: 16),
                _Legend(AppTheme.expense, 'Outflow'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                maxY: maxV * 1.15,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Text(
                              labels[months[v.toInt()].month - 1],
                              style:
                                  const TextStyle(fontSize: 11)))),
                ),
                barGroups: groups,
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}

class _CategoryPie extends StatelessWidget {
  final List<Txn> txns;
  const _CategoryPie({required this.txns});

  @override
  Widget build(BuildContext context) {
    final exp = txns.where((t) => t.isDebit);
    final byCat = <String, double>{};
    for (final t in exp) {
      final k = t.categoryName.isEmpty ? 'Uncategorized' : t.categoryName;
      byCat[k] = (byCat[k] ?? 0) + t.amount;
    }
    if (byCat.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No expenses yet.')));
    }
    final total = byCat.values.fold(0.0, (a, b) => a + b);
    final palette = [
      AppTheme.primary,
      const Color(0xFF0F766E),
      AppTheme.investment,
      const Color(0xFFEA580C),
      const Color(0xFF16A34A),
      const Color(0xFF475569),
    ];
    final entries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expense Allocation Structure',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: PieChart(PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: [
                  for (var i = 0; i < entries.length && i < 8; i++)
                    PieChartSectionData(
                      value: entries[i].value,
                      color: palette[i % palette.length],
                      title:
                          '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                      radius: 60,
                      titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                ],
              )),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < entries.length && i < 8; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  _Legend(palette[i % palette.length], entries[i].key),
                  const Spacer(),
                  Text(fmtMoney(entries[i].value),
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTable extends StatelessWidget {
  final List<Txn> txns;
  const _CategoryTable({required this.txns});

  @override
  Widget build(BuildContext context) {
    final byCat = <String, double>{};
    for (final t in txns.where((t) => t.isDebit)) {
      final k = t.categoryName.isEmpty ? 'Uncategorized' : t.categoryName;
      byCat[k] = (byCat[k] ?? 0) + t.amount;
    }
    final entries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expenses by Category',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text('No expenses yet.',
                  style: TextStyle(fontSize: 13)),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontSize: 13))),
                  Text(fmtMoney(e.value),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.expense)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopExpenses extends StatelessWidget {
  final List<Txn> txns;
  const _TopExpenses({required this.txns});

  @override
  Widget build(BuildContext context) {
    final top = txns.where((t) => t.isDebit).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final items = top.take(10).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top 10 Largest Expenses',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('No expenses yet.',
                  style: TextStyle(fontSize: 13)),
            for (final t in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        t.description.isEmpty
                            ? t.categoryName
                            : t.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(fmtMoney(t.amount),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.expense)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _InvestorPortfolio extends StatelessWidget {
  final List<Txn> txns;
  const _InvestorPortfolio({required this.txns});

  @override
  Widget build(BuildContext context) {
    final byInv = <String, double>{};
    for (final t in txns.where((t) => t.isInvestment)) {
      final k = t.investor.isEmpty ? 'Unknown' : t.investor;
      byInv[k] = (byInv[k] ?? 0) + t.amount;
    }
    final entries = byInv.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Investors Portfolio',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.investment)),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text('No investments recorded yet.',
                  style: TextStyle(fontSize: 13)),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontSize: 13))),
                  Text(fmtMoney(e.value),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.investment)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Petty cash summary on the home page: total spent + quick link.
class _PettyCashSummary extends ConsumerWidget {
  const _PettyCashSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pettyCashListProvider);
    final profile = ref.watch(profileProvider);
    final canAdd =
        profile.whenData((p) => p?.canAdd ?? false).value ?? false;

    return list.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        final funded = items
            .where((p) => p.isFund)
            .fold(0.0, (a, p) => a + p.amount);
        final spent = items
            .where((p) => !p.isFund)
            .fold(0.0, (a, p) => a + p.amount);
        final balance = funded - spent;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Petty Cash',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const PettyCashScreen()),
                      ),
                      child: const Text('View all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        '${items.length} entries',
                        style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 13)),
                    Text(fmtMoney(balance),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: balance < 0
                                ? AppTheme.expense
                                : AppTheme.income)),
                  ],
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  for (final p in items.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.description.isEmpty
                                  ? (p.isFund
                                      ? 'Funds added'
                                      : 'Petty expense')
                                  : p.description,
                              style: const TextStyle(
                                  fontSize: 13),
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                              '${p.isFund ? '+' : '−'} ${fmtMoney(p.amount)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: p.isFund
                                      ? AppTheme.income
                                      : AppTheme.expense)),
                        ],
                      ),
                    ),
                ],
                if (canAdd) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const PettyCashScreen()),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add petty cash'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
