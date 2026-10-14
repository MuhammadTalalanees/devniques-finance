import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos.dart';

/// Admin-only: view users and change roles.
/// New users self-register from the login screen (role = view_only by default);
/// the admin promotes them here.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  static String roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin (full access)';
      case 'add_only':
        return 'Add only';
      case 'view_only':
        return 'View only';
      default:
        return role;
    }
  }

  String _roleLabel(String role) => roleLabel(role);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(userListProvider);
    final me = ref.watch(profileProvider).whenData((p) => p).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Users & roles')),
      body: users.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final u = list[i];
            final isMe = me?.id == u.id;
            return ListTile(
              leading: CircleAvatar(
                  child: Text(u.name.isEmpty
                      ? u.email[0].toUpperCase()
                      : u.name[0].toUpperCase())),
              title: Text(u.name.isEmpty ? u.email : u.name),
              subtitle: Text('${u.email} · ${_roleLabel(u.role)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: ['admin', 'add_only', 'view_only']
                            .contains(u.role)
                        ? u.role
                        : 'view_only',
                    items: const [
                      DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin')),
                      DropdownMenuItem(
                          value: 'add_only',
                          child: Text('Add only')),
                      DropdownMenuItem(
                          value: 'view_only',
                          child: Text('View only')),
                    ],
                onChanged: isMe
                    ? null // can't demote yourself
                    : (r) {
                        if (r == null) return;
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Change role?'),
                            content: Text(
                                '${u.email} will become ${_roleLabel(r)}'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context),
                                  child:
                                      const Text('Cancel')),
                              FilledButton(
                                onPressed: () {
                                  ref
                                      .read(userRepoProvider)
                                      .setRole(u.id, r);
                                  Navigator.pop(context);
                                },
                                child:
                                    const Text('Confirm'),
                              ),
                            ],
                          ),
                        );
                      },
                  ),
                  if (!isMe)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20),
                      color: Colors.redAccent,
                      tooltip: 'Delete user',
                      onPressed: () async {
                        final confirm =
                            await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text(
                                        'Delete user?'),
                                    content: Text(
                                        'Remove ${u.email} from the app? This cannot be undone.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                                  context, false),
                                          child: const Text(
                                              'Cancel')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                                  context, true),
                                          child: const Text(
                                              'Delete')),
                                    ],
                                  ),
                                ) ??
                                false;
                        if (confirm) {
                          await ref
                              .read(userRepoProvider)
                              .deleteUser(u.id);
                        }
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
