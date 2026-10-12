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
  final String role; // 'admin' | 'staff'
  final DateTime updatedAt;

  AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.updatedAt,
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        email: (m['email'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        role: (m['role'] ?? 'staff') as String,
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
  final DateTime updatedAt;

  Party({
    required this.id,
    required this.name,
    required this.kind,
    this.phone = '',
    this.email = '',
    this.notes = '',
    required this.updatedAt,
  });

  factory Party.fromMap(Map<String, dynamic> m) => Party(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        kind: (m['kind'] ?? 'other') as String,
        phone: (m['phone'] ?? '') as String,
        email: (m['email'] ?? '') as String,
        notes: (m['notes'] ?? '') as String,
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
        'updated_at': _iso(updatedAt),
      };
}

class Txn {
  final String id;
  final String type; // 'income' | 'expense'
  final double amount;
  final String? categoryId;
  final String categoryName; // denormalized for offline display
  final String? partyId;
  final String partyName; // denormalized
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
    required this.date,
    this.description = '',
    this.paymentMethod = 'Cash',
    this.receiptUrl,
    this.receiptLocal,
    required this.createdBy,
    required this.updatedAt,
  });

  bool get isIncome => type == 'income';

  factory Txn.fromMap(Map<String, dynamic> m) => Txn(
        id: m['id'] as String,
        type: (m['type'] ?? 'expense') as String,
        amount: _num(m['amount']),
        categoryId: m['category_id'] as String?,
        categoryName: (m['category_name'] ?? '') as String,
        partyId: m['party_id'] as String?,
        partyName: (m['party_name'] ?? '') as String,
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
        'date': date.toIso8601String().substring(0, 10),
        'description': description,
        'payment_method': paymentMethod,
        'receipt_url': receiptUrl,
        'created_by': createdBy,
        'updated_at': _iso(updatedAt),
      };
}
