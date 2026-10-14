import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/repos.dart';

/// Admin-only: manage income/expense categories.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoryListProvider);
    final profile = ref.watch(profileProvider);
    final canAdd =
        profile.whenData((p) => p?.canAdd ?? false).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              onPressed: () => _showAdd(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: cats.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            // Empty on first load usually means sync hasn't pulled yet.
            // Offer a one-tap refresh instead of making the user reload.
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No categories yet.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(syncProvider.notifier)
                        .syncNow(),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            return Dismissible(
              key: ValueKey(c.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Colors.redAccent,
                child:
                    const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) async =>
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete category?'),
                      content: const Text(
                          'Entries using it will keep their label.'),
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
                  ref.read(categoryRepoProvider).remove(c.id),
              child: ListTile(
                leading: CircleAvatar(
                    backgroundColor: Colors.blue.withValues(alpha: 0.15),
                    child: const Icon(Icons.label_outline,
                        color: Colors.blue)),
                title: Text(c.name),
                subtitle: Text(c.type),
              ),
            );
          },
          );
        },
      ),
    );
  }

  void _showAdd(BuildContext context, WidgetRef ref) {
    final name = TextEditingController();
    String type = 'expense';
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('New category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Name')),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'income', label: Text('Income')),
                  ButtonSegment(
                      value: 'expense', label: Text('Expense')),
                  ButtonSegment(
                      value: 'both', label: Text('Both')),
                ],
                selected: {type},
                onSelectionChanged: (s) =>
                    setS(() => type = s.first),
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
                ref.read(categoryRepoProvider).add(Category(
                      id: newId(),
                      name: name.text.trim(),
                      type: type,
                      color: '#5b9dff',
                      updatedAt: DateTime.now(),
                    ));
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}
