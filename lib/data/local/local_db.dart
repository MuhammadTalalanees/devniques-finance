import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Offline-first local store (SQLite via sqflite).
/// Mirrors the Supabase tables + a sync queue + a kv store.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    // Web: getDatabasesPath() doesn't exist in the browser — the FFI-web
    // factory takes a plain name and persists it in IndexedDB itself.
    final String path;
    if (kIsWeb) {
      // No-web-worker variant: SQLite runs directly in the page, no
      // shared-worker message channel (that path returns null here).
      databaseFactory = databaseFactoryFfiWebNoWebWorker;
      path = 'devniques_finance.db';
    } else {
      final dir = await getDatabasesPath();
      path = p.join(dir, 'devniques_finance.db');
    }
    _db = await openDatabase(
      path,
      version: 5,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return _db!;
  }

  Future<void> _upgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      // v2: investor name column for 'investment' entries.
      await db.execute(
          "ALTER TABLE txns ADD COLUMN investor TEXT NOT NULL DEFAULT ''");
    }
    if (oldV < 3) {
      // v3: petty_cash table for small day-to-day expenses.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS petty_cash(
          id TEXT PRIMARY KEY, amount REAL NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          date TEXT NOT NULL,
          created_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)''');
    }
    if (oldV < 4) {
      // v4: kind column — 'fund' (money added in) vs 'spend' (money spent).
      await db.execute(
          "ALTER TABLE petty_cash ADD COLUMN kind TEXT NOT NULL DEFAULT 'spend'");
    }
    if (oldV < 5) {
      // v5: txn_id column — links a 'fund' entry to its ledger transaction.
      await db.execute(
          "ALTER TABLE petty_cash ADD COLUMN txn_id TEXT");
    }
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profiles(
        id TEXT PRIMARY KEY, email TEXT NOT NULL, name TEXT NOT NULL DEFAULT '',
        role TEXT NOT NULL DEFAULT 'view_only', updated_at TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE categories(
        id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL DEFAULT 'both',
        color TEXT NOT NULL DEFAULT '#5b9dff', updated_at TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE parties(
        id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'other',
        phone TEXT NOT NULL DEFAULT '', email TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE txns(
        id TEXT PRIMARY KEY, type TEXT NOT NULL, amount REAL NOT NULL,
        category_id TEXT, category_name TEXT NOT NULL DEFAULT '',
        party_id TEXT, party_name TEXT NOT NULL DEFAULT '',
        investor TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT 'Cash',
        receipt_url TEXT, receipt_local TEXT,
        created_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE petty_cash(
        id TEXT PRIMARY KEY, amount REAL NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'spend',
        txn_id TEXT,
        created_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE sync_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL, op TEXT NOT NULL,
        record_id TEXT NOT NULL, payload TEXT NOT NULL,
        created_at TEXT NOT NULL)''');
    await db.execute(
        'CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  // ---------- generic row helpers ----------
  Future<void> upsertAll(
      String table, List<Map<String, dynamic>> rows) async {
    final d = await db;
    final b = d.batch();
    for (final r in rows) {
      b.insert(table, r,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAll(String table,
      {String? orderBy}) async {
    final d = await db;
    return d.query(table, orderBy: orderBy);
  }

  Future<void> deleteMissing(String table, Set<String> remoteIds) async {
    final d = await db;
    if (remoteIds.isEmpty) {
      await d.delete(table);
      return;
    }
    final q = remoteIds.map((_) => '?').join(',');
    await d.delete(table, where: 'id NOT IN ($q)', whereArgs: remoteIds.toList());
  }

  Future<void> deleteRow(String table, String id) async {
    final d = await db;
    await d.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Delete petty cash fund entries linked to a ledger txn id.
  /// Returns the ids of deleted rows for sync queueing.
  Future<List<String>> deletePettyCashByTxnId(String txnId) async {
    final d = await db;
    final rows = await d.query('petty_cash',
        columns: ['id'], where: 'txn_id = ?', whereArgs: [txnId]);
    final ids = rows.map((r) => r['id'] as String).toList();
    for (final id in ids) {
      await d.delete('petty_cash', where: 'id = ?', whereArgs: [id]);
    }
    return ids;
  }

  /// Fallback: delete petty cash fund entries by amount+date
  /// (for old entries without txn_id link).
  Future<List<String>> deletePettyCashByAmountDate(
      double amount, String dateIso) async {
    final d = await db;
    final rows = await d.query('petty_cash',
        columns: ['id'],
        where: "kind = 'fund' AND amount = ? AND date = ?",
        whereArgs: [amount, dateIso]);
    final ids = rows.map((r) => r['id'] as String).toList();
    for (final id in ids) {
      await d.delete('petty_cash', where: 'id = ?', whereArgs: [id]);
    }
    return ids;
  }

  Future<void> clearAll() async {
    final d = await db;
    for (final t in ['profiles', 'categories', 'parties', 'txns', 'sync_queue', 'kv']) {
      await d.delete(t);
    }
  }

  // ---------- sync queue ----------
  Future<void> enqueue(String table, String op, String recordId,
      Map<String, dynamic> payload) async {
    final d = await db;
    await d.insert('sync_queue', {
      'table_name': table,
      'op': op, // insert | update | delete
      'record_id': recordId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> pendingOps() async {
    final d = await db;
    return d.query('sync_queue', orderBy: 'id ASC');
  }

  Future<void> dropOps(List<int> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    final q = ids.map((_) => '?').join(',');
    await d.delete('sync_queue', where: 'id IN ($q)', whereArgs: ids);
  }

  Future<int> pendingCount() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) c FROM sync_queue');
    return (r.first['c'] as int?) ?? 0;
  }

  // ---------- kv ----------
  Future<String?> kvGet(String key) async {
    final d = await db;
    final r =
        await d.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> kvSet(String key, String value) async {
    final d = await db;
    await d.insert('kv', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
