import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repos.dart';
import '../attendance/attendance_screen.dart';

/// Human Resources hub (Phase 1, 2026-10-22 — Talal's Facteno
/// model): Admin controls everything from here; employees see
/// only their own panel (requests, leave, payslips, documents).
/// All HR data lives in the migration-v13 tables and is read
/// fresh from the server (no local sync for HR).
class HrHubScreen extends ConsumerWidget {
  const HrHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final isAdmin =
        profile.whenData((p) => p?.isAdmin ?? false).value ?? false;

    Widget tile(IconData icon, String title, String subtitle,
        Widget screen) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => screen),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Human Resources (HR)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          tile(Icons.fact_check, 'Attendance',
              'WiFi attendance of the team', const AttendanceScreen()),
          if (isAdmin)
            tile(Icons.people, 'Employees',
                'Directory of everyone on the team',
                const EmployeesScreen()),
          tile(
              Icons.inbox,
              isAdmin ? 'Requests & Approvals' : 'My Requests',
              isAdmin
                  ? 'Leave and corrections waiting for a decision'
                  : 'Apply and track your requests',
              const RequestsScreen()),
          tile(Icons.beach_access, 'Leave',
              'Balances, holidays and leave types', const LeaveScreen()),
          tile(Icons.campaign, 'Announcements',
              'Office notices from admin', const AnnouncementsScreen()),
          tile(Icons.folder, 'Documents',
              'Policies and letters', const DocumentsScreen()),
          tile(Icons.receipt_long, 'Payslips',
              isAdmin ? 'Add and view payslips' : 'Your payslips',
              const PayslipsScreen()),
        ],
      ),
    );
  }
}

Widget statusChip(String status) {
  final color = switch (status) {
    'approved' => AppTheme.primary,
    'rejected' => Colors.redAccent,
    'cancelled' => AppTheme.muted,
    _ => AppTheme.investment,
  };
  return Chip(
    label: Text(status.toUpperCase(),
        style: const TextStyle(fontSize: 10.5, color: Colors.white)),
    backgroundColor: color,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
  );
}

DateTime? parseTs(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}

String fmtDays(num v) {
  var s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s;
}

/// Picks any file and uploads it to the HR folder of the
/// public storage bucket; returns the public URL (opens on
/// any phone), or null when the pick was cancelled.
Future<String?> pickHrFile(dynamic svc) async {
  final res = await FilePicker.pickFiles(withData: true);
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  final bytes = f.bytes;
  if (bytes == null) return null;
  final ext = (f.extension ?? '').toLowerCase();
  final contentType = switch (ext) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
  final url = await svc.uploadHrFile(f.name, bytes, contentType);
  return url as String;
}

/// The "upload a file" button used by the document and
/// payslip forms — fills the URL field with the uploaded
/// file's public link.
Widget uploadButton(dynamic ref, TextEditingController urlCtrl) {
  return OutlinedButton.icon(
    icon: const Icon(Icons.upload_file, size: 18),
    label: const Text('Upload a file instead'),
    onPressed: () async {
      final url = await pickHrFile(ref.read(supaServiceProvider));
      if (url != null) urlCtrl.text = url;
    },
  );
}

// ==================== Employees (admin) ====================

class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await ref.read(supaServiceProvider).selectSince('profiles', null);
      rows.sort((a, b) => ((a['name'] ?? '') as String)
          .compareTo((b['name'] ?? '') as String));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final nameCtrl =
        TextEditingController(text: (row['name'] ?? '') as String);
    var role = (row['role'] ?? 'view_only') as String;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Edit employee'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(
                        value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                        value: 'add_only', child: Text('Add only')),
                    DropdownMenuItem(
                        value: 'view_only', child: Text('View only')),
                  ],
                  onChanged: (v) => role = v ?? role,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ref.read(supaServiceProvider).updateRow(
          'profiles', row['id'] as String, {
        'name': nameCtrl.text.trim(),
        'role': role,
      });
      ref.invalidate(profileProvider);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employees')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final name = (r['name'] ?? '') as String;
                      final email = (r['email'] ?? '') as String;
                      final role = (r['role'] ?? 'view_only') as String;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.12),
                            child: Text(
                              (name.isNotEmpty
                                      ? name[0]
                                      : email.isNotEmpty
                                          ? email[0]
                                          : '?')
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(name.isNotEmpty ? name : email),
                          subtitle: Text(
                              '$email\n${role == 'admin' ? 'Admin' : role == 'add_only' ? 'Add only' : 'View only'}'),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            color: AppTheme.primary,
                            onPressed: () => _edit(r),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ==================== Requests & approvals ====================

class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _names = {};
  bool _loading = true;
  String? _error;
  bool _onlyPending = true;
  RealtimeChannel? _channel;

  bool get _isAdmin =>
      ref.read(profileProvider).value?.isAdmin ?? false;
  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    // Real-time: any change to requests refreshes the list —
    // an approval reaches the employee at once.
    _channel = Supabase.instance.client
        .channel('hr-requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'requests',
          callback: (_) => _load(silent: true),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await Supabase.instance.client
          .from('requests')
          .select()
          .order('created_at', ascending: false);
      final names =
          await ref.read(supaServiceProvider).fetchProfileNames();
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _names = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _detailsText(Map<String, dynamic> r) {
    final d = (r['details'] ?? {}) as Map<String, dynamic>;
    final parts = <String>[];
    if (r['kind'] == 'leave') {
      if (d['leave_type_name'] != null) {
        parts.add('${d['leave_type_name']} leave');
      }
      if (d['from'] != null && d['to'] != null) {
        parts.add('${d['from']} to ${d['to']}');
      }
      if (d['days'] != null) parts.add('${fmtDays(d['days'] as num)} day(s)');
    }
    if (r['kind'] == 'regularisation' && d['date'] != null) {
      parts.add('For ${d['date']}');
    }
    if (d['reason'] != null && (d['reason'] as String).isNotEmpty) {
      parts.add(d['reason'] as String);
    }
    if (d['note'] != null && (d['note'] as String).isNotEmpty) {
      parts.add(d['note'] as String);
    }
    return parts.join(' · ');
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(approve ? 'Approve request?' : 'Reject request?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['title'] as String? ?? ''),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Note (optional)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(approve ? 'Approve' : 'Reject')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final svc = ref.read(supaServiceProvider);
    try {
      await svc.updateRow('requests', r['id'] as String, {
        'status': approve ? 'approved' : 'rejected',
        'decided_by': _myId,
        'decided_at': DateTime.now().toUtc().toIso8601String(),
        'decision_note': noteCtrl.text.trim(),
      });
      await svc.insertRow('request_events', {
        'request_id': r['id'],
        'actor': _myId,
        'action': approve ? 'approved' : 'rejected',
        'note': noteCtrl.text.trim(),
      });
      // An approved leave comes out of the employee's balance.
      if (approve && r['kind'] == 'leave') {
        final d = (r['details'] ?? {}) as Map<String, dynamic>;
        if (d['leave_type_id'] != null && d['days'] != null) {
          await svc.insertRow('leave_ledger', {
            'user_id': r['user_id'],
            'leave_type_id': d['leave_type_id'],
            'delta': -(d['days'] as num).toDouble(),
            'reason': 'Leave approved',
            'request_id': r['id'],
            'created_by': _myId,
          });
        }
      }
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final svc = ref.read(supaServiceProvider);
    try {
      await svc.updateRow('requests', r['id'] as String, {
        'status': 'cancelled',
      });
      await svc.insertRow('request_events', {
        'request_id': r['id'],
        'actor': _myId,
        'action': 'cancelled',
        'note': '',
      });
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
    }
  }

  /// Brings the leave ledger back in line with a request's
  /// status: an approved leave takes its days OUT of the
  /// balance, anything else takes nothing. Corrections are
  /// compensating entries — ledger rows are never edited or
  /// deleted, exactly like the money ledger.
  Future<void> _syncLeaveLedger(
      Map<String, dynamic> r, String status) async {
    if (r['kind'] != 'leave') return;
    final d = (r['details'] ?? {}) as Map<String, dynamic>;
    if (d['leave_type_id'] == null || d['days'] == null) return;
    final rows = await Supabase.instance.client
        .from('leave_ledger')
        .select()
        .eq('request_id', r['id'] as String);
    var current = 0.0;
    for (final row in (rows as List)) {
      current += ((row as Map)['delta'] as num).toDouble();
    }
    final desired =
        status == 'approved' ? -(d['days'] as num).toDouble() : 0.0;
    final diff = desired - current;
    if (diff == 0) return;
    await ref.read(supaServiceProvider).insertRow('leave_ledger', {
      'user_id': r['user_id'],
      'leave_type_id': d['leave_type_id'],
      'delta': diff,
      'reason': 'Leave decision corrected',
      'request_id': r['id'],
      'created_by': _myId,
    });
  }

  Future<void> _editRequest(Map<String, dynamic> r) async {
    var status = r['status'] as String;
    final noteCtrl = TextEditingController(
        text: (r['decision_note'] ?? '') as String);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Edit request'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r['title'] as String? ?? ''),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration:
                        const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(
                          value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(
                          value: 'approved', child: Text('Approved')),
                      DropdownMenuItem(
                          value: 'rejected', child: Text('Rejected')),
                      DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('Cancelled')),
                    ],
                    onChanged: (v) =>
                        setLocal(() => status = v ?? status),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Admin note'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok) return;
    final svc = ref.read(supaServiceProvider);
    try {
      await svc.updateRow('requests', r['id'] as String, {
        'status': status,
        'decision_note': noteCtrl.text.trim(),
        'decided_by': _myId,
        'decided_at': DateTime.now().toUtc().toIso8601String(),
      });
      await svc.insertRow('request_events', {
        'request_id': r['id'],
        'actor': _myId,
        'action': 'edited',
        'note': 'Status: ${r['status']} -> $status',
      });
      await _syncLeaveLedger(r, status);
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete request?'),
            content: Text(
                '"${r['title']}" will be removed. If it was an '
                'approved leave, its days go back to the '
                "employee's balance first."),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      // Restore any leave balance this request had taken.
      await _syncLeaveLedger(r, 'deleted');
      await ref
          .read(supaServiceProvider)
          .deleteRow('requests', r['id'] as String);
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')));
    }
  }

  Future<void> _newRequest() async {
    final types = await Supabase.instance.client
        .from('leave_types')
        .select()
        .eq('active', true);
    if (!mounted) return;
    final leaveTypes = (types as List).cast<Map<String, dynamic>>();
    var kind = 'leave';
    Map<String, dynamic>? leaveType =
        leaveTypes.isNotEmpty ? leaveTypes.first : null;
    var from = DateTime.now();
    var to = DateTime.now();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('New request'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration:
                          const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(
                            value: 'leave', child: Text('Leave')),
                        DropdownMenuItem(
                            value: 'regularisation',
                            child: Text('Attendance correction')),
                        DropdownMenuItem(
                            value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) =>
                          setLocal(() => kind = v ?? kind),
                    ),
                    if (kind == 'leave') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        initialValue: leaveType,
                        decoration: const InputDecoration(
                            labelText: 'Leave type'),
                        items: leaveTypes
                            .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t['name'] as String)))
                            .toList(),
                        onChanged: (v) =>
                            setLocal(() => leaveType = v),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: from,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                );
                                if (d != null) {
                                  setLocal(() => from = d);
                                }
                              },
                              child: Text('From: ${fmtDate(from)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: to,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                );
                                if (d != null) setLocal(() => to = d);
                              },
                              child: Text('To: ${fmtDate(to)}'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (kind == 'regularisation') ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: from,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setLocal(() => from = d);
                        },
                        child: Text('Date: ${fmtDate(from)}'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Reason / details'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Submit')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok) return;
    final svc = ref.read(supaServiceProvider);
    final note = noteCtrl.text.trim();
    try {
      final Map<String, dynamic> details = {};
      var title = '';
      if (kind == 'leave') {
        final days = to.difference(from).inDays + 1;
        if (days < 1) throw Exception('End date is before start date');
        details.addAll({
          'leave_type_id': leaveType?['id'],
          'leave_type_name': leaveType?['name'],
          'from': fmtDate(from),
          'to': fmtDate(to),
          'days': days,
          'reason': note,
        });
        title = 'Leave — ${leaveType?['name'] ?? ''} — $days day(s)';
      } else if (kind == 'regularisation') {
        details.addAll({'date': fmtDate(from), 'note': note});
        title = 'Attendance correction — ${fmtDate(from)}';
      } else {
        details.addAll({'note': note});
        title = note.isNotEmpty ? note : 'Request';
      }
      final inserted = await Supabase.instance.client
          .from('requests')
          .insert({
            'user_id': _myId,
            'kind': kind,
            'title': title,
            'details': details,
          })
          .select('id')
          .single();
      await svc.insertRow('request_events', {
        'request_id': inserted['id'],
        'actor': _myId,
        'action': 'submitted',
        'note': '',
      });
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not submit: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rows.where((r) {
      if (!_isAdmin && r['user_id'] != _myId) return false;
      if (_onlyPending && _isAdmin) return r['status'] == 'pending';
      return true;
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Requests & Approvals' : 'My Requests'),
        actions: [
          if (_isAdmin)
            TextButton(
              onPressed: () =>
                  setState(() => _onlyPending = !_onlyPending),
              child: Text(_onlyPending ? 'Show all' : 'Pending only',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? null
          : FloatingActionButton.extended(
              onPressed: _newRequest,
              icon: const Icon(Icons.add),
              label: const Text('New request'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  onRefresh: () => _load(silent: true),
                  child: visible.isEmpty
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                                child: Text('No requests here yet.')),
                          ),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length,
                          itemBuilder: (_, i) {
                            final r = visible[i];
                            final who = _names[r['user_id']] ?? '';
                            final created = parseTs(r['created_at']);
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            r['title'] as String? ?? '',
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w600),
                                          ),
                                        ),
                                        statusChip(
                                            r['status'] as String),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if (_isAdmin) who,
                                        if (created != null)
                                          fmtDate(created),
                                        _detailsText(r),
                                      ]
                                          .where((s) => s.isNotEmpty)
                                          .join(' · '),
                                      style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: 12.5),
                                    ),
                                    if ((r['decision_note'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            top: 4),
                                        child: Text(
                                          'Admin note: ${r['decision_note']}',
                                          style: const TextStyle(
                                              fontSize: 12.5),
                                        ),
                                      ),
                                    if (r['status'] == 'pending' ||
                                        _isAdmin) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          if (!_isAdmin &&
                                              r['status'] == 'pending')
                                            TextButton(
                                              onPressed: () =>
                                                  _cancel(r),
                                              child:
                                                  const Text('Cancel'),
                                            ),
                                          if (_isAdmin) ...[
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.edit, size: 19),
                                              color: AppTheme.primary,
                                              tooltip: 'Edit',
                                              onPressed: () =>
                                                  _editRequest(r),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete,
                                                  size: 19),
                                              color: Colors.redAccent,
                                              tooltip: 'Delete',
                                              onPressed: () =>
                                                  _deleteRequest(r),
                                            ),
                                            if (r['status'] ==
                                                'pending') ...[
                                              TextButton(
                                                onPressed: () =>
                                                    _decide(r, false),
                                                child: const Text(
                                                    'Reject',
                                                    style: TextStyle(
                                                        color: Colors
                                                            .redAccent)),
                                              ),
                                              const SizedBox(width: 8),
                                              FilledButton(
                                                onPressed: () =>
                                                    _decide(r, true),
                                                child: const Text(
                                                    'Approve'),
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

// ==================== Leave ====================

class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _holidays = [];
  Map<String, String> _names = {};
  bool _loading = true;
  String? _error;
  String? _filterUser; // admin only; null = everyone

  bool get _isAdmin =>
      ref.read(profileProvider).value?.isAdmin ?? false;
  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = Supabase.instance.client;
      final types = await c.from('leave_types').select().order('name');
      final ledger = await c.from('leave_ledger').select();
      final holidays =
          await c.from('holidays').select().order('date');
      final names =
          await ref.read(supaServiceProvider).fetchProfileNames();
      if (!mounted) return;
      setState(() {
        _types = (types as List).cast<Map<String, dynamic>>();
        _ledger = (ledger as List).cast<Map<String, dynamic>>();
        _holidays = (holidays as List).cast<Map<String, dynamic>>();
        _names = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  double _balance(String userId, String typeId) {
    var sum = 0.0;
    for (final r in _ledger) {
      if (r['user_id'] == userId && r['leave_type_id'] == typeId) {
        sum += (r['delta'] as num).toDouble();
      }
    }
    return sum;
  }

  Future<void> _grantYearly() async {
    final year = DateTime.now().year;
    final reason = 'Yearly grant $year';
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Grant yearly leave?'),
            content: Text(
                'Give every employee their full yearly leave for $year '
                '(Annual 14, Casual 10, Sick 16 — as set in leave '
                'types). Anyone already granted for $year is skipped.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Grant')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      final svc = ref.read(supaServiceProvider);
      final profiles = await svc.selectSince('profiles', null);
      var added = 0;
      for (final p in profiles) {
        for (final t in _types) {
          final already = _ledger.any((r) =>
              r['user_id'] == p['id'] &&
              r['leave_type_id'] == t['id'] &&
              r['reason'] == reason);
          if (already) continue;
          await svc.insertRow('leave_ledger', {
            'user_id': p['id'],
            'leave_type_id': t['id'],
            'delta': (t['yearly_days'] as num).toDouble(),
            'reason': reason,
            'created_by': _myId,
          });
          added++;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added == 0
              ? 'Everyone was already granted for $year.'
              : 'Granted — $added entries added.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not grant: $e')));
    }
  }

  Future<void> _addHoliday() async {
    final nameCtrl = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Add holiday'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setLocal(() => date = d);
                    },
                    child: Text('Date: ${fmtDate(date)}'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Add')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok || nameCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(supaServiceProvider).insertRow('holidays', {
        'date':
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'name': nameCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add holiday: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leave')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leave')),
        body: Center(child: Text('Error: $_error')),
      );
    }
    final users = _isAdmin
        ? (_filterUser == null
            ? _names.keys.toList()
            : [_filterUser!])
        : [_myId];
    return Scaffold(
      appBar: AppBar(title: const Text('Leave')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Text('Balances',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                if (_isAdmin)
                  FilledButton.icon(
                    onPressed: _grantYearly,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Grant yearly'),
                  ),
              ],
            ),
            if (_isAdmin) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _filterUser,
                decoration:
                    const InputDecoration(labelText: 'Employee'),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Everyone')),
                  for (final e in _names.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _filterUser = v),
              ),
            ],
            const SizedBox(height: 10),
            for (final u in users)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isAdmin)
                        Text(_names[u] ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      for (final t in _types)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(t['name'] as String)),
                              Text(
                                '${fmtDays(_balance(u, t['id'] as String))} left',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Holidays',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                if (_isAdmin)
                  IconButton(
                    onPressed: _addHoliday,
                    icon: const Icon(Icons.add_circle,
                        color: AppTheme.primary),
                  ),
              ],
            ),
            for (final h in _holidays)
              ListTile(
                dense: true,
                title: Text(h['name'] as String? ?? ''),
                subtitle: Text(h['date'] as String? ?? ''),
                trailing: _isAdmin
                    ? IconButton(
                        icon: const Icon(Icons.delete,
                            size: 19, color: Colors.redAccent),
                        onPressed: () async {
                          await ref
                              .read(supaServiceProvider)
                              .deleteRow('holidays', h['id'] as String);
                          await _load();
                        },
                      )
                    : null,
              ),
            if (_holidays.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No holidays added yet.',
                    style: TextStyle(color: AppTheme.muted)),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== Announcements ====================

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState
    extends ConsumerState<AnnouncementsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  bool get _isAdmin =>
      ref.read(profileProvider).value?.isAdmin ?? false;
  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client
          .from('announcements')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('New announcement'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Message'),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Post')),
            ],
          ),
        ) ??
        false;
    if (!ok || titleCtrl.text.trim().isEmpty) return;
    await ref.read(supaServiceProvider).insertRow('announcements', {
      'title': titleCtrl.text.trim(),
      'body': bodyCtrl.text.trim(),
      'created_by': _myId,
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                            child: Text('No announcements yet.')),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final at = parseTs(r['created_at']);
                        return Card(
                          child: ListTile(
                            title: Text(r['title'] as String? ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text([
                              if (at != null) fmtDate(at),
                              r['body'] as String? ?? '',
                            ].join('\n')),
                            isThreeLine: true,
                            trailing: _isAdmin
                                ? IconButton(
                                    icon: const Icon(Icons.delete,
                                        size: 19,
                                        color: Colors.redAccent),
                                    onPressed: () async {
                                      await ref
                                          .read(supaServiceProvider)
                                          .deleteRow('announcements',
                                              r['id'] as String);
                                      await _load();
                                    },
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ==================== Documents ====================

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  List<Map<String, dynamic>> _rows = [];
  Set<String> _myAcks = {};
  Map<String, int> _ackCounts = {};
  bool _loading = true;

  bool get _isAdmin =>
      ref.read(profileProvider).value?.isAdmin ?? false;
  String get _myId => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = Supabase.instance.client;
      final res = await c
          .from('documents')
          .select()
          .order('created_at', ascending: false);
      final acks = await c.from('document_acks').select();
      final ackList = (acks as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _myAcks = ackList
            .where((a) => a['user_id'] == _myId)
            .map((a) => a['document_id'] as String)
            .toSet();
        _ackCounts = {};
        for (final a in ackList) {
          final k = a['document_id'] as String;
          _ackCounts[k] = (_ackCounts[k] ?? 0) + 1;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String what) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Delete $what?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteDoc(Map<String, dynamic> r) async {
    if (!await _confirm('document')) return;
    await ref
        .read(supaServiceProvider)
        .deleteRow('documents', r['id'] as String);
    await _load();
  }

  Future<void> _editDoc(Map<String, dynamic> r) async {
    final titleCtrl =
        TextEditingController(text: r['title'] as String? ?? '');
    final urlCtrl =
        TextEditingController(text: r['url'] as String? ?? '');
    var kind = (r['kind'] as String?) ?? 'policy';
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Edit document'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration:
                        const InputDecoration(labelText: 'Kind'),
                    items: const [
                      DropdownMenuItem(
                          value: 'policy', child: Text('Policy')),
                      DropdownMenuItem(
                          value: 'contract', child: Text('Contract')),
                      DropdownMenuItem(
                          value: 'letter', child: Text('Letter')),
                      DropdownMenuItem(
                          value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setLocal(() => kind = v ?? kind),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Link (URL)'),
                  ),
                  const SizedBox(height: 8),
                  uploadButton(ref, urlCtrl),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok || titleCtrl.text.trim().isEmpty) return;
    await ref.read(supaServiceProvider).updateRow(
        'documents', r['id'] as String, {
      'title': titleCtrl.text.trim(),
      'kind': kind,
      'url': urlCtrl.text.trim(),
    });
    await _load();
  }

  Future<void> _add() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var kind = 'policy';
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Add document'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration:
                        const InputDecoration(labelText: 'Kind'),
                    items: const [
                      DropdownMenuItem(
                          value: 'policy', child: Text('Policy')),
                      DropdownMenuItem(
                          value: 'contract', child: Text('Contract')),
                      DropdownMenuItem(
                          value: 'letter', child: Text('Letter')),
                      DropdownMenuItem(
                          value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setLocal(() => kind = v ?? kind),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Link (URL)',
                        hintText: 'https://...'),
                  ),
                  const SizedBox(height: 8),
                  uploadButton(ref, urlCtrl),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Add')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok || titleCtrl.text.trim().isEmpty) return;
    await ref.read(supaServiceProvider).insertRow('documents', {
      'title': titleCtrl.text.trim(),
      'kind': kind,
      'url': urlCtrl.text.trim(),
      'created_by': _myId,
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child:
                            Center(child: Text('No documents yet.')),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final id = r['id'] as String;
                        final acked = _myAcks.contains(id);
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.description,
                                color: AppTheme.primary),
                            title: Text(r['title'] as String? ?? ''),
                            subtitle: Text([
                              (r['kind'] as String? ?? '').toUpperCase(),
                              if (_isAdmin)
                                '${_ackCounts[id] ?? 0} acknowledged',
                              if (acked) 'You acknowledged this',
                            ].join(' · ')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((r['url'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.open_in_new,
                                        size: 19),
                                    onPressed: () => launchUrl(
                                      Uri.parse(r['url'] as String),
                                      mode: LaunchMode
                                          .externalApplication,
                                    ),
                                  ),
                                if (!acked && !_isAdmin)
                                  FilledButton(
                                    onPressed: () async {
                                      await ref
                                          .read(supaServiceProvider)
                                          .insertRow('document_acks', {
                                        'document_id': id,
                                        'user_id': _myId,
                                      });
                                      await _load();
                                    },
                                    child: const Text('Acknowledge'),
                                  ),
                                if (acked)
                                  const Icon(Icons.check_circle,
                                      color: AppTheme.primary),
                                if (_isAdmin) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        size: 19),
                                    color: AppTheme.primary,
                                    onPressed: () => _editDoc(r),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        size: 19,
                                        color: Colors.redAccent),
                                    onPressed: () => _deleteDoc(r),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ==================== Payslips ====================

class PayslipsScreen extends ConsumerStatefulWidget {
  const PayslipsScreen({super.key});

  @override
  ConsumerState<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends ConsumerState<PayslipsScreen> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _names = {};
  bool _loading = true;

  bool get _isAdmin =>
      ref.read(profileProvider).value?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client
          .from('payslips')
          .select()
          .order('month', ascending: false);
      final names =
          await ref.read(supaServiceProvider).fetchProfileNames();
      if (!mounted) return;
      setState(() {
        _rows = (res as List).cast<Map<String, dynamic>>();
        _names = names;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteSlip(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete payslip?'),
            content: const Text('This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await ref
        .read(supaServiceProvider)
        .deleteRow('payslips', r['id'] as String);
    await _load();
  }

  Future<void> _editSlip(Map<String, dynamic> r) async {
    String? userId = r['user_id'] as String?;
    final parsed = parseTs(r['month']) ?? DateTime.now();
    var month = DateTime(parsed.year, parsed.month);
    final urlCtrl =
        TextEditingController(text: r['url'] as String? ?? '');
    final noteCtrl = TextEditingController(
        text: ((r['breakdown'] ?? {}) as Map)['note'] as String? ?? '');
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Edit payslip'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: userId,
                    decoration:
                        const InputDecoration(labelText: 'Employee'),
                    items: _names.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setLocal(() => userId = v),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: month,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setLocal(() =>
                            month = DateTime(d.year, d.month));
                      }
                    },
                    child: Text('Month: ${fmtMonth(month)}'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Payslip link (URL)'),
                  ),
                  const SizedBox(height: 8),
                  uploadButton(ref, urlCtrl),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Note (optional)'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok || userId == null) return;
    await ref.read(supaServiceProvider).updateRow(
        'payslips', r['id'] as String, {
      'user_id': userId,
      'month':
          '${month.year}-${month.month.toString().padLeft(2, '0')}-01',
      'url': urlCtrl.text.trim(),
      'breakdown': {'note': noteCtrl.text.trim()},
    });
    await _load();
  }

  Future<void> _add() async {
    String? userId = _names.keys.isNotEmpty ? _names.keys.first : null;
    var month = DateTime(DateTime.now().year, DateTime.now().month);
    final urlCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Add payslip'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: userId,
                    decoration:
                        const InputDecoration(labelText: 'Employee'),
                    items: _names.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setLocal(() => userId = v),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: month,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) {
                        setLocal(() =>
                            month = DateTime(d.year, d.month));
                      }
                    },
                    child: Text('Month: ${fmtMonth(month)}'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Payslip link (URL)'),
                  ),
                  const SizedBox(height: 8),
                  uploadButton(ref, urlCtrl),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Note (optional)'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Add')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok || userId == null) return;
    await ref.read(supaServiceProvider).insertRow('payslips', {
      'user_id': userId,
      'month':
          '${month.year}-${month.month.toString().padLeft(2, '0')}-01',
      'url': urlCtrl.text.trim(),
      'breakdown': {'note': noteCtrl.text.trim()},
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payslips')),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No payslips yet.')),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        final month = parseTs(r['month']);
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long,
                                color: AppTheme.primary),
                            title: Text(month != null
                                ? fmtMonth(month)
                                : (r['month'] as String? ?? '')),
                            subtitle: Text([
                              if (_isAdmin)
                                _names[r['user_id']] ?? '',
                              ((r['breakdown'] ?? {})
                                      as Map)['note'] ??
                                  '',
                            ]
                                .where((s) => s.toString().isNotEmpty)
                                .join(' · ')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((r['url'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  IconButton(
                                    icon: const Icon(
                                        Icons.open_in_new, size: 19),
                                    onPressed: () => launchUrl(
                                      Uri.parse(r['url'] as String),
                                      mode: LaunchMode
                                          .externalApplication,
                                    ),
                                  ),
                                if (_isAdmin) ...[
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        size: 19),
                                    color: AppTheme.primary,
                                    onPressed: () => _editSlip(r),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        size: 19,
                                        color: Colors.redAccent),
                                    onPressed: () => _deleteSlip(r),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
