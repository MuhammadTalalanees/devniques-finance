#!/usr/bin/env python3
"""Home _PettyCashSummary: replace the compact rows with a
ledger-style table (Date | Particulars | Category | Debit |
Credit | Balance | Action)."""
P = '/home/hatch/workspace/apk-build/devniques-finance/lib/features/dashboard/dashboard_screen.dart'
lines = open(P, encoding='utf-8').read().split('\n')

def find(sub, start=0):
    for i in range(start, len(lines)):
        if sub in lines[i]:
            return i
    raise SystemExit(f'ANCHOR NOT FOUND: {sub}')

# --- replace the list block ---
s = find("if (items.isNotEmpty) ...[")
e = find('if (canAdd) ...[', s)
# the block ends at the '],' line right before canAdd (with a
# possible blank structure) — walk back to the exact '                ],'
end = e - 1
while lines[end].strip() == '':
    end -= 1
assert lines[end] == '                ],', repr(lines[end])
chunk = '\n'.join(lines[s:end + 1])
assert 'Spent' in chunk and '_editPettyEntry' in chunk, 'unexpected chunk'
NEW = '''                if (items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  _pettyLedgerTable(context, ref, items, isAdmin),
                ],'''
lines[s:end + 1] = NEW.split('\n')
print(f'list block replaced ({end + 1 - s} lines out)')

# --- insert the table method before _editPettyEntry ---
c = find('Future<void> _editPettyEntry(')
METHOD = r'''  /// The home petty-cash list as a mini ledger table — the
  /// same columns as the main Ledger (Talal, 2026-10-22):
  /// Date | Particulars | Category | Debit | Credit |
  /// Balance | Action. Fund = Credit, Spend = Debit; Balance
  /// is the running pot balance after that entry. Category is
  /// the entry's OWN category — older fund entries fall back
  /// to their linked ledger transaction's category.
  Widget _pettyLedgerTable(BuildContext context, WidgetRef ref,
      List<PettyCash> items, bool isAdmin) {
    final txns = ref.watch(txnListProvider).value ?? const <Txn>[];
    final txnById = {for (final t in txns) t.id: t};
    String categoryOf(PettyCash p) {
      if (p.categoryName.isNotEmpty) return p.categoryName;
      if (p.txnId != null) {
        final c = txnById[p.txnId!]?.categoryName ?? '';
        if (c.isNotEmpty) return c;
      }
      return '—';
    }

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

    const headStyle =
        TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    const cellStyle = TextStyle(fontSize: 12);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: isAdmin ? 720 : 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: AppTheme.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                      width: 80, child: Text('Date', style: headStyle)),
                  const SizedBox(
                      width: 160,
                      child: Text('Particulars', style: headStyle)),
                  const SizedBox(
                      width: 110,
                      child: Text('Category', style: headStyle)),
                  const SizedBox(
                      width: 90,
                      child: Text('Debit (Rs.)',
                          textAlign: TextAlign.right, style: headStyle)),
                  const SizedBox(
                      width: 90,
                      child: Text('Credit (Rs.)',
                          textAlign: TextAlign.right, style: headStyle)),
                  const SizedBox(
                      width: 90,
                      child: Text('Balance (Rs.)',
                          textAlign: TextAlign.right, style: headStyle)),
                  if (isAdmin)
                    const SizedBox(
                        width: 100,
                        child: Text('Action', style: headStyle)),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 132,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final p in items)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: Color(0x11000000), width: 1)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 80,
                                child: Text(fmtDate(p.date),
                                    style: cellStyle)),
                            SizedBox(
                              width: 160,
                              child: Text(
                                p.description.isEmpty
                                    ? (p.isFund
                                        ? 'Funds added'
                                        : 'Petty expense')
                                    : p.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: cellStyle,
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
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text(categoryOf(p),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            SizedBox(
                                width: 90,
                                child: Text(
                                    p.isFund ? '-' : fmtMoney(p.amount),
                                    textAlign: TextAlign.right,
                                    style: cellStyle)),
                            SizedBox(
                                width: 90,
                                child: Text(
                                    p.isFund ? fmtMoney(p.amount) : '-',
                                    textAlign: TextAlign.right,
                                    style: cellStyle)),
                            SizedBox(
                                width: 90,
                                child: Text(
                                    fmtMoney(balanceAfter[p.id] ?? 0),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold))),
                            if (isAdmin)
                              SizedBox(
                                width: 100,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFFB45309),
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(40, 32),
                                      ),
                                      onPressed: () => _editPettyEntry(
                                          context, ref, p),
                                      child: const Text('Edit',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                    const Text('|',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.muted)),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.expense,
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(48, 32),
                                      ),
                                      onPressed: () =>
                                          _deletePettyEntry(
                                              context, ref, p),
                                      child: const Text('Delete',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
lines.insert(c, METHOD)
print('table method inserted')
open(P, 'w', encoding='utf-8').write('\n'.join(lines))
print('OK')
