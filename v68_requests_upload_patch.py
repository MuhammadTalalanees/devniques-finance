#!/usr/bin/env python3
"""Finance v68 (Talal, 2026-10-22):
- Requests & Approvals: admin Edit (status + note, leave
  ledger auto-corrected with compensating entries) + Delete
  (balance restored first) on every record, ledger-style.
- Documents/Payslips forms: upload ANY file (public storage
  URL that opens on phones) instead of only pasting a link.
"""
FIN = '/home/hatch/workspace/apk-build/devniques-finance/lib/'

def load(p):
    return open(p, encoding='utf-8').read()

def save(p, s):
    open(p, 'w', encoding='utf-8').write(s)

def rep(s, old, new, count=1):
    assert s.count(old) == count, f'anchor x{s.count(old)}: {old[:70]!r}'
    return s.replace(old, new)

# ---------- SupaService.uploadHrFile ----------
p = FIN + 'data/remote/supa_service.dart'
s = load(p)
s = rep(s, """    return _c.storage.from('receipts').getPublicUrl(path);
  }
}""",
"""    return _c.storage.from('receipts').getPublicUrl(path);
  }

  /// HR files (documents / payslips): same public 'receipts'
  /// bucket, 'hr/' folder. The returned public URL opens on
  /// any phone browser — no sign-in needed to view the file.
  Future<String> uploadHrFile(
      String fileName, Uint8List bytes, String contentType) async {
    final name = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final path = 'hr/$name';
    await _c.storage.from('receipts').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return _c.storage.from('receipts').getPublicUrl(path);
  }
}""")
save(p, s)
print('supa_service patched')

# ---------- hr file ----------
p = FIN + 'features/hr/hr_hub_screen.dart'
s = load(p)

s = rep(s, """import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';""",
"""import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';""")

# pickHrFile helper (after the fmtDays helper)
s = rep(s, """String fmtDays(num v) {
  var s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s;
}""",
"""String fmtDays(num v) {
  var s = v.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return s;
}

/// Picks any file and uploads it to the HR folder of the
/// public storage bucket; returns the public URL (opens on
/// any phone), or null when the pick was cancelled.
Future<String?> pickHrFile(dynamic svc) async {
  final res = await FilePicker.platform.pickFiles(withData: true);
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
}""")

# ---------- Requests: edit/delete methods ----------
s = rep(s, """  Future<void> _newRequest() async {""",
"""  /// Brings the leave ledger back in line with a request's
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

  Future<void> _newRequest() async {""")

# ---------- Requests: action buttons on every record ----------
s = rep(s, """                                    if (r['status'] == 'pending') ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          if (!_isAdmin)
                                            TextButton(
                                              onPressed: () =>
                                                  _cancel(r),
                                              child:
                                                  const Text('Cancel'),
                                            ),
                                          if (_isAdmin) ...[
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
                                              child:
                                                  const Text('Approve'),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],""",
"""                                    if (r['status'] == 'pending' ||
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
                                    ],""")

# ---------- upload buttons in the 4 dialogs ----------
s = rep(s, """                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Link (URL)',
                        hintText: 'https://...'),
                  ),""",
"""                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Link (URL)',
                        hintText: 'https://...'),
                  ),
                  const SizedBox(height: 8),
                  uploadButton(ref, urlCtrl),""")

s = rep(s, """                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Link (URL)'),
                  ),""",
"""                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Link (URL)'),
                  ),
                  const SizedBox(height: 8),
                  uploadButton(ref, urlCtrl),""")

s = rep(s, """                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Payslip link (URL)'),
                  ),""",
"""                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Payslip link (URL)'),
                  ),
                  const SizedBox(height: 8),
                  uploadButton(ref, urlCtrl),""", count=2)

save(p, s)
print('V68 PATCH DONE')
