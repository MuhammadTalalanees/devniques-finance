import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/local_db.dart';
import '../../data/repos.dart';
import '../categories/categories_screen.dart';
import '../parties/parties_screen.dart';
import '../investors/investors_screen.dart';
import '../petty_cash/petty_cash_screen.dart';
import '../users/users_screen.dart';
import '../activity/activity_screen.dart';
import '../../core/theme.dart';

/// Settings / management menu. Admin-only items are hidden from staff.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static String _roleDisplay(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'add_only':
        return 'Add only';
      case 'view_only':
        return 'View only';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final sync = ref.watch(syncProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final canAdd =
        profile.whenData((p) => p?.canAdd ?? false).value ?? false;

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
                        '${p.email} · ${_roleDisplay(p.role)}'),
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
            onTap: canAdd
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const CategoriesScreen()))
                : null,
            subtitle: canAdd
                ? null
                : const Text('Admin only'),
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Parties'),
            subtitle: canAdd ? null : const Text('Admin only'),
            onTap: canAdd
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const PartiesScreen()))
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Investors'),
            subtitle: canAdd ? null : const Text('Admin only'),
            onTap: canAdd
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const InvestorsScreen()))
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.coffee_outlined),
            title: const Text('Petty Cash'),
            subtitle:
                const Text('Small day-to-day expenses'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        const PettyCashScreen())),
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
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Activity log'),
            subtitle: canAdd
                ? const Text(
                    'Who added what, and when')
                : const Text('Admin only'),
            onTap: canAdd
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const ActivityScreen()))
                : null,
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
                style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
