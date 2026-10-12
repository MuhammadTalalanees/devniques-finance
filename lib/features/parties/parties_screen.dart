import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/repos.dart';

const kinds = ['client', 'vendor', 'employee', 'other'];

/// Parties: clients, vendors, employees. Staff can add; only admin edits/deletes.
class PartiesScreen extends ConsumerWidget {
  const PartiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partyListProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Parties')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: parties.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
                child:
                    Text('No parties yet. Add clients, vendors…'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              final tile = ListTile(
                leading: CircleAvatar(
                    child: Text(p.name.isEmpty
                        ? '?'
                        : p.name[0].toUpperCase())),
                title: Text(p.name),
                subtitle:
                    Text('${p.kind}${p.phone.isEmpty ? '' : ' · ${p.phone}'}'),
                onTap: isAdmin
                    ? () => _showForm(context, ref, p)
                    : null,
              );
              if (!isAdmin) return tile;
              return Dismissible(
                key: ValueKey(p.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.redAccent,
                  child: const Icon(Icons.delete,
                      color: Colors.white),
                ),
                confirmDismiss: (_) async =>
                    await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete party?'),
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
                    ref.read(partyRepoProvider).remove(p.id),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }

  void _showForm(
      BuildContext context, WidgetRef ref, Party? existing) {
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    String kind = existing?.kind ?? 'client';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(existing == null
              ? 'New party'
              : 'Edit party'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone (optional)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration:
                    const InputDecoration(labelText: 'Type'),
                items: kinds
                    .map((k) => DropdownMenuItem(
                        value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) =>
                    setS(() => kind = v ?? 'client'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                final repo = ref.read(partyRepoProvider);
                if (existing == null) {
                  repo.add(Party(
                    id: newId(),
                    name: name.text.trim(),
                    kind: kind,
                    phone: phone.text.trim(),
                    updatedAt: DateTime.now(),
                  ));
                } else {
                  repo.update(Party(
                    id: existing.id,
                    name: name.text.trim(),
                    kind: kind,
                    phone: phone.text.trim(),
                    email: existing.email,
                    notes: existing.notes,
                    updatedAt: DateTime.now(),
                  ));
                }
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
