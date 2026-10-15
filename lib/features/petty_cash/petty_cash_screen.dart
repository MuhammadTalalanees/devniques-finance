import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

/// Petty Cash: its own separate pot of money.
/// 'Fund' = money added INTO petty cash. 'Spend' = money spent FROM it.
/// Balance = total funded − total spent. Never touches the main ledger.
class PettyCashScreen extends ConsumerWidget {
  const PettyCashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pettyCashListProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final canAdd = profile.whenData((p) =>
        p != null && (p.isAdmin || p.role == 'add_only')).value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Petty Cash'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download CSV',
            onPressed: () => _downloadCsv(ref),
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              onPressed: () => _showAdd(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: list.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          final funded = items
              .where((p) => p.isFund)
              .fold(0.0, (a, p) => a + p.amount);
          final spent = items
              .where((p) => !p.isFund)
              .fold(0.0, (a, p) => a + p.amount);
          final balance = funded - spent;
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Petty Cash Balance',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          Text(fmtMoney(balance),
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: balance < 0
                                      ? AppTheme.expense
                                      : AppTheme.income)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              'Added: ${fmtMoney(funded)}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.income)),
                          Text(
                              'Spent: ${fmtMoney(spent)}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.expense)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                            'No petty cash entries yet.'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final p = items[i];
                          final fund = p.isFund;
                          return Card(
                            margin:
                                const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    (fund
                                            ? AppTheme.income
                                            : AppTheme.expense)
                                        .withValues(alpha: 0.15),
                                child: Icon(
                                    fund
                                        ? Icons.add_card
                                        : Icons.coffee_outlined,
                                    color: fund
                                        ? AppTheme.income
                                        : AppTheme.expense),
                              ),
                              title: Text(p.description.isEmpty
                                  ? (fund
                                      ? 'Funds added'
                                      : 'Petty expense')
                                  : p.description),
                              subtitle: Text(
                                  '${fund ? 'Added' : 'Spent'} · ${fmtDate(p.date)}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      '${fund ? '+' : '−'} ${fmtMoney(p.amount)}',
                                      style: TextStyle(
                                          fontWeight:
                                              FontWeight.bold,
                                          color: fund
                                              ? AppTheme.income
                                              : AppTheme.expense)),
                                  if (isAdmin)
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete,
                                          size: 20),
                                      color: Colors.redAccent,
                                      onPressed: () async {
                                        final confirm =
                                            await showDialog<
                                                    bool>(
                                                  context:
                                                      context,
                                                  builder: (_) =>
                                                      AlertDialog(
                                                    title: const Text(
                                                        'Delete?'),
                                                    content:
                                                        const Text(
                                                            'Remove this petty cash entry?'),
                                                    actions: [
                                                      TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context,
                                                                  false),
                                                          child: const Text(
                                                              'Cancel')),
                                                      FilledButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  context,
                                                                  true),
                                                          child: const Text(
                                                              'Delete')),
                                                    ],
                                                  ),
                                                ) ??
                                            false;
                                        if (confirm) {
                                          await ref
                                              .read(
                                                  pettyCashRepoProvider)
                                              .remove(p.id);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAdd(BuildContext context, WidgetRef ref) {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final profile = ref.read(profileProvider).value;
    var isFund = false; // false = spend, true = add funds
    var selectedDate = DateTime.now();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Petty Cash'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: true,
                      label: Text('Add funds'),
                      icon: Icon(Icons.add_card,
                          size: 18)),
                  ButtonSegment(
                      value: false,
                      label: Text('Spend'),
                      icon: Icon(
                          Icons.coffee_outlined,
                          size: 18)),
                ],
                selected: {isFund},
                onSelectionChanged: (s) =>
                    setState(() => isFund = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(
                    labelText: 'Amount (Rs)',
                    prefixText: 'Rs '),
                keyboardType:
                    const TextInputType.numberWithOptions(
                        decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                    labelText: isFund
                        ? 'Note (e.g. monthly float)'
                        : 'Description (e.g. lunch)'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    '${selectedDate.day.toString().padLeft(2, '0')} '
                    '${_monthName(selectedDate.month)} '
                    '${selectedDate.year}',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final amount =
                    double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;
                final now = DateTime.now();
                final entry = PettyCash(
                  id: newId(),
                  amount: amount,
                  description: descCtrl.text.trim(),
                  date: selectedDate,
                  createdBy: profile?.id ?? '',
                  updatedAt: now,
                  kind: isFund ? 'fund' : 'spend',
                );
                await ref
                    .read(pettyCashRepoProvider)
                    .add(entry);
                if (context.mounted)
                  Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadCsv(WidgetRef ref) async {
    final items = await ref.read(pettyCashListProvider.future);
    final sorted = items.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final sb = StringBuffer(
        '\uFEFFDate,Description,Fund (Rs.),Spend (Rs.),Balance (Rs.)\n');
    double balance = 0;
    for (final p in sorted) {
      final fund = p.isFund ? p.amount : 0;
      final spend = !p.isFund ? p.amount : 0;
      balance += (fund - spend);
      sb.write(
          '"${p.date.toIso8601String().substring(0, 10)}","${p.description.replaceAll('"', '""')}",$fund,$spend,$balance\n');
    }
    await Share.shareXFiles(
      [XFile.fromData(
          Uint8List.fromList(sb.toString().codeUnits),
          name: 'devniques-petty-cash.csv',
          mimeType: 'text/csv')],
      text: 'Devniques Finance — Petty Cash',
    );
  }
}

String _monthName(int month) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return names[month - 1];
}
