#!/usr/bin/env python3
"""PettyCashScreen: replace the card list with a ledger-style
table (Date | Particulars | Category | Debit | Credit |
Balance | Action), mirroring dashboard_screen.dart's Ledger."""
P = '/home/hatch/workspace/apk-build/devniques-finance/lib/features/petty_cash/petty_cash_screen.dart'
lines = open(P, encoding='utf-8').read().split('\n')

def find(sub, start=0):
    for i in range(start, len(lines)):
        if sub in lines[i]:
            return i
    raise SystemExit(f'ANCHOR NOT FOUND: {sub}')

# --- A. watch txns at build top (for fund-category lookup) ---
a = find('final list = ref.watch(pettyCashListProvider);')
lines.insert(a + 1,
    "    final txns = ref.watch(txnListProvider).value ?? const <Txn>[];")
print('A. txns watch added')

# --- B. replace the card list with the table ---
s = find('child: items.isEmpty') - 1
assert 'Expanded(' in lines[s], lines[s]
e = s
while True:
    e += 1
    if lines[e] == '              ),' and lines[e + 1] == '            ],':
        break
chunk = '\n'.join(lines[s:e + 1])
assert 'ListTile' in chunk and 'Cascade delete' in chunk, 'unexpected chunk'
NEW = r'''              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text('No petty cash entries yet.'))
                    : _buildTable(context, ref, items, txns, isAdmin),
              )'''
lines[s:e + 1] = NEW.split('\n')
print(f'B. list replaced ({e + 1 - s} lines out)')

# --- C. helper methods before _downloadCsv ---
c = find('Future<void> _downloadCsv')
METHODS = r'''  /// Ledger-style table (same layout as the main Ledger):
  /// Date | Particulars | Category badge | Debit | Credit |
  /// Balance | Action. Fund = Credit, Spend = Debit; Balance
  /// is the running pot balance after that entry.
  Widget _buildTable(BuildContext context, WidgetRef ref,
      List<PettyCash> items, List<Txn> txns, bool isAdmin) {
    // Running balance after each entry, computed oldest-first
    // and attached by entry id; display stays newest-first.
    final chronological = items.toList()
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.updatedAt.compareTo(b.updatedAt);
      });
    final balanceAfter = <String, double>{};
    var run = 0.0;
    for (final p in chronological) {
      run += p.isFund ? p.amount : -p.amount;
      balanceAfter[p.id] = run;
    }
    final txnById = {for (final t in txns) t.id: t};
    String categoryOf(PettyCash p) {
      if (p.isFund && p.txnId != null) {
        final c = txnById[p.txnId!]?.categoryName ?? '';
        if (c.isNotEmpty) return c;
      }
      return 'Petty Cash';
    }

    TextStyle head() => const TextStyle(
        fontWeight: FontWeight.bold, fontSize: 12);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: isAdmin ? 730 : 630,
        child: Column(
          children: [
            Container(
              color: AppTheme.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text('Date', style: head())),
                  SizedBox(
                      width: 170,
                      child: Text('Particulars', style: head())),
                  SizedBox(
                      width: 110,
                      child: Text('Category', style: head())),
                  SizedBox(
                      width: 90,
                      child: Text('Debit (Rs.)',
                          textAlign: TextAlign.right, style: head())),
                  SizedBox(
                      width: 90,
                      child: Text('Credit (Rs.)',
                          textAlign: TextAlign.right, style: head())),
                  SizedBox(
                      width: 90,
                      child: Text('Balance (Rs.)',
                          textAlign: TextAlign.right, style: head())),
                  if (isAdmin)
                    SizedBox(
                        width: 100, child: Text('Action', style: head())),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _row(context, ref, items[i],
                    categoryOf(items[i]),
                    balanceAfter[items[i].id] ?? 0, isAdmin),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, PettyCash p,
      String category, double balance, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0x11000000), width: 1)),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(fmtDate(p.date),
                  style: const TextStyle(fontSize: 12))),
          SizedBox(
            width: 170,
            child: Text(
              p.description.isEmpty
                  ? (p.isFund ? 'Funds added' : 'Petty expense')
                  : p.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(category,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          SizedBox(
              width: 90,
              child: Text(p.isFund ? '-' : fmtMoney(p.amount),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12))),
          SizedBox(
              width: 90,
              child: Text(p.isFund ? fmtMoney(p.amount) : '-',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12))),
          SizedBox(
              width: 90,
              child: Text(fmtMoney(balance),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold))),
          if (isAdmin)
            SizedBox(
              width: 100,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 32),
                    ),
                    onPressed: () => _editEntry(context, ref, p),
                    child:
                        const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                  const Text('|',
                      style:
                          TextStyle(fontSize: 12, color: AppTheme.muted)),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.expense,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 32),
                    ),
                    onPressed: () => _deleteEntry(context, ref, p),
                    child: const Text('Delete',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(
      BuildContext context, WidgetRef ref, PettyCash p) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete?'),
            content: const Text('Remove this petty cash entry?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;
    // Cascade delete: if this petty cash fund entry is linked
    // to a ledger transaction, delete that too.
    if (p.txnId != null) {
      await ref.read(txnRepoProvider).remove(p.txnId!);
    }
    await ref.read(pettyCashRepoProvider).remove(p.id);
  }

'''
lines.insert(c, METHODS)
print('C. table methods inserted')

open(P, 'w', encoding='utf-8').write('\n'.join(lines))
print('OK')
