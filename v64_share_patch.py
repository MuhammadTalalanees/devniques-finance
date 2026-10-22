#!/usr/bin/env python3
"""Finance v64 — share % validation (Talal, 2026-10-22 night):
all investors' shares together can NEVER pass 100%. Saving an
investor that would overflow is blocked with a clear error:
how much is already used and how much is left."""
BASE = '/home/hatch/workspace/apk-build/devniques-finance/lib/'

def load(name):
    return open(BASE + name, encoding='utf-8').read()

def save(name, src):
    open(BASE + name, 'w', encoding='utf-8').write(src)

def rep(src, old, new, count=1):
    assert src.count(old) == count, f'anchor x{src.count(old)}: {old[:70]!r}'
    return src.replace(old, new)

# ---------- repos.dart ----------
s = load('data/repos.dart')

s = rep(s, """class PartyRepo {
  PartyRepo(this._ref);
  final Ref _ref;

  Future<void> add(Party p) async {""",
"""/// Thrown when an investor save would push the total of all
/// shares past 100% (Talal's rule, 2026-10-22). The investor
/// forms catch this, show [message] and keep the dialog open.
class ShareLimitException implements Exception {
  final String message;
  ShareLimitException(this.message);
  @override
  String toString() => message;
}

class PartyRepo {
  PartyRepo(this._ref);
  final Ref _ref;

  static String _fmtShare(double v) {
    var x = v.toStringAsFixed(2);
    if (x.contains('.')) {
      x = x.replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\\.$'), '');
    }
    return x;
  }

  /// All investors' shares together can never pass 100%.
  /// Returns the error text for this save, or null when it fits.
  Future<String?> shareLimitError(Party p) async {
    final pct = p.sharePercent;
    if (pct == null) return null;
    if (pct < 0 || pct > 100) {
      return 'Share % must be between 0 and 100.';
    }
    final rows = await LocalDb.instance.getAll('parties');
    var others = 0.0;
    for (final r in rows) {
      final q = Party.fromMap(r);
      if (q.kind == 'investor' &&
          q.id != p.id &&
          q.sharePercent != null) {
        others += q.sharePercent!;
      }
    }
    if (others + pct > 100.0001) {
      final left = 100 - others;
      return 'Shares already total ${_fmtShare(others)}%. '
          'Only ${_fmtShare(left)}% is left — this share can be '
          'at most ${_fmtShare(left)}%.';
    }
    return null;
  }

  Future<void> add(Party p) async {
    if (p.kind == 'investor') {
      final err = await shareLimitError(p);
      if (err != null) throw ShareLimitException(err);
    }""")

# saveInvestor guard at entry
s = rep(s, """  Future<void> saveInvestor(Party p, List<Txn> txns,
      {String? previousName}) async {""",
"""  Future<void> saveInvestor(Party p, List<Txn> txns,
      {String? previousName}) async {
    final err = await shareLimitError(p);
    if (err != null) throw ShareLimitException(err);""")

save('data/repos.dart', s)
print('repos.dart patched')

# ---------- dashboard form ----------
s = load('features/dashboard/dashboard_screen.dart')
s = rep(s, """              final repo = ref.read(partyRepoProvider);
              if (existing == null) {
                await repo.add(party);
              } else {
                await repo.saveInvestor(party, txns,
                    previousName: existing.name);
              }
              if (context.mounted) Navigator.pop(context);""",
"""              final repo = ref.read(partyRepoProvider);
              try {
                if (existing == null) {
                  await repo.add(party);
                } else {
                  await repo.saveInvestor(party, txns,
                      previousName: existing.name);
                }
              } on ShareLimitException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(e.message),
                        backgroundColor: Colors.redAccent),
                  );
                }
                return;
              }
              if (context.mounted) Navigator.pop(context);""")
save('features/dashboard/dashboard_screen.dart', s)
print('dashboard form patched')

# ---------- investors screen form ----------
s = load('features/investors/investors_screen.dart')
s = rep(s, """              final repo = ref.read(partyRepoProvider);
              if (existing == null) {
                await repo.add(party);
              } else {
                final txns = ref.read(txnListProvider).value ?? [];
                await repo.saveInvestor(party, txns,
                    previousName: existing.name);
              }
              if (context.mounted) Navigator.pop(context);""",
"""              final repo = ref.read(partyRepoProvider);
              try {
                if (existing == null) {
                  await repo.add(party);
                } else {
                  final txns = ref.read(txnListProvider).value ?? [];
                  await repo.saveInvestor(party, txns,
                      previousName: existing.name);
                }
              } on ShareLimitException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(e.message),
                        backgroundColor: Colors.redAccent),
                  );
                }
                return;
              }
              if (context.mounted) Navigator.pop(context);""")
save('features/investors/investors_screen.dart', s)
print('investors form patched')
print('V64 PATCH DONE')
