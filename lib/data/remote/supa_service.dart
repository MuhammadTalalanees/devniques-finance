import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around the Supabase client (Postgres + Auth + Storage).
class SupaService {
  SupabaseClient get _c => Supabase.instance.client;

  // ---------- auth ----------
  Future<AuthResponse> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<AuthResponse> signUp(String email, String password, String name) =>
      _c.auth.signUp(
          email: email,
          password: password,
          data: {'name': name});

  Future<void> signOut() => _c.auth.signOut();

  Stream<AuthState> get authChanges => _c.auth.onAuthStateChange;

  User? get currentUser => _c.auth.currentUser;

  // ---------- reads ----------
  Future<List<Map<String, dynamic>>> selectSince(
      String table, DateTime? since) async {
    var q = _c.from(table).select();
    if (since != null && since.millisecondsSinceEpoch > 0) {
      q = q.gt('updated_at', since.toUtc().toIso8601String());
    }
    final res = await q;
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<String>> allIds(String table) async {
    final res = await _c.from(table).select('id');
    return (res as List).map((e) => e['id'] as String).toList();
  }

  // ---------- attendance (migration v7, read-only here) ----------
  /// Sessions whose entry falls in [from, to). RLS decides visibility:
  /// employees get only their own rows, admin gets everyone's.
  Future<List<Map<String, dynamic>>> fetchAttendance(
      DateTime from, DateTime to) async {
    final res = await _c
        .from('attendance_sessions')
        .select()
        .gte('entry_at', from.toUtc().toIso8601String())
        .lt('entry_at', to.toUtc().toIso8601String())
        .order('entry_at', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// id -> display name for every profile (used by the admin attendance
  /// list; falls back to email when a name is empty).
  Future<Map<String, String>> fetchProfileNames() async {
    final res = await _c.from('profiles').select('id, name, email');
    final out = <String, String>{};
    for (final r in (res as List).cast<Map<String, dynamic>>()) {
      final name = (r['name'] ?? '') as String;
      out[r['id'] as String] =
          name.isNotEmpty ? name : (r['email'] ?? 'User') as String;
    }
    return out;
  }

  // ---------- writes ----------
  Future<void> insertRow(String table, Map<String, dynamic> row) =>
      _c.from(table).insert(row);

  Future<void> updateRow(
          String table, String id, Map<String, dynamic> row) =>
      _c.from(table).update(row).eq('id', id);

  Future<void> deleteRow(String table, String id) =>
      _c.from(table).delete().eq('id', id);

  /// Invoke an Edge Function (e.g. delete-user). Throws on error.
  Future<Map<String, dynamic>> invokeFunction(
      String name, Map<String, dynamic> body) async {
    final res = await _c.functions.invoke(name, body: body);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      if (data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return data;
    }
    return {'ok': true};
  }

  // ---------- receipts ----------
  /// Path-based (mobile offline-retry). Works on all platforms via XFile.
  Future<String> uploadReceipt(String localPath) async => uploadReceiptBytes(
      localPath.split('/').last, await XFile(localPath).readAsBytes());

  /// Bytes-based — the web-safe path (no dart:io anywhere).
  Future<String> uploadReceiptBytes(String fileName, Uint8List bytes) async {
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final path = 'receipts/$name';
    await _c.storage.from('receipts').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return _c.storage.from('receipts').getPublicUrl(path);
  }
}
