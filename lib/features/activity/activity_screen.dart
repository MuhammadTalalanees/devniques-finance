import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

/// Admin-only: every entry with who added it and when (newest first).
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(txnListProvider);
    final users = ref.watch(userListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: txns.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final items = list.toList()
            ..sort(
                (a, b) => b.updatedAt.compareTo(a.updatedAt));
          if (items.isEmpty) {
            return const Center(
                child: Text('No activity yet.'));
          }
          final userMap = users.when(
            data: (ul) => {
              for (final u in ul)
                u.id: u.name.isEmpty ? u.email : u.name
            },
            loading: () => <String, String>{},
            error: (_, __) => <String, String>{},
          );
          return ListView.builder(
            itemCount: items.length,
            padding: const EdgeInsets.only(bottom: 24),
            itemBuilder: (_, i) {
              final Txn t = items[i];
              final color = t.isDebit
                  ? AppTheme.expense
                  : (t.isInvestment
                      ? AppTheme.investment
                      : AppTheme.income);
              final typeLabel = t.isDebit
                  ? 'Expense'
                  : (t.isInvestment ? 'Investment' : 'Credit');
              final scope = t.isInvestment
                  ? t.investor
                  : (t.categoryName.isEmpty
                      ? t.partyName
                      : t.categoryName);
              final title = t.description.isEmpty
                  ? (scope.isEmpty ? typeLabel : scope)
                  : t.description;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      color.withValues(alpha: 0.15),
                  child: Icon(
                      t.isDebit
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      color: color,
                      size: 20),
                ),
                title: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${_dateTime.format(t.updatedAt.toLocal())} · Added by ${userMap[t.createdBy] ?? t.createdBy}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${t.isDebit ? '−' : '+'} ${fmtMoney(t.amount)}',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(typeLabel,
                        style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: 11)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
