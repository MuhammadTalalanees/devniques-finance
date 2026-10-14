import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/repos.dart';
import '../../core/theme.dart';

/// Investors: manage investor names for investment entries.
/// Admin-only. Investors appear in the investment form dropdown.
class InvestorsScreen extends ConsumerWidget {
  const InvestorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partyListProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final canAdd =
        profile.whenData((p) => p?.canAdd ?? false).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Investors')),
      floatingActionButton: canAdd
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
          final investors =
              list.where((p) => p.kind == 'investor').toList();
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
                  subtitle: Text(p.phone.isEmpty
                      ? 'Investor'
                      : 'Investor · ${p.phone}'),
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

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Party p) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete investor?'),
            content: Text(
                'Remove "${p.name}" from investors?'),
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
      await ref.read(partyRepoProvider).remove(p.id);
    }
  }

  void _showForm(
      BuildContext context, WidgetRef ref, Party? existing) {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? '');
    final phoneCtrl =
        TextEditingController(text: existing?.phone ?? '');
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
              final now = DateTime.now();
              final party = Party(
                id: existing?.id ??
                    '${now.millisecondsSinceEpoch}',
                name: name,
                kind: 'investor',
                phone: phoneCtrl.text.trim(),
                updatedAt: now,
              );
              final repo = ref.read(partyRepoProvider);
              if (existing == null) {
                await repo.add(party);
              } else {
                await repo.update(party);
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
