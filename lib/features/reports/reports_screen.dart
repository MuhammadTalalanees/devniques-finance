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
import '../../core/theme.dart';

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
          final inflow = list
              .where((t) => t.isInflow)
              .fold(0.0, (a, t) => a + t.amount);
          final expense = list
              .where((t) => t.isDebit)
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
                        _Total('Inflow', inflow, AppTheme.income),
                        _Total('Expense', expense, AppTheme.expense),
                        _Total('Net', inflow - expense,
                            AppTheme.primary),
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
                              '${t.isDebit ? '−' : '+'} ${fmtMoney(t.amount)}',
                              style: TextStyle(
                                  color: t.isDebit
                                      ? AppTheme.expense
                                      : AppTheme.income,
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
    final inflow =
        list.where((t) => t.isInflow).fold(0.0, (a, t) => a + t.amount);
    final expense = list
        .where((t) => t.isDebit)
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
              pw.Text('Inflow: ${fmtMoney(inflow)}'),
              pw.Text('Expense: ${fmtMoney(expense)}'),
              pw.Text('Net: ${fmtMoney(inflow - expense)}'),
            ]),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const [
            'Date',
            'Particulars',
            'Category / Investor',
            'Debit (Rs.)',
            'Credit (Rs.)',
            'Balance (Rs.)'
          ],
          data: [
            for (final t in list)
              [
                fmtDate(t.date),
                t.description.isEmpty
                    ? (t.partyName.isEmpty
                        ? t.categoryName
                        : t.partyName)
                    : t.description,
                t.isDebit
                    ? (t.categoryName.isEmpty
                        ? 'Uncategorized'
                        : t.categoryName)
                    : (t.investor.isEmpty
                        ? 'General'
                        : t.investor),
                t.isDebit ? fmtMoney(t.amount) : '—',
                t.isInflow ? fmtMoney(t.amount) : '—',
                fmtMoney(
                    list
                            .where((x) =>
                                !x.date.isAfter(t.date))
                            .fold(
                                0.0,
                                (a, x) => a +
                                    (x.isInflow
                                        ? x.amount
                                        : -x.amount))),
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
    // Columns match Devniques_Account_Management.html export.
    final sb = StringBuffer(
        '\uFEFFDate,Particulars,Category / Investor,Debit (Rs.),Credit (Rs.),Running Balance (Rs.),Document URL\n');
    double runningBalance = 0;
    // Sort oldest first for running balance.
    final sorted = list.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final t in sorted) {
      final dr = t.isDebit ? t.amount : 0;
      final cr = t.isInflow ? t.amount : 0;
      runningBalance += (cr - dr);
      final tag = t.isDebit
          ? (t.categoryName.isEmpty ? 'Uncategorized' : t.categoryName)
          : (t.investor.isEmpty ? 'General' : t.investor);
      final desc = t.description.isEmpty
          ? (t.partyName.isEmpty ? tag : t.partyName)
          : t.description;
      sb.write(
          '"${t.date.toIso8601String().substring(0, 10)}","${desc.replaceAll('"', '""')}","${tag.replaceAll('"', '""')}",$dr,$cr,$runningBalance,"${t.receiptUrl ?? ''}"\n');
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
          style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 12)),
      Text(fmtMoney(value),
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15)),
    ]);
  }
}
