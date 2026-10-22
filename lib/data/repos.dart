import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'local/local_db.dart';
import 'models.dart';
import 'remote/supa_service.dart';

final _uuid = Uuid();

final supaServiceProvider = Provider((_) => SupaService());
final localDbProvider = Provider((_) => LocalDb.instance);

// ==================== AUTH ====================

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supaServiceProvider).authChanges;
});

final profileProvider = FutureProvider<AppUser?>((ref) async {
  final auth = ref.watch(authStateProvider);
  return auth.when(
    data: (s) async {
      final user = s.session?.user;
      if (user == null) return null;
      // prefer local cache, fall back to remote
      final local = await LocalDb.instance.getAll('profiles');
      final hit = local.where((e) => e['id'] == user.id);
      if (hit.isNotEmpty) return AppUser.fromMap(hit.first);
      try {
        final supa = ref.read(supaServiceProvider);
        final rows = await supa.selectSince('profiles', null);
        final me = rows.where((e) => e['id'] == user.id);
        if (me.isEmpty) {
          // No profile row yet (fresh registration) — create one
          // as view_only. Admin can promote later.
          final now = DateTime.now();
          final p = AppUser(
            id: user.id,
            email: user.email ?? '',
            name: (user.userMetadata?['name'] as String?) ?? '',
            role: 'view_only',
            updatedAt: now,
          );
          try {
            await supa.insertRow('profiles', p.toMap());
          } catch (_) {
            // RLS may block; still cache locally so the app works.
          }
          await LocalDb.instance.upsertAll('profiles', [p.toMap()]);
          return p;
        }
        final p = AppUser.fromMap(me.first);
        await LocalDb.instance.upsertAll('profiles', [p.toMap()]);
        return p;
      } catch (_) {
        return null;
      }
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// ==================== SYNC ====================

enum SyncStatus { idle, syncing, error }

class SyncState {
  final SyncStatus status;
  final int pending;
  final DateTime? lastSync;
  final String? error;
  SyncState(
      {this.status = SyncStatus.idle,
      this.pending = 0,
      this.lastSync,
      this.error});
}

class SyncNotifier extends Notifier<SyncState> {
  StreamSubscription? _sub;

  @override
  SyncState build() {
    _sub ??= Connectivity()
        .onConnectivityChanged
        .listen((r) => syncNow());
    ref.onDispose(() => _sub?.cancel());
    Future.microtask(() => syncNow());
    return SyncState();
  }

  bool get isOnline => true; // refined inside syncNow via try/catch

  Future<void> syncNow() async {
    if (state.status == SyncStatus.syncing) return;
    // Fast offline exit — the UI is local-first anyway; no point waiting
    // on network timeouts when there is no connection at all.
    try {
      final conn = await Connectivity().checkConnectivity();
      if (conn.contains(ConnectivityResult.none)) {
        final pending = await LocalDb.instance.pendingCount();
        state = SyncState(
            status: SyncStatus.idle,
            pending: pending,
            lastSync: state.lastSync);
        return;
      }
    } catch (_) {
      // connectivity_plus unavailable — fall through to try/catch below.
    }
    state = SyncState(status: SyncStatus.syncing, pending: state.pending);
    try {
      await _push();
      await _pull();
      final pending = await LocalDb.instance.pendingCount();
      state = SyncState(
          status: SyncStatus.idle,
          pending: pending,
          lastSync: DateTime.now());
    } catch (e) {
      final pending = await LocalDb.instance.pendingCount();
      state = SyncState(
          status: pending > 0 ? SyncStatus.error : SyncStatus.idle,
          pending: pending,
          lastSync: state.lastSync,
          error: e.toString());
    }
    // notify list screens
    ref.invalidate(txnListProvider);
    ref.invalidate(categoryListProvider);
    ref.invalidate(partyListProvider);
    ref.invalidate(pettyCashListProvider);
  }

  Future<void> _push() async {
    final ops = await LocalDb.instance.pendingOps();
    final done = <int>[];
    final supa = ref.read(supaServiceProvider);
    for (final op in ops) {
      final qid = op['id'] as int;
      final table = op['table_name'] as String;
      final action = op['op'] as String;
      final recordId = op['record_id'] as String;
      try {
        if (action == 'delete') {
          await supa.deleteRow(table, recordId);
        } else {
          final payload =
              jsonDecode(op['payload'] as String) as Map<String, dynamic>;
          // upload any pending receipt photo first (was saved offline)
          if (table == 'transactions') {
            final local =
                await LocalDb.instance.getAll('txns');
            final hit =
                local.where((e) => e['id'] == recordId);
            if (hit.isNotEmpty) {
              final lp = hit.first['receipt_local'] as String?;
              if (lp != null && lp.isNotEmpty) {
                final url = await supa.uploadReceipt(lp);
                payload['receipt_url'] = url;
                hit.first['receipt_url'] = url;
                hit.first['receipt_local'] = null;
                await LocalDb.instance
                    .upsertAll('txns', [hit.first]);
              }
            }
          }
          // strip local-only columns before sending
          payload.remove('category_name');
          payload.remove('party_name');
          payload.remove('receipt_local');
          if (action == 'insert') {
            await supa.insertRow(table, payload);
          } else {
            await supa.updateRow(table, recordId, payload);
          }
        }
        done.add(qid);
      } catch (e) {
        // RLS violation or gone remote: drop the op so the queue never jams.
        // A re-pull right after restores the true server state.
        done.add(qid);
      }
    }
    await LocalDb.instance.dropOps(done);
  }

  static const _tables = [
    'categories',
    'parties',
    'transactions',
    'profiles',
    'petty_cash'
  ];

  /// Local column allow-list per table (remote rows carry extra columns
  /// like created_at / created_by which don't exist locally).
  static const _localCols = {
    'profiles': {'id', 'email', 'name', 'role', 'updated_at'},
    'categories': {'id', 'name', 'type', 'color', 'updated_at'},
    'parties': {
      'id', 'name', 'kind', 'phone', 'email', 'notes', 'share_percent',
      'updated_at'
    },
    'transactions': {
      'id', 'type', 'amount', 'category_id', 'party_id', 'investor', 'date',
      'description', 'payment_method', 'receipt_url', 'created_by',
      'updated_at'
    },
    'petty_cash': {
      'id', 'amount', 'description', 'date', 'created_by', 'updated_at',
      'kind', 'txn_id', 'category_id', 'category_name'
    },
  };

  Map<String, dynamic> _localize(String table, Map<String, dynamic> row) {
    final keep = _localCols[table]!;
    return {for (final k in keep) k: row[k]};
  }

  Future<void> _pull() async {
    final supa = ref.read(supaServiceProvider);
    final db = LocalDb.instance;
    // Wave 1: reference tables concurrently (was: 4 sequential round-trips).
    await Future.wait(['categories', 'parties', 'profiles', 'petty_cash']
        .map((t) => _pullTable(supa, db, t)));
    // Wave 2: transactions need categories/parties for name denormalization.
    await _pullTable(supa, db, 'transactions');
    // Reconcile deletes at most once per hour — deletes are rare, and
    // fetching full id lists on every launch is pure overhead.
    final lastReconcileStr = await db.kvGet('last_reconcile');
    final lastReconcile = lastReconcileStr == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.parse(lastReconcileStr);
    if (DateTime.now().difference(lastReconcile) > const Duration(hours: 1)) {
      await Future.wait(_tables.map((t) async {
        final remoteIds = (await supa.allIds(t)).toSet();
        await db.deleteMissing(t == 'transactions' ? 'txns' : t, remoteIds);
      }));
      await db.kvSet(
          'last_reconcile', DateTime.now().toUtc().toIso8601String());
    }
  }

  Future<void> _pullTable(SupaService supa, LocalDb db, String t) async {
    final sinceStr = await db.kvGet('last_pull_$t');
    final since = sinceStr == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.parse(sinceStr);
    final rows = await supa.selectSince(t, since);
    if (rows.isNotEmpty) {
      final local = t == 'transactions' ? 'txns' : t;
      if (t == 'transactions') {
        // denormalize names for offline display
        final cats = {for (final c in await db.getAll('categories')) c['id']: c['name']};
        final prs = {for (final p in await db.getAll('parties')) p['id']: p['name']};
        for (final r in rows) {
          r['category_name'] = cats[r['category_id']] ?? '';
          r['party_name'] = prs[r['party_id']] ?? '';
        }
        await db.upsertAll('txns', [
          for (final r in rows)
            _localize(t, r)
              ..['category_name'] = r['category_name']
              ..['party_name'] = r['party_name']
        ]);
      } else if (t == 'petty_cash') {
        // denormalize the category name for display
        final cats = {
          for (final c in await db.getAll('categories')) c['id']: c['name']
        };
        await db.upsertAll(local, [
          for (final r in rows)
            _localize(t, r)
              ..['category_name'] = cats[r['category_id']] ?? ''
        ]);
      } else {
        await db.upsertAll(local, [for (final r in rows) _localize(t, r)]);
      }
      await db.kvSet('last_pull_$t', DateTime.now().toUtc().toIso8601String());
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

// ==================== TRANSACTIONS ====================

final txnListProvider = FutureProvider<List<Txn>>((ref) async {
  final rows = await LocalDb.instance
      .getAll('txns', orderBy: 'date DESC, updated_at DESC');
  return rows.map(Txn.fromMap).toList();
});

class TxnRepo {
  TxnRepo(this._ref);
  final Ref _ref;

  Future<void> add(Txn t) async {
    final db = LocalDb.instance;
    await db.upsertAll('txns', [t.toLocalMap()]);
    await db.enqueue('transactions', 'insert', t.id, t.toRemoteMap());
    _ref.invalidate(txnListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  Future<void> update(Txn t) async {
    final db = LocalDb.instance;
    await db.upsertAll('txns', [t.toLocalMap()]);
    await db.enqueue('transactions', 'update', t.id, t.toRemoteMap());
    _ref.invalidate(txnListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  Future<void> remove(String id) async {
    final db = LocalDb.instance;
    await db.deleteRow('txns', id);
    await db.enqueue('transactions', 'delete', id, {'id': id});
    _ref.invalidate(txnListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }
}

final txnRepoProvider = Provider((ref) => TxnRepo(ref));

String newId() => _uuid.v4();

// ==================== PETTY CASH ====================

final pettyCashListProvider =
    FutureProvider<List<PettyCash>>((ref) async {
  final rows = await LocalDb.instance
      .getAll('petty_cash', orderBy: 'date DESC, updated_at DESC');
  return rows.map(PettyCash.fromMap).toList();
});

/// Attendance for one calendar month. [month] is any day inside the
/// month; sessions are fetched straight from Supabase (read-only —
/// the Android attendance app writes them, this app only displays).
final attendanceMonthProvider = FutureProvider.family<List<AttendanceSession>,
    DateTime>((ref, month) async {
  final supa = ref.watch(supaServiceProvider);
  // The month is always read on the Pakistan (UTC+5) calendar —
  // the office is there, wherever the viewer happens to be.
  final fromUtc = DateTime.utc(month.year, month.month, 1)
      .subtract(const Duration(hours: 5));
  final toUtc = DateTime.utc(month.year, month.month + 1, 1)
      .subtract(const Duration(hours: 5));
  final rows = await supa.fetchAttendance(fromUtc, toUtc);
  return rows.map(AttendanceSession.fromMap).toList();
});

/// id -> name map for showing names in the admin attendance list.
final profileNamesProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final supa = ref.watch(supaServiceProvider);
  return supa.fetchProfileNames();
});

class PettyCashRepo {
  PettyCashRepo(this._ref);
  final Ref _ref;

  Future<void> add(PettyCash p) async {
    final db = LocalDb.instance;
    // Ensure txn_id column exists (for DBs created before v5 migration)
    try {
      final d = await db.db;
      await d.execute(
          "ALTER TABLE petty_cash ADD COLUMN txn_id TEXT");
    } catch (_) {
      // Column already exists, ignore
    }
    await db.upsertAll('petty_cash', [p.toMap()]);
    await db.enqueue('petty_cash', 'insert', p.id, p.toRemoteMap());
    _ref.invalidate(pettyCashListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  Future<void> update(PettyCash p) async {
    final db = LocalDb.instance;
    await db.upsertAll('petty_cash', [p.toMap()]);
    await db.enqueue('petty_cash', 'update', p.id, p.toRemoteMap());
    _ref.invalidate(pettyCashListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  Future<void> remove(String id) async {
    final db = LocalDb.instance;
    await db.deleteRow('petty_cash', id);
    await db.enqueue('petty_cash', 'delete', id, {'id': id});
    _ref.invalidate(pettyCashListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  /// Delete all petty cash entries linked to a ledger txn id.
  /// Bypasses provider cache — hits local DB directly.
  /// Falls back to amount+date matching for old unlinked entries.
  Future<void> removeByTxnId(String txnId,
      {double? amount, String? dateIso}) async {
    final db = LocalDb.instance;
    var ids = await db.deletePettyCashByTxnId(txnId);
    if (ids.isEmpty && amount != null && dateIso != null) {
      ids = await db.deletePettyCashByAmountDate(amount, dateIso);
    }
    for (final id in ids) {
      await db.enqueue('petty_cash', 'delete', id, {'id': id});
    }
    _ref.invalidate(pettyCashListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }
}

final pettyCashRepoProvider =
    Provider((ref) => PettyCashRepo(ref));

// ==================== CATEGORIES ====================

final categoryListProvider = FutureProvider<List<Category>>((ref) async {
  final rows =
      await LocalDb.instance.getAll('categories', orderBy: 'name ASC');
  return rows.map(Category.fromMap).toList();
});

class CategoryRepo {
  CategoryRepo(this._ref);
  final Ref _ref;

  Future<void> add(Category c) async {
    final db = LocalDb.instance;
    await db.upsertAll('categories', [c.toMap()]);
    await db.enqueue('categories', 'insert', c.id, c.toMap());
    _ref.invalidate(categoryListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  Future<void> remove(String id) async {
    final db = LocalDb.instance;
    await db.deleteRow('categories', id);
    await db.enqueue('categories', 'delete', id, {'id': id});
    _ref.invalidate(categoryListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }
}

final categoryRepoProvider = Provider((ref) => CategoryRepo(ref));

// ==================== PARTIES ====================

final partyListProvider = FutureProvider<List<Party>>((ref) async {
  final rows = await LocalDb.instance.getAll('parties', orderBy: 'name ASC');
  return rows.map(Party.fromMap).toList();
});

/// Thrown when an investor save would push the total of all
/// shares past 100% (Talal's rule, 2026-10-22). The investor
/// forms catch this, show [message] and keep the dialog open.
class ShareLimitException implements Exception {
  final String message;
  ShareLimitException(this.message);
  @override
  String toString() => message;
}

class PartyRepo {
  PartyRepo(this._ref);
  final Ref _ref;

  static String _fmtShare(double v) {
    var x = v.toStringAsFixed(2);
    if (x.contains('.')) {
      x = x.replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return x;
  }

  /// All investors' shares together can never pass 100%.
  /// Returns the error text for this save, or null when it fits.
  Future<String?> shareLimitError(Party p) async {
    final pct = p.sharePercent;
    if (pct == null) return null;
    if (pct < 0 || pct > 100) {
      return 'Share % must be between 0 and 100.';
    }
    final rows = await LocalDb.instance.getAll('parties');
    var others = 0.0;
    for (final r in rows) {
      final q = Party.fromMap(r);
      if (q.kind == 'investor' &&
          q.id != p.id &&
          q.sharePercent != null) {
        others += q.sharePercent!;
      }
    }
    if (others + pct > 100.0001) {
      final left = 100 - others;
      return 'Shares already total ${_fmtShare(others)}%. '
          'Only ${_fmtShare(left)}% is left — this share can be '
          'at most ${_fmtShare(left)}%.';
    }
    return null;
  }

  Future<void> add(Party p) async {
    if (p.kind == 'investor') {
      final err = await shareLimitError(p);
      if (err != null) throw ShareLimitException(err);
    }
    final db = LocalDb.instance;
    await db.upsertAll('parties', [p.toMap()]);
    await db.enqueue('parties', 'insert', p.id, p.toMap());
    _ref.invalidate(partyListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  Future<void> update(Party p) async {
    final db = LocalDb.instance;
    await db.upsertAll('parties', [p.toMap()]);
    await db.enqueue('parties', 'update', p.id, p.toMap());
    _ref.invalidate(partyListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  Future<void> remove(String id) async {
    final db = LocalDb.instance;
    await db.deleteRow('parties', id);
    await db.enqueue('parties', 'delete', id, {'id': id});
    _ref.invalidate(partyListProvider);
    _ref.read(syncProvider.notifier).syncNow();
  }

  /// Saves an investor from the Investors panel / screen.
  ///
  /// An investor can exist in two ways: as a real party record, or
  /// name-only (id 'txn-<name>') through their investment entries.
  /// Saving a name-only investor creates the real record under a
  /// fresh UUID. Talal's final model (2026-10-22): saving NEVER
  /// touches entries — no retagging on rename. The name on an
  /// entry is free text the admin typed on that entry; renaming
  /// the record changes only the record.
  Future<void> saveInvestor(Party p, List<Txn> txns,
      {String? previousName}) async {
    final err = await shareLimitError(p);
    if (err != null) throw ShareLimitException(err);
    if (p.id.startsWith('txn-')) {
      await add(Party(
        id: newId(),
        name: p.name,
        kind: 'investor',
        phone: p.phone,
        email: p.email,
        notes: p.notes,
        sharePercent: p.sharePercent,
        updatedAt: p.updatedAt,
      ));
    } else {
      await update(p);
    }
  }

  /// Removes an investor (Talal's FINAL rule, 2026-10-22 night —
  /// replaces every earlier variant): the Investors section is a
  /// share register ONLY. Deleting removes ONLY the investor
  /// record and its share %. It NEVER touches entries, Total
  /// Raised Capital or balances — no untagging, no cascading,
  /// nothing. A name-only investor (id 'txn-...') has no record,
  /// so there is nothing to delete.
  Future<void> removeInvestor(Party p, List<Txn> txns) async {
    if (!p.id.startsWith('txn-')) {
      await remove(p.id);
    }
  }
}

final partyRepoProvider = Provider((ref) => PartyRepo(ref));

// ==================== USERS (admin) ====================

final userListProvider = FutureProvider<List<AppUser>>((ref) async {
  // always fresh from server — admin-only screen, admin is online here
  final rows = await ref.read(supaServiceProvider).selectSince('profiles', null);
  rows.sort((a, b) => (a['email'] as String).compareTo(b['email'] as String));
  return rows.map(AppUser.fromMap).toList();
});

class UserRepo {
  UserRepo(this._ref);
  final Ref _ref;

  Future<void> setRole(String userId, String role) async {
    await _ref
        .read(supaServiceProvider)
        .updateRow('profiles', userId, {'role': role});
    // keep local cache consistent
    final db = LocalDb.instance;
    final rows = await db.getAll('profiles');
    for (final r in rows.where((e) => e['id'] == userId)) {
      r['role'] = role;
      await db.upsertAll('profiles', [r]);
    }
    _ref.invalidate(userListProvider);
    _ref.invalidate(profileProvider);
  }

  Future<void> deleteUser(String userId) async {
    // Delete from Auth + profiles via Edge Function (service-role).
    // Falls back to profile-only delete if the function isn't deployed.
    try {
      await _ref
          .read(supaServiceProvider)
          .invokeFunction('delete-user', {'user_id': userId});
    } catch (_) {
      try {
        await _ref
            .read(supaServiceProvider)
            .deleteRow('profiles', userId);
      } catch (_) {
        // RLS may block; continue with local cleanup.
      }
    }
    final db = LocalDb.instance;
    await db.deleteRow('profiles', userId);
    _ref.invalidate(userListProvider);
  }
}

final userRepoProvider = Provider((ref) => UserRepo(ref));
