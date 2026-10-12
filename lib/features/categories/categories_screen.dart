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
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAdd(context, ref),
        child: const Icon(Icons.add),
      ),
      body: cats.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView.builder(
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
                    backgroundColor: Colors.blue.withOpacity(0.15),
                    child: const Icon(Icons.label_outline,
                        color: Colors.blue)),
                title: Text(c.name),
                subtitle: Text(c.type),
              ),
            );
          },
        ),
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
