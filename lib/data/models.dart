/// Plain data models — hand-written (no codegen) so the project
/// builds with a plain `flutter pub get`, no build_runner needed.

DateTime _dt(dynamic v) =>
    v is DateTime ? v : DateTime.parse(v.toString()).toLocal();

String _iso(DateTime d) => d.toUtc().toIso8601String();

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

class AppUser {
  final String id;
  final String email;
  final String name;
  final String role; // 'admin' | 'add_only' | 'view_only'
  final DateTime updatedAt;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.updatedAt,
  });

  bool get isAdmin => role == 'admin';
  bool get canAdd => role == 'admin' || role == 'add_only';
  bool get isViewOnly => role == 'view_only';

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: (m['email'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        role: (m['role'] ?? 'view_only') as String,
        updatedAt: m['updated_at'] != null
            ? _dt(m['updated_at'])
            : DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'updated_at': _iso(updatedAt),
      };
}

class Category {
  final String id;
  final String name;
  final String type; // 'income' | 'expense' | 'both'
  final String color;
  final DateTime updatedAt;

  Category({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.updatedAt,
  });

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        type: (m['type'] ?? 'both') as String,
        color: (m['color'] ?? '#5b9dff') as String,
        updatedAt: m['updated_at'] != null
            ? _dt(m['updated_at'])
            : DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'color': color,
        'updated_at': _iso(updatedAt),
      };

  bool matches(String txnType) => type == 'both' || type == txnType;
}

class Party {
  final String id;
  final String name;
  final String kind; // client | vendor | employee | other
  final String phone;
  final String email;
  final String notes;

  /// Investor share of Total Raised Capital, in percent (e.g. 30 =
  /// 30%). Only meaningful for kind = 'investor'. The amount shown
  /// in the app is calculated live: sharePercent% of raised capital.
  final double? sharePercent;
  final DateTime updatedAt;

  Party({
    required this.id,
    required this.name,
    required this.kind,
    this.phone = '',
    this.email = '',
    this.notes = '',
    this.sharePercent,
    required this.updatedAt,
  });

  factory Party.fromMap(Map<String, dynamic> m) => Party(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        kind: (m['kind'] ?? 'other') as String,
        phone: (m['phone'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        notes: (m['notes'] ?? '') as String,
        sharePercent: (m['share_percent'] as num?)?.toDouble(),
        updatedAt: m['updated_at'] != null
            ? _dt(m['updated_at'])
            : DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind,
        'phone': phone,
        'email': email,
        'notes': notes,
        'share_percent': sharePercent,
        'updated_at': _iso(updatedAt),
      };
}

class Txn {
  final String id;
  final String type; // 'debit' | 'credit' | 'investment' | 'profit'
  final double amount;
  final String? categoryId;
  final String categoryName; // denormalized for offline display
  final String? partyId;
  final String partyName; // denormalized
  final String investor; // investor name for 'investment' entries
  final DateTime date;
  final String description;
  final String paymentMethod;
  final String? receiptUrl;
  final String? receiptLocal; // local file path when offline (local-only)
  final String createdBy;
  final DateTime updatedAt;

  Txn({
    required this.id,
    required this.type,
    required this.amount,
    this.categoryId,
    this.categoryName = '',
    this.partyId,
    this.partyName = '',
    this.investor = '',
    required this.date,
    this.description = '',
    this.paymentMethod = 'Cash',
    this.receiptUrl,
    this.receiptLocal,
    required this.createdBy,
    required this.updatedAt,
  });

  Txn copyWith({String? investor, DateTime? updatedAt}) => Txn(
        id: id,
        type: type,
        amount: amount,
        categoryId: categoryId,
        categoryName: categoryName,
        partyId: partyId,
        partyName: partyName,
        investor: investor ?? this.investor,
        date: date,
        description: description,
        paymentMethod: paymentMethod,
        receiptUrl: receiptUrl,
        receiptLocal: receiptLocal,
        createdBy: createdBy,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Money coming in (credit, investment, or profit) vs money going out (debit).
  bool get isInflow =>
      type == 'credit' || type == 'investment' || type == 'profit';
  bool get isInvestment => type == 'investment';
  bool get isProfit => type == 'profit';
  bool get isDebit => type == 'debit';

  /// True if this is a "Petty cash fund" ledger entry (saved as debit).
  /// Matches both "Petty cash fund" (empty description) and
  /// "Petty cash fund - <notes>" formats.
  bool get isPettyCashFund =>
      type == 'debit' &&
      (description == 'Petty cash fund' ||
          description.startsWith('Petty cash fund - '));

  factory Txn.fromMap(Map<String, dynamic> m) => Txn(
        id: m['id'] as String,
        type: (m['type'] ?? 'debit') as String,
        amount: _num(m['amount']),
        categoryId: m['category_id'] as String?,
        categoryName: (m['category_name'] ?? '') as String,
        partyId: m['party_id'] as String?,
        partyName: (m['party_name'] ?? '') as String,
        investor: (m['investor'] ?? '') as String,
        date: m['date'] is DateTime
            ? m['date'] as DateTime
            : DateTime.parse('${m['date']}'),
        description: (m['description'] ?? '') as String,
        paymentMethod: (m['payment_method'] ?? 'Cash') as String,
        receiptUrl: m['receipt_url'] as String?,
        receiptLocal: m['receipt_local'] as String?,
        createdBy: (m['created_by'] ?? '') as String,
        updatedAt: m['updated_at'] != null
            ? _dt(m['updated_at'])
            : DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Map for the LOCAL sqlite table (includes denormalized names + receipt_local).
  Map<String, dynamic> toLocalMap() => {
        'id': id,
        'type': type,
        'amount': amount,
        'category_id': categoryId,
        'category_name': categoryName,
        'party_id': partyId,
        'party_name': partyName,
        'investor': investor,
        'date': date.toIso8601String().substring(0, 10),
        'description': description,
        'payment_method': paymentMethod,
        'receipt_url': receiptUrl,
        'receipt_local': receiptLocal,
        'created_by': createdBy,
        'updated_at': _iso(updatedAt),
      };

  /// Map for SUPABASE (only real columns — no denormalized / local-only fields).
  Map<String, dynamic> toRemoteMap() => {
        'id': id,
        'type': type,
        'amount': amount,
        'category_id': categoryId,
        'party_id': partyId,
        'investor': investor,
        'date': date.toIso8601String().substring(0, 10),
        'description': description,
        'payment_method': paymentMethod,
        'receipt_url': receiptUrl,
        'created_by': createdBy,
        'updated_at': _iso(updatedAt),
      };
}

/// Petty cash entry: small day-to-day expenses (lunch, etc.).
/// Stored in its own table so small expenses are viewable separately.
class PettyCash {
  final String id;
  final double amount;
  final String description;
  final DateTime date;
  final String createdBy;
  final DateTime updatedAt;
  /// 'fund' = money added INTO petty cash, 'spend' = money spent FROM it.
  final String kind;
  /// Links a 'fund' entry to its main-ledger transaction (for cascade delete).
  final String? txnId;

  /// The entry's own category — chosen in the entry form (for a
  /// fund it mirrors the linked ledger transaction's category).
  final String? categoryId;
  final String categoryName;

  PettyCash({
    required this.id,
    required this.amount,
    this.description = '',
    required this.date,
    required this.createdBy,
    required this.updatedAt,
    this.kind = 'spend',
    this.txnId,
    this.categoryId,
    this.categoryName = '',
  });

  bool get isFund => kind == 'fund';

  factory PettyCash.fromMap(Map<String, dynamic> m) => PettyCash(
        id: m['id'] as String,
        amount: _num(m['amount']),
        description: (m['description'] ?? '') as String,
        date: m['date'] is DateTime
            ? m['date'] as DateTime
            : DateTime.parse('${m['date']}'),
        createdBy: (m['created_by'] ?? '') as String,
        updatedAt: m['updated_at'] != null
            ? _dt(m['updated_at'])
            : DateTime.fromMillisecondsSinceEpoch(0),
        kind: (m['kind'] ?? 'spend') as String,
        txnId: m['txn_id'] as String?,
        categoryId: m['category_id'] as String?,
        categoryName: (m['category_name'] ?? '') as String,
      );

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'id': id,
      'amount': amount,
      'description': description,
      'date': date.toIso8601String().substring(0, 10),
      'created_by': createdBy,
      'updated_at': _iso(updatedAt),
      'kind': kind,
      'category_name': categoryName,
    };
    // Only include txn_id if set (for backward compat with old local DBs)
    if (txnId != null) m['txn_id'] = txnId;
    if (categoryId != null) m['category_id'] = categoryId;
    return m;
  }

  Map<String, dynamic> toRemoteMap() {
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
  }
}

/// One office visit, recorded automatically when the employee's phone
/// joins / leaves the office WiFi (migration v7). Read-only in this app:
/// attendance records are never edited or deleted here.
class AttendanceSession {
  final String id;
  final String userId;
  final DateTime entryAt;
  final DateTime? exitAt; // null = still in office
  final String ssid;
  final String bssid;
  final String source; // 'wifi' (auto) | 'manual' (Mark Attendance)

  AttendanceSession({
    required this.id,
    required this.userId,
    required this.entryAt,
    this.exitAt,
    this.ssid = '',
    this.bssid = '',
    this.source = 'wifi',
  });

  bool get isOpen => exitAt == null;

  /// Marked by hand from the attendance app (not via office WiFi).
  bool get isManual => source == 'manual';

  /// Time spent in office for this session (open session counts till now).
  Duration get duration => (exitAt ?? DateTime.now()).difference(entryAt);

  factory AttendanceSession.fromMap(Map<String, dynamic> m) =>
      AttendanceSession(
        id: m['id'] as String,
        userId: (m['user_id'] ?? '') as String,
        entryAt: _dt(m['entry_at']),
        exitAt: m['exit_at'] != null ? _dt(m['exit_at']) : null,
        ssid: (m['ssid'] ?? '') as String,
        bssid: (m['bssid'] ?? '') as String,
        source: (m['source'] ?? 'wifi') as String,
      );
}
