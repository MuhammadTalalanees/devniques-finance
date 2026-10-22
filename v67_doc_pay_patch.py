#!/usr/bin/env python3
"""Finance v67 — Documents + Payslips: admin Edit/Delete
(Talal, 2026-10-22: 'in dono pr delete k button nhi aa raha
lagao, edit bhi')."""
P = '/home/hatch/workspace/apk-build/devniques-finance/lib/features/hr/hr_hub_screen.dart'
s = open(P).read()

def rep(old, new, count=1):
    global s
    assert s.count(old) == count, f'anchor x{s.count(old)}: {old[:70]!r}'
    s = s.replace(old, new)

# ---------- Documents: edit/delete methods ----------
rep("""  Future<void> _add() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var kind = 'policy';""",
"""  Future<bool> _confirm(String what) async {
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
    var kind = 'policy';""")

# ---------- Documents: trailing buttons ----------
rep("""                                if (acked)
                                  const Icon(Icons.check_circle,
                                      color: AppTheme.primary),
                              ],
                            ),""",
"""                                if (acked)
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
                            ),""")

# ---------- Payslips: edit/delete methods ----------
rep("""  Future<void> _add() async {
    String? userId = _names.keys.isNotEmpty ? _names.keys.first : null;""",
"""  Future<void> _deleteSlip(Map<String, dynamic> r) async {
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
    String? userId = _names.keys.isNotEmpty ? _names.keys.first : null;""")

# ---------- Payslips: trailing buttons ----------
rep("""                            trailing: (r['url'] ?? '')
                                    .toString()
                                    .isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                        Icons.open_in_new, size: 19),
                                    onPressed: () => launchUrl(
                                      Uri.parse(r['url'] as String),
                                      mode: LaunchMode
                                          .externalApplication,
                                    ),
                                  )
                                : null,""",
"""                            trailing: Row(
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
                            ),""")

open(P, 'w').write(s)
print('V67 PATCH DONE')
