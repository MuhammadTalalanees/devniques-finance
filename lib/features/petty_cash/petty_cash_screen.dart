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
    final txns = ref.watch(txnListProvider).value ?? const <Txn>[];
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
                        child: Text('No petty cash entries yet.'))
                    : _buildTable(context, ref, items, txns, isAdmin),
              )
            ],
          );
        },
      ),
    );
  }

  /// Ledger-style table (same layout as the main Ledger):
  /// Date | Particulars | Category badge | Debit | Credit |
  /// Balance | Action. Fund = Credit, Spend = Debit; Balance
  /// is the running pot balance after that entry.
  Widget _buildTable(BuildContext context, WidgetRef ref,
      List<PettyCash> items, List<Txn> txns, bool isAdmin) {
    // Running balance after each entry, computed oldest-first
    // and attached by entry id; display stays newest-first.
    final chronological = items.toList()
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.updatedAt.compareTo(b.updatedAt);
      });
    final balanceAfter = <String, double>{};
    var run = 0.0;
    for (final p in chronological) {
      run += p.isFund ? p.amount : -p.amount;
      balanceAfter[p.id] = run;
    }
    final txnById = {for (final t in txns) t.id: t};
    String categoryOf(PettyCash p) {
      if (p.isFund && p.txnId != null) {
        final c = txnById[p.txnId!]?.categoryName ?? '';
        if (c.isNotEmpty) return c;
      }
      return 'Petty Cash';
    }

    TextStyle head() => const TextStyle(
        fontWeight: FontWeight.bold, fontSize: 12);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: isAdmin ? 730 : 630,
        child: Column(
          children: [
            Container(
              color: AppTheme.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text('Date', style: head())),
                  SizedBox(
                      width: 170,
                      child: Text('Particulars', style: head())),
                  SizedBox(
                      width: 110,
                      child: Text('Category', style: head())),
                  SizedBox(
                      width: 90,
                      child: Text('Debit (Rs.)',
                          textAlign: TextAlign.right, style: head())),
                  SizedBox(
                      width: 90,
                      child: Text('Credit (Rs.)',
                          textAlign: TextAlign.right, style: head())),
                  SizedBox(
                      width: 90,
                      child: Text('Balance (Rs.)',
                          textAlign: TextAlign.right, style: head())),
                  if (isAdmin)
                    SizedBox(
                        width: 100, child: Text('Action', style: head())),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _row(context, ref, items[i],
                    categoryOf(items[i]),
                    balanceAfter[items[i].id] ?? 0, isAdmin),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, PettyCash p,
      String category, double balance, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0x11000000), width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(fmtDate(p.date),
                  style: const TextStyle(fontSize: 12))),
          SizedBox(
            width: 170,
            child: Text(
              p.description.isEmpty
                  ? (p.isFund ? 'Funds added' : 'Petty expense')
                  : p.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(category,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          SizedBox(
              width: 90,
              child: Text(p.isFund ? '-' : fmtMoney(p.amount),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12))),
          SizedBox(
              width: 90,
              child: Text(p.isFund ? fmtMoney(p.amount) : '-',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12))),
          SizedBox(
              width: 90,
              child: Text(fmtMoney(balance),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold))),
          if (isAdmin)
            SizedBox(
              width: 100,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 32),
                    ),
                    onPressed: () => _editEntry(context, ref, p),
                    child:
                        const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                  const Text('|',
                      style:
                          TextStyle(fontSize: 12, color: AppTheme.muted)),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.expense,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 32),
                    ),
                    onPressed: () => _deleteEntry(context, ref, p),
                    child: const Text('Delete',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(
      BuildContext context, WidgetRef ref, PettyCash p) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete?'),
            content: const Text('Remove this petty cash entry?'),
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
    if (!confirm) return;
    // Cascade delete: if this petty cash fund entry is linked
    // to a ledger transaction, delete that too.
    if (p.txnId != null) {
      await ref.read(txnRepoProvider).remove(p.txnId!);
    }
    await ref.read(pettyCashRepoProvider).remove(p.id);
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
      );
      await ref.read(pettyCashRepoProvider).update(updated);
    }
    amountCtrl.dispose();
    descCtrl.dispose();
  }
}
