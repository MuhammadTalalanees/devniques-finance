import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';
import '../transactions/txn_form_screen.dart';

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
                                    Row(
                                        mainAxisSize:
                                            MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                                Icons.edit,
                                                size: 20),
                                            color:
                                                AppTheme.primary,
                                            tooltip: 'Edit',
                                            onPressed: () =>
                                                _editEntry(context,
                                                    ref, p),
                                          ),
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
                                          // Cascade delete: if this petty cash
                                          // fund entry is linked to a ledger
                                          // transaction, delete that too
                                          if (p.txnId != null) {
                                            await ref
                                                .read(txnRepoProvider)
                                                .remove(p.txnId!);
                                          }
                                          await ref
                                              .read(
                                                  pettyCashRepoProvider)
                                              .remove(p.id);
                                        }
                                      },
                                    ),
                                        ],
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

  Future<void> _editEntry(
      BuildContext context, WidgetRef ref, PettyCash p) async {
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
    final amountCtrl =
        TextEditingController(text: p.amount.toStringAsFixed(0));
    final descCtrl = TextEditingController(text: p.description);
    DateTime date = p.date;
    final allCats = await ref.read(categoryListProvider.future);
    final cats = allCats
        .where((c) => p.isFund
            ? (c.type == 'income' || c.type == 'both')
            : (c.type == 'expense' || c.type == 'both'))
        .toList();
    String? catId = p.categoryId;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(p.isFund ? 'Edit fund entry' : 'Edit petty expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Amount (Rs)'),
              ),
              TextField(
                controller: descCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 18),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => date = picked);
                      }
                    },
                    child: Text(
                        '${date.day}/${date.month}/${date.year}'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: catId,
                decoration:
                    const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('No category')),
                  for (final c in cats)
                    DropdownMenuItem<String?>(
                        value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => catId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final amount = double.tryParse(amountCtrl.text.trim());
      if (amount == null || amount <= 0) {
        amountCtrl.dispose();
        descCtrl.dispose();
        return;
      }
      final updated = PettyCash(
        id: p.id,
        amount: amount,
        description: descCtrl.text.trim(),
        date: date,
        createdBy: p.createdBy,
        updatedAt: DateTime.now(),
        kind: p.kind,
        txnId: p.txnId,
        categoryId: catId,
        categoryName:
            cats.where((c) => c.id == catId).firstOrNull?.name ?? '',
      );
      await ref.read(pettyCashRepoProvider).update(updated);
    }
    amountCtrl.dispose();
    descCtrl.dispose();
  }
}
