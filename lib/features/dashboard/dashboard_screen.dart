import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(txnListProvider);
    final profile = ref.watch(profileProvider);
    final sync = ref.watch(syncProvider);

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
                          '(${p.isAdmin ? 'Admin' : 'Staff — add only'})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium,
                        ),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              _MonthCards(txns: list),
              const SizedBox(height: 16),
              _MonthlyChart(txns: list),
              const SizedBox(height: 16),
              _CategoryPie(txns: list),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthCards extends StatelessWidget {
  final List<Txn> txns;
  const _MonthCards({required this.txns});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final m = txns.where(
        (t) => t.date.year == now.year && t.date.month == now.month);
    final income =
        m.where((t) => t.isIncome).fold(0.0, (a, t) => a + t.amount);
    final expense =
        m.where((t) => !t.isIncome).fold(0.0, (a, t) => a + t.amount);
    return Row(
      children: [
        Expanded(
            child: _StatCard(
                'Income', income, AppTheme.income, fmtMonth(now))),
        const SizedBox(width: 12),
        Expanded(
            child: _StatCard(
                'Expense', expense, AppTheme.expense, fmtMonth(now))),
        const SizedBox(width: 12),
        Expanded(
            child: _StatCard('Net', income - expense,
                AppTheme.blue, fmtMonth(now))),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final String sub;
  const _StatCard(this.label, this.value, this.color, this.sub);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 12)),
            const SizedBox(height: 4),
            Text(fmtMoney(value),
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Text(sub,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final List<Txn> txns;
  const _MonthlyChart({required this.txns});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(
        6, (i) => DateTime(now.year, now.month - 5 + i));
    double maxV = 1;
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      final inM = txns
          .where((t) =>
              t.isIncome &&
              t.date.year == m.year &&
              t.date.month == m.month)
          .fold(0.0, (a, t) => a + t.amount);
      final exM = txns
          .where((t) =>
              !t.isIncome &&
              t.date.year == m.year &&
              t.date.month == m.month)
          .fold(0.0, (a, t) => a + t.amount);
      if (inM > maxV) maxV = inM;
      if (exM > maxV) maxV = exM;
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: inM, color: AppTheme.income, width: 8),
        BarChartRodData(toY: exM, color: AppTheme.expense, width: 8),
      ]));
    }
    const labels = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Last 6 months',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Row(
              children: const [
                _Legend(AppTheme.income, 'Income'),
                SizedBox(width: 16),
                _Legend(AppTheme.expense, 'Expense'),
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
                              style: const TextStyle(fontSize: 11)))),
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
          width: 12, height: 12,
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
    final now = DateTime.now();
    final exp = txns.where((t) =>
        !t.isIncome && t.date.year == now.year && t.date.month == now.month);
    final byCat = <String, double>{};
    for (final t in exp) {
      final k = t.categoryName.isEmpty ? 'Uncategorized' : t.categoryName;
      byCat[k] = (byCat[k] ?? 0) + t.amount;
    }
    if (byCat.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No expenses this month yet.')));
    }
    final total = byCat.values.fold(0.0, (a, b) => a + b);
    final palette = [
      AppTheme.blue, AppTheme.cyan, const Color(0xFFA78BFA),
      const Color(0xFFFB923C), const Color(0xFF4ADE80),
      const Color(0xFFFBBF24),
    ];
    final entries = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expenses by category',
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
            for (var i = 0;
                i < entries.length && i < 8;
                i++)
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
