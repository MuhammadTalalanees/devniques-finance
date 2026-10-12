import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

/// Monthly report with PDF + CSV export.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  List<Txn> _forMonth(List<Txn> all) => all
      .where((t) =>
          t.date.year == _month.year && t.date.month == _month.month)
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(txnListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: () => _exportPdf(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Export CSV',
            onPressed: () => _exportCsv(ref),
          ),
        ],
      ),
      body: txns.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final list = _forMonth(all);
          final income = list
              .where((t) => t.isIncome)
              .fold(0.0, (a, t) => a + t.amount);
          final expense = list
              .where((t) => !t.isIncome)
              .fold(0.0, (a, t) => a + t.amount);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() => _month =
                            DateTime(
                                _month.year, _month.month - 1))),
                    Text(fmtMonth(_month),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() => _month =
                            DateTime(
                                _month.year, _month.month + 1))),
                  ],
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceAround,
                      children: [
                        _Total('Income', income, Colors.green),
                        _Total('Expense', expense, Colors.red),
                        _Total('Net', income - expense,
                            Colors.blue),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text('No entries this month.'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final t = list[i];
                          return ListTile(
                            dense: true,
                            title: Text(t.description.isEmpty
                                ? t.categoryName
                                : t.description),
                            subtitle: Text(
                                '${fmtDate(t.date)} · ${t.categoryName}'),
                            trailing: Text(
                              '${t.isIncome ? '+' : '−'} ${fmtMoney(t.amount)}',
                              style: TextStyle(
                                  color: t.isIncome
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportPdf(
      BuildContext context, WidgetRef ref) async {
    final all = await ref.read(txnListProvider.future);
    final list = _forMonth(all);
    final income =
        list.where((t) => t.isIncome).fold(0.0, (a, t) => a + t.amount);
    final expense = list
        .where((t) => !t.isIncome)
        .fold(0.0, (a, t) => a + t.amount);

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Header(
            level: 0,
            child: pw.Text('Devniques Finance — ${fmtMonth(_month)}',
                style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 8),
        pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Income: ${fmtMoney(income)}'),
              pw.Text('Expense: ${fmtMoney(expense)}'),
              pw.Text('Net: ${fmtMoney(income - expense)}'),
            ]),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Date', 'Type', 'Category', 'Party', 'Description', 'Amount'
          ],
          data: [
            for (final t in list)
              [
                fmtDate(t.date),
                t.type,
                t.categoryName,
                t.partyName,
                t.description,
                fmtMoney(t.amount),
              ],
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold),
        ),
      ],
    ));
    await Printing.sharePdf(
        bytes: await doc.save(),
        filename:
            'devniques-finance-${_month.year}-${_month.month}.pdf');
  }

  Future<void> _exportCsv(WidgetRef ref) async {
    final all = await ref.read(txnListProvider.future);
    final list = _forMonth(all);
    final sb = StringBuffer('Date,Type,Category,Party,Description,Method,Amount\n');
    for (final t in list) {
      sb.write(
          '${t.date.toIso8601String().substring(0, 10)},${t.type},"${t.categoryName}","${t.partyName}","${t.description.replaceAll('"', "'")}",${t.paymentMethod},${t.amount}\n');
    }
    await Share.shareXFiles(
      [XFile.fromData(
          Uint8List.fromList(sb.toString().codeUnits),
          name:
              'devniques-finance-${_month.year}-${_month.month}.csv',
          mimeType: 'text/csv')],
      text: 'Devniques Finance — ${fmtMonth(_month)}',
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _Total(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12)),
      Text(fmtMoney(value),
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15)),
    ]);
  }
}
