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
  String _filter = 'all'; // all | debit | credit | investment | profit
  String _query = '';

  String get _fabType {
    if (_filter == 'debit' ||
        _filter == 'credit' ||
        _filter == 'investment' ||
        _filter == 'profit') {
      return _filter;
    }
    return 'debit';
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(txnListProvider);
    final profile = ref.watch(profileProvider);
    final canAdd = profile.whenData(
            (p) => p != null && p.role != 'view_only')
        .value ??
        false;

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
                ButtonSegment(value: 'debit', label: Text('Expenses')),
                ButtonSegment(value: 'credit', label: Text('Credits')),
                ButtonSegment(value: 'investment', label: Text('Investments')),
                ButtonSegment(value: 'profit', label: Text('Profits')),
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
                        '${t.description} ${t.categoryName} ${t.partyName} ${t.investor}'
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
      floatingActionButton: canAdd
          ? Builder(
              builder: (ctx) {
                final currentFilter = _filter;
                String formType = 'debit';
                if (currentFilter == 'credit' ||
                    currentFilter == 'investment' ||
                    currentFilter == 'profit' ||
                    currentFilter == 'debit') {
                  formType = currentFilter;
                }
                return FloatingActionButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            TxnFormScreen(initialType: formType)),
                  ),
                  child: const Icon(Icons.add),
                );
              },
            )
          : null,
    );
  }
}

class _TxnTile extends ConsumerWidget {
  final Txn txn;
  final bool canModify;
  const _TxnTile({required this.txn, required this.canModify});

  /// Look up the display name for a user ID (for "Added by" info).
  Future<String> _addedByName(WidgetRef ref, String userId) async {
    try {
      final users = await ref.read(userListProvider.future);
      final match = users.where((u) => u.id == userId);
      if (match.isNotEmpty) {
        final u = match.first;
        return u.name.isEmpty ? u.email : u.name;
      }
    } catch (_) {}
    return userId.substring(0, userId.length > 8 ? 8 : userId.length);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = txn.isDebit
        ? AppTheme.expense
        : (txn.isInvestment ? AppTheme.investment : AppTheme.income);
    final icon = txn.isDebit
        ? Icons.arrow_upward
        : (txn.isInvestment ? Icons.savings : Icons.arrow_downward);
    final scope = txn.isInvestment
        ? txn.investor
        : (txn.categoryName.isEmpty ? txn.partyName : txn.categoryName);
    // Payment method badge (Cash, Bank, etc.) - always visible
    final paymentBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        txn.paymentMethod.isEmpty ? 'Cash' : txn.paymentMethod,
        style: TextStyle(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
                txn.description.isEmpty ? scope : txn.description,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          paymentBadge,
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${scope.isEmpty ? '—' : scope} · ${fmtDate(txn.date)}'),
          if (txn.partyName.isNotEmpty && txn.categoryName.isNotEmpty)
            Text(
              'Party: ${txn.partyName}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          if (canModify && txn.createdBy.isNotEmpty)
            FutureBuilder<String>(
              future: _addedByName(ref, txn.createdBy),
              builder: (_, snap) => snap.hasData
                  ? Text(
                      'Added by: ${snap.data}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${txn.isDebit ? '−' : '+'} ${fmtMoney(txn.amount)}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (canModify) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              color: AppTheme.primary,
              tooltip: 'Edit',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TxnFormScreen(existing: txn))),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              color: Colors.redAccent,
              tooltip: 'Delete',
              onPressed: () async {
                final confirm = await showDialog<bool>(
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
                    false;
                if (confirm) {
                  // Cascade delete: if this is a petty cash fund entry,
                  // also delete the linked petty cash record
                  if (txn.description
                      .startsWith('Petty cash fund - ')) {
                    final pettyEntries = await ref.read(
                        pettyCashListProvider.future);
                    for (final pe in pettyEntries
                        .where((p) => p.txnId == txn.id)) {
                      await ref
                          .read(pettyCashRepoProvider)
                          .remove(pe.id);
                    }
                    // Fallback: match by amount/date for old entries
                    // without txnId link
                    final txnDate = txn.date
                        .toIso8601String()
                        .substring(0, 10);
                    for (final pe in pettyEntries.where((p) =>
                        p.isFund &&
                        p.txnId == null &&
                        p.amount == txn.amount &&
                        p.date
                                .toIso8601String()
                                .substring(0, 10) ==
                            txnDate)) {
                      await ref
                          .read(pettyCashRepoProvider)
                          .remove(pe.id);
                    }
                  }
                  await ref.read(txnRepoProvider).remove(txn.id);
                }
              },
            ),
          ],
        ],
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
