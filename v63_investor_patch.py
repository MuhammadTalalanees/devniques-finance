#!/usr/bin/env python3
"""Finance v63 — Talal's FINAL investor model (2026-10-22 night):
- Investors = a share register ONLY (name + share %). Add/Edit/
  Delete touch NOTHING else — never entries, never Total
  Raised, never balances.
- No more untag-on-delete, no more retag-on-rename.
- Entry form: investor name is a free TEXT field (admin types
  it), not a dropdown. The entry shows in the ledger and adds
  to Total Raised + Net Balance like any other inflow.
"""
BASE = '/home/hatch/workspace/apk-build/devniques-finance/lib/'

def load(name):
    return open(BASE + name, encoding='utf-8').read()

def save(name, src):
    open(BASE + name, 'w', encoding='utf-8').write(src)

def rep(src, old, new, count=1):
    assert src.count(old) == count, f'anchor x{src.count(old)}: {old[:70]!r}'
    return src.replace(old, new)

# ================= repos.dart =================
s = load('data/repos.dart')

s = rep(s, """  /// Saves an investor from the Investors panel / screen.
  ///
  /// An investor can exist in two ways: as a real party record, or
  /// name-only (id 'txn-<name>') through their investment entries.
  /// Saving a name-only investor creates the real record under a
  /// fresh UUID. A rename (of either kind) also renames the investor
  /// tag on their entries — otherwise the old name keeps showing as
  /// a second investor.
""",
"""  /// Saves an investor from the Investors panel / screen.
  ///
  /// An investor can exist in two ways: as a real party record, or
  /// name-only (id 'txn-<name>') through their investment entries.
  /// Saving a name-only investor creates the real record under a
  /// fresh UUID. Talal's final model (2026-10-22): saving NEVER
  /// touches entries — no retagging on rename. The name on an
  /// entry is free text the admin typed on that entry; renaming
  /// the record changes only the record.
""")

s = rep(s, """    if (p.id.startsWith('txn-')) {
      final oldName = p.id.substring(4);
      await add(Party(""",
"""    if (p.id.startsWith('txn-')) {
      await add(Party(""")

s = rep(s, """      if (oldName.trim().toLowerCase() !=
          p.name.trim().toLowerCase()) {
        await _retagInvestor(txns, oldName, p.name);
      }
    } else {""",
"""    } else {""")

s = rep(s, """      await update(p);
      if (previousName != null &&
          previousName.trim().toLowerCase() !=
              p.name.trim().toLowerCase()) {
        await _retagInvestor(txns, previousName, p.name);
      }
    }
  }""",
"""      await update(p);
    }
  }""")

s = rep(s, """  /// Removes an investor (Talal's rule, 2026-10-22 — REPLACES the
  /// 2026-10-21 delete-everything rule): ONLY the investor record
  /// and its share % go away. The capital entries STAY in the
  /// ledger — Total Raised Capital never decreases — they only
  /// lose the investor name tag, so the investors panel no longer
  /// lists this investor. The confirm dialog states this first.
  Future<void> removeInvestor(Party p, List<Txn> txns) async {
    if (!p.id.startsWith('txn-')) {
      await remove(p.id);
    }
    final f = p.name.trim().toLowerCase();
    if (f.isEmpty) return;
    final repo = _ref.read(txnRepoProvider);
    for (final t in txns) {
      if (t.isInvestment && t.investor.trim().toLowerCase() == f) {
        await repo.update(
            t.copyWith(investor: '', updatedAt: DateTime.now()));
      }
    }
  }

  Future<void> _retagInvestor(
      List<Txn> txns, String from, String to) async {
    final f = from.trim().toLowerCase();
    if (f.isEmpty) return;
    final repo = _ref.read(txnRepoProvider);
    for (final t in txns) {
      if (t.isInvestment && t.investor.trim().toLowerCase() == f) {
        await repo.update(
            t.copyWith(investor: to, updatedAt: DateTime.now()));
      }
    }
  }
""",
"""  /// Removes an investor (Talal's FINAL rule, 2026-10-22 night —
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
""")
save('data/repos.dart', s)
print('repos.dart patched')

# ================= txn_form_screen.dart =================
s = load('features/transactions/txn_form_screen.dart')

s = rep(s, """  final _docUrl = TextEditingController();
""",
"""  final _docUrl = TextEditingController();
  final _investorCtrl = TextEditingController();
""")

s = rep(s, """  String? _investorName; // selected investor name for investments
""", "")

s = rep(s, """      _investorName = e.investor.isEmpty ? null : e.investor;
""",
"""      _investorCtrl.text = e.investor;
""")

s = rep(s, """    if (_type == 'investment' && (_investorName == null || _investorName!.isEmpty)) {
      _snack('Select the investor');
      return;
    }""",
"""    if (_type == 'investment' && _investorCtrl.text.trim().isEmpty) {
      _snack('Enter the investor name');
      return;
    }""")

s = rep(s, """        investor: _type == 'investment' ? (_investorName ?? '') : '',""",
"""        investor: _type == 'investment' ? _investorCtrl.text.trim() : '',""")

s = rep(s, """          if (_type == 'investment')
            parties.when(
              data: (list) {
                final investors = list
                    .where((p) => p.kind == 'investor')
                    .map((p) => p.name)
                    .toSet();
                // Add investors from transactions
                txns.whenData((txns) {
                  for (final t in txns.where((t) => t.isInvestment)) {
                    if (t.investor.isNotEmpty) {
                      investors.add(t.investor);
                    }
                  }
                });
                final sorted = investors.toList()..sort();
                return DropdownButtonFormField<String>(
                  initialValue: _investorName,
                  decoration: const InputDecoration(
                      labelText: 'Investor'),
                  items: sorted
                      .map((name) => DropdownMenuItem(
                          value: name, child: Text(name)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _investorName = v),
                  hint: const Text(
                      'Select investor (add in More → Investors)'),
                );
              },
              loading: () =>
                  const LinearProgressIndicator(),
              error: (_, __) =>
                  const Text('Could not load investors'),
            ),""",
"""          // Talal's rule (2026-10-22): the investor name on an
          // entry is a plain TEXT label the admin types — no
          // dropdown, no link to the Investors register.
          if (_type == 'investment')
            TextFormField(
              controller: _investorCtrl,
              decoration: const InputDecoration(
                labelText: 'Investor name',
                hintText: 'Type the investor name (e.g. ASAD ANIS)',
              ),
            ),""")
save('features/transactions/txn_form_screen.dart', s)
print('txn_form patched')

# ================= dashboard panel =================
s = load('features/dashboard/dashboard_screen.dart')

s = rep(s, """  /// What deleting this investor will remove, in plain words.
  String _deleteWarning(Party p) {
    final f = p.name.trim().toLowerCase();
    final mine = txns
        .where((t) =>
            t.isInvestment && t.investor.trim().toLowerCase() == f)
        .toList();
    if (mine.isEmpty) {
      return 'Remove \\"${p.name}\\" from investors?';
    }
    final total = mine.fold(0.0, (a, t) => a + t.amount);
    return 'Remove \\"${p.name}\\" from investors? His share % will be '
        'removed. His ${mine.length} investment entries '
        '(${fmtMoney(total)}) stay in the ledger — Total Raised '
        'Capital will not change.';
  }""",
"""  /// What deleting this investor will remove, in plain words.
  /// Talal's final model: ONLY the record and its share % — the
  /// investment entries, Total Raised and balances never change.
  String _deleteWarning(Party p) {
    return 'Remove \\"${p.name}\\" from investors? Only this investor '
        'record and its share % will be deleted. Investment entries, '
        'Total Raised Capital and balances will NOT change.';
  }""")

s = rep(s, """          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 19),
              color: AppTheme.primary,
              visualDensity: VisualDensity.compact,
              onPressed: () => _showForm(context, ref, p),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 19),
              color: Colors.redAccent,
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDelete(context, ref, p),
            ),
          ],""",
"""          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.edit, size: 19),
              color: AppTheme.primary,
              visualDensity: VisualDensity.compact,
              onPressed: () => _showForm(context, ref, p),
            ),
          // A name-only investor (from entry text) has no record
          // to delete — the record is created via Edit/Add first.
          if (isAdmin && !p.id.startsWith('txn-'))
            IconButton(
              icon: const Icon(Icons.delete, size: 19),
              color: Colors.redAccent,
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDelete(context, ref, p),
            ),""")
save('features/dashboard/dashboard_screen.dart', s)
print('dashboard patched')

# ================= investors_screen.dart =================
s = load('features/investors/investors_screen.dart')

s = rep(s, """                            IconButton(
                              icon: const Icon(Icons.delete,
                                  size: 20),
                              color: Colors.redAccent,
                              onPressed: () =>
                                  _confirmDelete(context, ref, p),
                            ),""",
"""                            if (!p.id.startsWith('txn-'))
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 20),
                                color: Colors.redAccent,
                                onPressed: () =>
                                    _confirmDelete(context, ref, p),
                              ),""")
save('features/investors/investors_screen.dart', s)
print('investors_screen patched (delete button)')
print('V63 PATCH DONE')
