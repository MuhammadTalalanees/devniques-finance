import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0.00', 'en_PK');
final _date = DateFormat('dd MMM yyyy');
final _month = DateFormat('MMM yyyy');

/// "Rs 1,250,000.00"
String fmtMoney(double v) => 'Rs ${_money.format(v)}';

String fmtDate(DateTime d) => _date.format(d);

String fmtMonth(DateTime d) => _month.format(d);

/// "#5b9dff" -> Color int
int hexToInt(String hex) {
  final h = hex.replaceAll('#', '');
  return int.parse('FF$h', radix: 16);
}

DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
DateTime firstOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1, 1);
