import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/repos.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';

/// Investors: manage investor names for investment entries.
/// Admin-only. Investors appear in the investment form dropdown.
class InvestorsScreen extends ConsumerWidget {
  const InvestorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partyListProvider);
    final txns = ref.watch(txnListProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Investors')),
      // Talal's rule: investors are ADMIN ONLY — add-only users
      // cannot add here either.
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _showForm(context, ref, null),
              child: const Icon(Icons.add),
            )
          : null,
      body: parties.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          // Merge parties with investors found in transactions
          final investors = list.where((p) => p.kind == 'investor').toList();
          txns.whenData((txns) {
            final names = <String>{};
            for (final t in txns.where((t) => t.isInvestment)) {
              if (t.investor.isNotEmpty) names.add(t.investor);
            }
            // Add transaction investors not already in parties
            final existing = investors.map((p) => p.name).toSet();
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
          });
          if (investors.isEmpty) {
            return const Center(
                child: Text(
                    'No investors yet. Tap + to add one.'));
          }
          return ListView.builder(
            itemCount: investors.length,
            itemBuilder: (_, i) {
              final p = investors[i];
              return Card(
                margin: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.investment
                        .withValues(alpha: 0.15),
                    child: Icon(Icons.savings,
                        color: AppTheme.investment),
                  ),
                  title: Text(p.name),
                  subtitle: Text([
                    'Investor',
                    if (p.sharePercent != null)
                      '${p.sharePercent}% share',
                    if (p.phone.isNotEmpty) p.phone,
                  ].join(' · ')),
                  trailing: isAdmin
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit,
                                  size: 20),
                              color: AppTheme.primary,
                              onPressed: () =>
                                  _showForm(context, ref, p),
                            ),
                            if (!p.id.startsWith('txn-'))
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 20),
                                color: Colors.redAccent,
                                onPressed: () =>
                                    _confirmDelete(context, ref, p),
                              ),
                          ],
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// What deleting this investor will remove, in plain words.
  /// Talal's final model: ONLY the record and its share % — the
  /// investment entries, Total Raised and balances never change.
  String _deleteWarning(List<Txn> txns, Party p) {
    return 'Remove \"${p.name}\" from investors? Only this investor '
        'record and its share % will be deleted. Investment entries, '
        'Total Raised Capital and balances will NOT change.';
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Party p) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete investor?'),
            content: Text(_deleteWarning(
                ref.read(txnListProvider).value ?? [], p)),
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
      final txns = ref.read(txnListProvider).value ?? [];
      await ref.read(partyRepoProvider).removeInvestor(p, txns);
    }
  }

  void _showForm(
      BuildContext context, WidgetRef ref, Party? existing) {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? '');
    final phoneCtrl =
        TextEditingController(text: existing?.phone ?? '');
    final pctCtrl = TextEditingController(
        text: existing?.sharePercent != null
            ? '${existing!.sharePercent}'
            : '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null
            ? 'Add Investor'
            : 'Edit Investor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Investor name'),
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
              decoration: const InputDecoration(
                  labelText: 'Phone (optional)'),
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
              final pct = pctText.isEmpty
                  ? null
                  : double.tryParse(pctText);
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
              try {
                if (existing == null) {
                  await repo.add(party);
                } else {
                  final txns = ref.read(txnListProvider).value ?? [];
                  await repo.saveInvestor(party, txns,
                      previousName: existing.name);
                }
              } on ShareLimitException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(e.message),
                        backgroundColor: Colors.redAccent),
                  );
                }
                return;
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
