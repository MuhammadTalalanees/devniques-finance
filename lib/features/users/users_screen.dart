import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos.dart';

/// Admin-only: view users and change roles.
/// New staff self-register from the login screen (role = staff by default);
/// the admin promotes them here.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

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
              subtitle: Text(u.email),
              trailing: DropdownButton<String>(
                value: u.role,
                items: const [
                  DropdownMenuItem(
                      value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(
                      value: 'staff',
                      child: Text('Staff (add only)')),
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
                                '${u.email} will become ${r == 'admin' ? 'Admin (full access)' : 'Staff (add-only)'}'),
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
            );
          },
        ),
      ),
    );
  }
}
