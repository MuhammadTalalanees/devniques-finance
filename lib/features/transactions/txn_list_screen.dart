import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';
import 'txn_form_screen.dart';

class TxnListScreen extends ConsumerStatefulWidget {
  const TxnListScreen({super.key});

  @override
  ConsumerState<TxnListScreen> createState() => _TxnListScreenState();
}

class _TxnListScreenState extends ConsumerState<TxnListScreen> {
  String _filter = 'all'; // all | income | expense
  String _query = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(txnListProvider);
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Entries')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search description, category, party…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'income', label: Text('Income')),
                ButtonSegment(value: 'expense', label: Text('Expense')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) =>
                  setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: txns.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) {
                var items = list;
                if (_filter != 'all') {
                  items = items
                      .where((t) => t.type == _filter)
                      .toList();
                }
                if (_query.isNotEmpty) {
                  items = items.where((t) {
                    final hay =
                        '${t.description} ${t.categoryName} ${t.partyName}'
                            .toLowerCase();
                    return hay.contains(_query);
                  }).toList();
                }
                if (items.isEmpty) {
                  return const Center(
                      child: Text('No entries yet. Tap + to add one.'));
                }
                return profile.when(
                  data: (p) => ListView.builder(
                    itemCount: items.length,
                    padding: const EdgeInsets.only(bottom: 88),
                    itemBuilder: (_, i) => _TxnTile(
                      txn: items[i],
                      canModify: p?.isAdmin ?? false,
                    ),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends ConsumerWidget {
  final Txn txn;
  final bool canModify;
  const _TxnTile({required this.txn, required this.canModify});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = txn.isIncome ? AppTheme.income : AppTheme.expense;
    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(
            txn.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: color, size: 20),
      ),
      title: Text(
          txn.description.isEmpty ? txn.categoryName : txn.description,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${txn.categoryName}${txn.partyName.isEmpty ? '' : ' · ${txn.partyName}'} · ${fmtDate(txn.date)}'),
      trailing: Text(
        '${txn.isIncome ? '+' : '−'} ${fmtMoney(txn.amount)}',
        style: TextStyle(
            color: color, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      onTap: canModify
          ? () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TxnFormScreen(existing: txn)))
          : null,
    );
    if (!canModify) return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: tile);
    return Dismissible(
      key: ValueKey(txn.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async => await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Delete entry?'),
              content: const Text('This cannot be undone.'),
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
          false,
      onDismissed: (_) =>
          ref.read(txnRepoProvider).remove(txn.id),
      child: Card(
          margin:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: tile),
    );
  }
}
