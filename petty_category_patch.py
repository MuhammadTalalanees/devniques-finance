#!/usr/bin/env python3
"""Petty cash categories end-to-end + home ledger table.
- PettyCash model: categoryId/categoryName
- Local DB v7: petty_cash category columns
- Sync: allow-list + pull denormalization
- txn form: fund/spend entries inherit the form's category
- petty edit dialog: category dropdown
- home _PettyCashSummary: ledger-style table"""
import sys

def patch(path, pairs):
    src = open(path, encoding='utf-8').read()
    for old, new in pairs:
        assert src.count(old) == 1, f'{path}: anchor not unique/found: {old[:70]!r} (count={src.count(old)})'
        src = src.replace(old, new)
    open(path, 'w', encoding='utf-8').write(src)
    print(f'OK {path} ({len(pairs)} edits)')

B = '/home/hatch/workspace/apk-build/devniques-finance/'

# ---------------- models.dart ----------------
patch(B + 'lib/data/models.dart', [
("""  /// Links a 'fund' entry to its main-ledger transaction (for cascade delete).
  final String? txnId;""",
 """  /// Links a 'fund' entry to its main-ledger transaction (for cascade delete).
  final String? txnId;

  /// The entry's own category — chosen in the entry form (for a
  /// fund it mirrors the linked ledger transaction's category).
  final String? categoryId;
  final String categoryName;"""),
("""    this.kind = 'spend',
    this.txnId,
  });""",
 """    this.kind = 'spend',
    this.txnId,
    this.categoryId,
    this.categoryName = '',
  });"""),
("""        kind: (m['kind'] ?? 'spend') as String,
        txnId: m['txn_id'] as String?,
      );""",
 """        kind: (m['kind'] ?? 'spend') as String,
        txnId: m['txn_id'] as String?,
        categoryId: m['category_id'] as String?,
        categoryName: (m['category_name'] ?? '') as String,
      );"""),
("""      'kind': kind,
    };
    // Only include txn_id if set (for backward compat with old local DBs)
    if (txnId != null) m['txn_id'] = txnId;
    return m;
  }""",
 """      'kind': kind,
      'category_name': categoryName,
    };
    // Only include txn_id if set (for backward compat with old local DBs)
    if (txnId != null) m['txn_id'] = txnId;
    if (categoryId != null) m['category_id'] = categoryId;
    return m;
  }"""),
("""  Map<String, dynamic> toRemoteMap() => {
        'id': id,
        'amount': amount,
        'description': description,
        'date': date.toIso8601String().substring(0, 10),
        'created_by': createdBy,
        'updated_at': _iso(updatedAt),
        'kind': kind,
        'txn_id': txnId,
      };""",
 """  Map<String, dynamic> toRemoteMap() {
    final m = <String, dynamic>{
      'id': id,
      'amount': amount,
      'description': description,
      'date': date.toIso8601String().substring(0, 10),
      'created_by': createdBy,
      'updated_at': _iso(updatedAt),
      'kind': kind,
      'txn_id': txnId,
    };
    // Sent only when set — the server column arrives with
    // migration v12; a null category syncs exactly as before.
    if (categoryId != null) m['category_id'] = categoryId;
    return m;
  }"""),
])

# ---------------- local_db.dart ----------------
patch(B + 'lib/data/local/local_db.dart', [
("      version: 6,", "      version: 7,"),
("""    if (oldV < 6) {
      // v6: investor share % of Total Raised Capital (home Investors panel).
      await db.execute(
          "ALTER TABLE parties ADD COLUMN share_percent REAL");
    }
  }""",
 """    if (oldV < 6) {
      // v6: investor share % of Total Raised Capital (home Investors panel).
      await db.execute(
          "ALTER TABLE parties ADD COLUMN share_percent REAL");
    }
    if (oldV < 7) {
      // v7: each petty cash entry carries its own category.
      await db.execute(
          "ALTER TABLE petty_cash ADD COLUMN category_id TEXT");
      await db.execute(
          "ALTER TABLE petty_cash ADD COLUMN category_name TEXT NOT NULL DEFAULT ''");
    }
  }"""),
("""        date TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'spend',
        txn_id TEXT,
        created_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)''');""",
 """        date TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'spend',
        txn_id TEXT, category_id TEXT,
        category_name TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL)''');"""),
])

# ---------------- repos.dart ----------------
patch(B + 'lib/data/repos.dart', [
("""    'petty_cash': {
      'id', 'amount', 'description', 'date', 'created_by', 'updated_at',
      'kind', 'txn_id'
    },""",
 """    'petty_cash': {
      'id', 'amount', 'description', 'date', 'created_by', 'updated_at',
      'kind', 'txn_id', 'category_id', 'category_name'
    },"""),
("""      } else {
        await db.upsertAll(local, [for (final r in rows) _localize(t, r)]);
      }""",
 """      } else if (t == 'petty_cash') {
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
      }"""),
])

# ---------------- txn_form_screen.dart ----------------
patch(B + 'lib/features/transactions/txn_form_screen.dart', [
("""          kind: 'fund',
          txnId: txn.id,
        );""",
 """          kind: 'fund',
          txnId: txn.id,
          categoryId: txn.categoryId,
          categoryName: txn.categoryName,
        );"""),
("""            kind: 'fund',
            txnId: existing.id,
          );""",
 """            kind: 'fund',
            txnId: existing.id,
            categoryId: existing.categoryId,
            categoryName: existing.categoryName,
          );"""),
("""          kind: 'spend',
        );
        await pettyRepo.add(pettyEntry);""",
 """          kind: 'spend',
          categoryId: _categoryId,
          categoryName: cat.isNotEmpty ? cat.first.name : '',
        );
        await pettyRepo.add(pettyEntry);"""),
])

# ---------------- petty_cash_screen.dart (edit dialog) ----------------
patch(B + 'lib/features/petty_cash/petty_cash_screen.dart', [
("""    final amountCtrl =
        TextEditingController(text: p.amount.toStringAsFixed(0));
    final descCtrl = TextEditingController(text: p.description);
    DateTime date = p.date;""",
 """    final amountCtrl =
        TextEditingController(text: p.amount.toStringAsFixed(0));
    final descCtrl = TextEditingController(text: p.description);
    DateTime date = p.date;
    final allCats = await ref.read(categoryListProvider.future);
    final cats = allCats
        .where((c) => p.isFund
            ? (c.type == 'income' || c.type == 'both')
            : (c.type == 'expense' || c.type == 'both'))
        .toList();
    String? catId = p.categoryId;"""),
("""                    child: Text(
                        '${date.day}/${date.month}/${date.year}'),
                  ),
                ],
              ),
            ],
          ),""",
 """                    child: Text(
                        '${date.day}/${date.month}/${date.year}'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: catId,
                decoration:
                    const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('No category')),
                  for (final c in cats)
                    DropdownMenuItem<String?>(
                        value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => catId = v),
              ),
            ],
          ),"""),
("""        kind: p.kind,
        txnId: p.txnId,
      );""",
 """        kind: p.kind,
        txnId: p.txnId,
        categoryId: catId,
        categoryName:
            cats.where((c) => c.id == catId).firstOrNull?.name ?? '',
      );"""),
])
print('ALL PATCHES APPLIED')
