import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/local_db.dart';
import '../../data/repos.dart';
import '../categories/categories_screen.dart';
import '../parties/parties_screen.dart';
import '../users/users_screen.dart';

/// Settings / management menu. Admin-only items are hidden from staff.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final sync = ref.watch(syncProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          profile.when(
            data: (p) => p == null
                ? const SizedBox.shrink()
                : ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.person)),
                    title: Text(p.name.isEmpty
                        ? p.email
                        : p.name),
                    subtitle: Text(
                        '${p.email} · ${p.isAdmin ? 'Admin' : 'Staff (add only)'}'),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync now'),
            subtitle: Text(sync.lastSync == null
                ? 'Never synced'
                : 'Last sync: ${sync.lastSync!.toLocal().toString().substring(0, 16)}'
                    '${sync.pending > 0 ? ' · ${sync.pending} pending' : ''}'),
            onTap: () =>
                ref.read(syncProvider.notifier).syncNow(),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Categories'),
            onTap: isAdmin
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const CategoriesScreen()))
                : null,
            subtitle: isAdmin
                ? null
                : const Text('Admin only'),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Parties'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        const PartiesScreen())),
          ),
          if (isAdmin)
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Users & roles'),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) =>
                          const UsersScreen())),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout,
                color: Colors.redAccent),
            title: const Text('Sign out',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await ref
                  .read(supaServiceProvider)
                  .signOut();
              await LocalDb.instance.clearAll();
              ref.invalidate(profileProvider);
              ref.invalidate(txnListProvider);
              ref.invalidate(categoryListProvider);
              ref.invalidate(partyListProvider);
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Devniques Finance v1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color:
                        Colors.white.withOpacity(0.35),
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
