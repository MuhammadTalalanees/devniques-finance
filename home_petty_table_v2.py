#!/usr/bin/env python3
"""Replace _pettyLedgerTable with a full-width version:
LayoutBuilder-driven width (fills the card), flexible
Particulars, 13px text, roomier rows, plain dash for
missing category."""
P = '/home/hatch/workspace/apk-build/devniques-finance/lib/features/dashboard/dashboard_screen.dart'
lines = open(P, encoding='utf-8').read().split('\n')

def find(sub, start=0):
    for i in range(start, len(lines)):
        if sub in lines[i]:
            return i
    raise SystemExit(f'ANCHOR NOT FOUND: {sub}')

s = find('/// The home petty-cash list as a mini ledger table')
e = find('Future<void> _editPettyEntry(', s)
chunk = '\n'.join(lines[s:e])
assert '_pettyLedgerTable' in chunk and 'categoryOf' in chunk

NEW = r'''  /// The home petty-cash list as a ledger table — the same
  /// columns as the main Ledger (Talal, 2026-10-22): Date |
  /// Particulars | Category | Debit | Credit | Balance |
  /// Action. Fund = Credit, Spend = Debit; Balance is the
  /// running pot balance after that entry. Category is the
  /// entry's OWN category — older fund entries fall back to
  /// their linked ledger transaction's category. The table
  /// fills the whole card width (Particulars stretches).
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
      return '';
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
        TextStyle(fontWeight: FontWeight.bold, fontSize: 13);
    const cellStyle = TextStyle(fontSize: 13);
    const wDate = 92.0;
    const wCat = 130.0;
    const wAmt = 112.0;
    const wAct = 108.0;
    return LayoutBuilder(builder: (context, constraints) {
      final fixed =
          wDate + wCat + wAmt * 3 + (isAdmin ? wAct : 0.0);
      final wPart = (constraints.maxWidth - fixed).clamp(220.0, 900.0);
      final tableW = fixed + wPart;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: AppTheme.primary.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 11),
                child: Row(
                  children: [
                    const SizedBox(
                        width: wDate,
                        child: Text('Date', style: headStyle)),
                    SizedBox(
                        width: wPart,
                        child:
                            const Text('Particulars', style: headStyle)),
                    const SizedBox(
                        width: wCat,
                        child: Text('Category', style: headStyle)),
                    const SizedBox(
                        width: wAmt,
                        child: Text('Debit (Rs.)',
                            textAlign: TextAlign.right,
                            style: headStyle)),
                    const SizedBox(
                        width: wAmt,
                        child: Text('Credit (Rs.)',
                            textAlign: TextAlign.right,
                            style: headStyle)),
                    const SizedBox(
                        width: wAmt,
                        child: Text('Balance (Rs.)',
                            textAlign: TextAlign.right,
                            style: headStyle)),
                    if (isAdmin)
                      const SizedBox(
                          width: wAct,
                          child: Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: Text('Action', style: headStyle),
                          )),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 216,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final p in items)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: Color(0x11000000), width: 1)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                  width: wDate,
                                  child: Text(fmtDate(p.date),
                                      style: cellStyle)),
                              SizedBox(
                                width: wPart,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(right: 12),
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
                              ),
                              SizedBox(
                                width: wCat,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: categoryOf(p).isEmpty
                                      ? const Text('—',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.muted))
                                      : Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 9,
                                              vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[600],
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(categoryOf(p),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11.5,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ),
                                ),
                              ),
                              SizedBox(
                                  width: wAmt,
                                  child: Text(
                                      p.isFund
                                          ? '-'
                                          : fmtMoney(p.amount),
                                      textAlign: TextAlign.right,
                                      style: cellStyle)),
                              SizedBox(
                                  width: wAmt,
                                  child: Text(
                                      p.isFund
                                          ? fmtMoney(p.amount)
                                          : '-',
                                      textAlign: TextAlign.right,
                                      style: cellStyle)),
                              SizedBox(
                                  width: wAmt,
                                  child: Text(
                                      fmtMoney(balanceAfter[p.id] ?? 0),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              FontWeight.bold))),
                              if (isAdmin)
                                SizedBox(
                                  width: wAct,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.only(left: 12),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFFB45309),
                                            padding: EdgeInsets.zero,
                                            minimumSize:
                                                const Size(40, 34),
                                          ),
                                          onPressed: () =>
                                              _editPettyEntry(
                                                  context, ref, p),
                                          child: const Text('Edit',
                                              style:
                                                  TextStyle(fontSize: 13)),
                                        ),
                                        const Text('|',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.muted)),
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                AppTheme.expense,
                                            padding: EdgeInsets.zero,
                                            minimumSize:
                                                const Size(48, 34),
                                          ),
                                          onPressed: () =>
                                              _deletePettyEntry(
                                                  context, ref, p),
                                          child: const Text('Delete',
                                              style:
                                                  TextStyle(fontSize: 13)),
                                        ),
                                      ],
                                    ),
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
    });
  }

'''
lines[s:e] = NEW.split('\n')
open(P, 'w', encoding='utf-8').write('\n'.join(lines))
print('table replaced with full-width version')
