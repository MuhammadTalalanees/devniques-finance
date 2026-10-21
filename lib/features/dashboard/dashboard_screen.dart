import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';
import '../attendance/attendance_screen.dart';
import '../petty_cash/petty_cash_screen.dart';
import '../transactions/txn_form_screen.dart';

/// Dashboard mirroring the Devniques Expense Tracker:
/// Net Balance / Raised Capital / Operational Expenses / Cash Runway,
/// ledger table, cash-velocity trend, expense allocation, category totals,
/// top-10 expenses and the investors portfolio.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    final txns = ref.watch(txnListProvider);
    final profile = ref.watch(profileProvider);
    final sync = ref.watch(syncProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final canAdd =
        profile.whenData((p) => p?.canAdd ?? false).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title is a button too: tap = back to the top of Home.
            InkWell(
              onTap: () {
                if (_scroll.hasClients) {
                  _scroll.animateTo(0,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut);
                }
              },
              child: const Text('Devniques Finance'),
            ),
            const SizedBox(width: 14),
            // Human Resources — written exactly like the title
            // (plain text, no button box); tap opens the HR page
            // (attendance of everyone; home no longer carries it).
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AttendanceScreen()),
              ),
              child: Text(MediaQuery.of(context).size.width > 700
                  ? 'Human Resources (HR)'
                  : 'HR'),
            ),
          ],
        ),
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
            controller: _scroll,
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
              _ProfitsSection(txns: list),
              const SizedBox(height: 16),
              // Ledger + Investors side by side on wide screens
              // (the space beside the ledger), stacked on phones.
              LayoutBuilder(
                builder: (context, c) {
                  final ledger = _LedgerCard(txns: list, isAdmin: isAdmin);
                  final investors =
                      _InvestorsPanel(txns: list, isAdmin: isAdmin);
                  if (c.maxWidth > 1000) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: ledger),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: investors),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      ledger,
                      const SizedBox(height: 16),
                      investors,
                    ],
                  );
                },
              ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // On wide screens (web), show 4 in a row; on mobile, 2x2 grid.
        final isWide = constraints.maxWidth > 600;
        final kpis = [
          _Kpi('Current Net Balance', fmtMoney(balance), AppTheme.primary),
          _Kpi('Total Raised Capital', fmtMoney(raised), AppTheme.investment),
          _Kpi('Total Expenses', fmtMoney(expenses),
              AppTheme.expense),
          _Kpi('Petty Cash', fmtMoney(pettyBalance), AppTheme.income),
        ];
        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < kpis.length; i++) ...[
                Expanded(child: kpis[i]),
                if (i < kpis.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.8,
          children: kpis,
        );
      },
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
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
              SizedBox(
                height: 420,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: isAdmin ? 790 : 690,
                    child: Column(
                      children: [
                    // Fixed header
                    Container(
                      color:
                          AppTheme.primary.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 80,
                              child: Text('Date',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 12))),
                          SizedBox(
                              width: 170,
                              child: Text('Particulars',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 12))),
                          SizedBox(
                              width: 110,
                              child: Text('Category',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 12))),
                          SizedBox(
                              width: 90,
                              child: Text('Debit (Rs.)',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 12))),
                          SizedBox(
                              width: 90,
                              child: Text('Credit (Rs.)',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 12))),
                          SizedBox(
                              width: 90,
                              child: Text('Balance (Rs.)',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 12))),
                          SizedBox(
                              width: 40,
                              child: Text('Doc',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      fontSize: 12))),
                          if (isAdmin)
                            SizedBox(
                                width: 100,
                                child: Text('Action',
                                    style: TextStyle(
                                        fontWeight:
                                            FontWeight.bold,
                                        fontSize: 12))),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Virtualized rows — only visible ones render
                    Expanded(
                      child: ListView.builder(
                        itemCount: display.length,
                        itemExtent: 48,
                        itemBuilder: (context, i) {
                          final r = display[i];
                          return _LedgerListRow(
                            row: r,
                            isAdmin: isAdmin,
                            onEdit: () =>
                                Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      TxnFormScreen(
                                          existing:
                                              r.txn)),
                            ),
                            onDelete: () =>
                                _confirmDelete(
                                    context, ref, r.txn),
                          );
                        },
                      ),
                    ),
                  ],
                    ),
                    ),
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
      // Cascade delete: if this is a petty cash fund entry,
      // also delete the linked petty cash record(s).
      if (txn.isPettyCashFund) {
        await ref.read(pettyCashRepoProvider).removeByTxnId(
              txn.id,
              amount: txn.amount,
              dateIso: txn.date.toIso8601String().substring(0, 10),
            );
      }
      await ref.read(txnRepoProvider).remove(txn.id);
      ref.invalidate(pettyCashListProvider);
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

/// Virtualized ledger row — fixed height for ListView.builder.
/// Wrapped in RepaintBoundary to avoid repainting off-screen rows.
class _LedgerListRow extends StatelessWidget {
  final _LedgerRow row;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LedgerListRow({
    required this.row,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final txn = row.txn;
    return RepaintBoundary(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: Color(0x11000000), width: 1)),
        ),
        child: Row(
          children: [
            SizedBox(
                width: 80,
                child: Text(fmtDate(txn.date),
                    style:
                        const TextStyle(fontSize: 12))),
            SizedBox(
              width: 170,
              child: Text(
                txn.description.isEmpty
                    ? '—'
                    : txn.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(
                width: 110,
                child: _ScopeBadge(txn: txn)),
            SizedBox(
                width: 90,
                child: Text(
                    txn.isDebit
                        ? fmtMoney(txn.amount)
                        : '-',
                    textAlign: TextAlign.right,
                    style:
                        const TextStyle(fontSize: 12))),
            SizedBox(
                width: 90,
                child: Text(
                    txn.isInflow
                        ? fmtMoney(txn.amount)
                        : '-',
                    textAlign: TextAlign.right,
                    style:
                        const TextStyle(fontSize: 12))),
            SizedBox(
                width: 90,
                child: Text(fmtMoney(row.balance),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold))),
            SizedBox(
              width: 40,
              child: (txn.receiptUrl ?? '').isEmpty
                  ? const Text('-',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12))
                  : const Icon(Icons.attach_file,
                      size: 16,
                      color: AppTheme.primary),
            ),
            if (isAdmin)
              SizedBox(
                width: 100,
                child: Row(
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
                      onPressed: onEdit,
                      child: const Text('Edit',
                          style:
                              TextStyle(fontSize: 12)),
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
                      onPressed: onDelete,
                      child: const Text('Delete',
                          style:
                              TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
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

/// Profits section on the home page: total profit + monthly breakdown.
class _ProfitsSection extends StatelessWidget {
  final List<Txn> txns;
  const _ProfitsSection({required this.txns});

  @override
  Widget build(BuildContext context) {
    final profits = txns.where((t) => t.isProfit).toList();
    final totalProfit = profits.fold(0.0, (a, t) => a + t.amount);
    // Group by month
    final byMonth = <String, double>{};
    for (final t in profits) {
      final k = '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
      byMonth[k] = (byMonth[k] ?? 0) + t.amount;
    }
    final entries = byMonth.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Profits',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.income)),
                Text(fmtMoney(totalProfit),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.income)),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text('No profits recorded yet.',
                  style: TextStyle(fontSize: 13)),
            for (final e in entries.take(6))
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
                          color: AppTheme.income)),
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
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;

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
                  SizedBox(
                    height: 120,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final p in items)
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
                                  if (isAdmin) ...[
                                    InkWell(
                                      onTap: () =>
                                          _editPettyEntry(
                                              context, ref, p),
                                      child: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(
                                                horizontal: 4),
                                        child: Icon(Icons.edit,
                                            size: 16,
                                            color:
                                                AppTheme.primary),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () =>
                                          _deletePettyEntry(
                                              context, ref, p),
                                      child: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(
                                                horizontal: 4),
                                        child: Icon(Icons.delete,
                                            size: 16,
                                            color:
                                                Colors.redAccent),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
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
                            builder: (_) => const TxnFormScreen(
                                initialType: 'credit')),
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

  Future<void> _editPettyEntry(
      BuildContext context, WidgetRef ref, PettyCash p) async {
    // Fund entry with linked txn → edit via ledger form
    if (p.isFund && p.txnId != null) {
      final txns = await ref.read(txnListProvider.future);
      final linked = txns.where((t) => t.id == p.txnId);
      if (linked.isNotEmpty) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TxnFormScreen(existing: linked.first),
        ));
        return;
      }
    }
    // Otherwise navigate to full petty cash screen for editing
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PettyCashScreen()),
    );
  }

  Future<void> _deletePettyEntry(
      BuildContext context, WidgetRef ref, PettyCash p) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete?'),
            content:
                const Text('Remove this petty cash entry?'),
            actions: [
              TextButton(
                  onPressed: () =>
                      Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      if (p.txnId != null) {
        await ref.read(txnRepoProvider).remove(p.txnId!);
      }
      await ref.read(pettyCashRepoProvider).remove(p.id);
    }
  }
}

/// Home-page Investors panel — beside the Ledger on wide screens,
/// below it on phones. Investors are parties (kind = 'investor')
/// merged with names found on investment entries (same merge as the
/// More -> Investors screen, so nobody ever vanishes).
///
/// The admin enters each investor's share % of Total Raised
/// Capital; the amount is calculated live from that %. Add / Edit /
/// Delete are ADMIN ONLY here (add-only users cannot add).
class _InvestorsPanel extends ConsumerWidget {
  final List<Txn> txns;
  final bool isAdmin;
  const _InvestorsPanel({required this.txns, required this.isAdmin});

  static String _fmtPct(double v) {
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partyListProvider);
    // Total Raised Capital — the same formula as the KPI grid:
    // every inflow that ever came in.
    final raised =
        txns.where((t) => t.isInflow).fold(0.0, (a, t) => a + t.amount);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Investors',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                if (isAdmin)
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _showForm(context, ref, null),
                  ),
              ],
            ),
            parties.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Error: $e'),
              ),
              data: (list) {
                final investors =
                    list.where((p) => p.kind == 'investor').toList();
                final existing = investors.map((p) => p.name).toSet();
                final names = <String>{};
                for (final t in txns.where((t) => t.isInvestment)) {
                  if (t.investor.isNotEmpty) names.add(t.investor);
                }
                for (final name in names) {
                  if (!existing.contains(name)) {
                    investors.add(Party(
                      id: 'txn-$name',
                      name: name,
                      kind: 'investor',
                      phone: '',
                      updatedAt: DateTime.now(),
                    ));
                  }
                }
                if (investors.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No investors yet.',
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.muted)),
                  );
                }
                return Column(
                  children: [
                    for (final p in investors)
                      _investorRow(
                          context, ref, p, raised, _investedOf(p.name)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// What deleting this investor will remove, in plain words.
  String _deleteWarning(Party p) {
    final f = p.name.trim().toLowerCase();
    final mine = txns
        .where((t) =>
            t.isInvestment && t.investor.trim().toLowerCase() == f)
        .toList();
    if (mine.isEmpty) {
      return 'Remove "${p.name}" from investors?';
    }
    final total = mine.fold(0.0, (a, t) => a + t.amount);
    return 'Remove "${p.name}" from investors? His ${mine.length} '
        'investment entries (${fmtMoney(total)}) will also be '
        'deleted from the ledger. This cannot be undone.';
  }

  /// What this investor has actually put in so far (sum of their
  /// investment entries) — shown until the admin sets a share %.
  double _investedOf(String name) {
    final n = name.trim().toLowerCase();
    return txns
        .where((t) =>
            t.isInvestment && t.investor.trim().toLowerCase() == n)
        .fold(0.0, (a, t) => a + t.amount);
  }

  Widget _investorRow(BuildContext context, WidgetRef ref, Party p,
      double raised, double invested) {
    final pct = p.sharePercent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.investment.withValues(alpha: 0.15),
            child:
                Icon(Icons.savings, size: 16, color: AppTheme.investment),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  pct != null
                      ? '${_fmtPct(pct)}%  ·  ${fmtMoney(raised * pct / 100)}'
                      : '${fmtMoney(invested)}  ·  Share % not set',
                  style:
                      const TextStyle(color: AppTheme.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 19),
              color: AppTheme.primary,
              visualDensity: VisualDensity.compact,
              onPressed: () => _showForm(context, ref, p),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 19),
              color: Colors.redAccent,
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDelete(context, ref, p),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Party p) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete investor?'),
            content: Text(_deleteWarning(p)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      await ref.read(partyRepoProvider).removeInvestor(p, txns);
    }
  }

  void _showForm(BuildContext context, WidgetRef ref, Party? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final pctCtrl = TextEditingController(
        text: existing?.sharePercent != null
            ? _fmtPct(existing!.sharePercent!)
            : '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Add Investor' : 'Edit Investor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Investor name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pctCtrl,
              decoration: const InputDecoration(
                  labelText: 'Share % of Total Raised Capital',
                  suffixText: '%'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration:
                  const InputDecoration(labelText: 'Phone (optional)'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final pctText = pctCtrl.text.trim();
              final pct = pctText.isEmpty ? null : double.tryParse(pctText);
              final now = DateTime.now();
              final party = Party(
                id: existing?.id ?? newId(),
                name: name,
                kind: 'investor',
                phone: phoneCtrl.text.trim(),
                email: existing?.email ?? '',
                notes: existing?.notes ?? '',
                sharePercent: pct,
                updatedAt: now,
              );
              final repo = ref.read(partyRepoProvider);
              if (existing == null) {
                await repo.add(party);
              } else {
                await repo.saveInvestor(party, txns,
                    previousName: existing.name);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
