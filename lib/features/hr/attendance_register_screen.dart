import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repos.dart';

/// Attendance Register (Talal, 2026-10-23 — modelled on the
/// Facteno register he shared): one row per employee for a
/// chosen month with Present / Half day / Leave / Absent /
/// Late marks / Late (min) / Overtime (hrs).
///
/// Everything comes from the WiFi attendance track — the real
/// attendance in Talal's model. Rules (shown in the app too):
///  - Working day = any day except Sundays and company
///    holidays; for the running month only days up to today.
///  - Present = in office 4 hours or more that day (first
///    WiFi entry to last WiFi exit); less than that = Half day.
///  - Leave = approved leave covering that working day, when
///    the employee did not come in.
///  - Late = first entry after 10:00 AM; Late (min) sums the
///    minutes past 10:00.
///  - Overtime = hours past 9 in a day, totalled and rounded.
/// Department and Code are free text on the employee profile
/// (Employees → Edit) — Talal types them himself, no dropdown.
class AttendanceRegisterScreen extends ConsumerStatefulWidget {
  const AttendanceRegisterScreen({super.key});

  @override
  ConsumerState<AttendanceRegisterScreen> createState() =>
      _AttendanceRegisterScreenState();
}

class _RegRow {
  _RegRow(this.code, this.name, this.department);
  final String code;
  final String name;
  final String department;
  int present = 0;
  int halfDay = 0;
  int leave = 0;
  int absent = 0;
  int lateMarks = 0;
  int lateMin = 0;
  double overtime = 0;
}

class _AttendanceRegisterScreenState
    extends ConsumerState<AttendanceRegisterScreen> {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _lateHour = 10; // office start 10:00 AM PKT
  static const _halfDayHours = 4.0;
  static const _fullDayHours = 9.0;

  late int _month;
  late int _year;
  String _department = '';
  List<String> _departments = [];
  List<_RegRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
    _run();
  }

  /// An instant reframed so its fields read as PKT wall time.
  DateTime _pkt(DateTime instant) {
    final d = instant.toUtc().add(const Duration(hours: 5));
    return DateTime.utc(
        d.year, d.month, d.day, d.hour, d.minute, d.second);
  }

  DateTime? _parseDay(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    for (final f in ['dd MMM yyyy', 'dd/MM/yyyy', 'd MMM yyyy']) {
      try {
        final d = DateFormat(f).parse(s);
        return DateTime(d.year, d.month, d.day);
      } catch (_) {
        // try the next format
      }
    }
    return null;
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(supaServiceProvider);
      final client = Supabase.instance.client;

      final profiles = await svc.selectSince('profiles', null);
      final from = DateTime.utc(_year, _month, 1)
          .subtract(const Duration(hours: 5));
      final to = DateTime.utc(_year, _month + 1, 1)
          .subtract(const Duration(hours: 5));
      final sessions = await svc.fetchAttendance(from, to);
      final reqRes = await client
          .from('requests')
          .select()
          .eq('kind', 'leave')
          .eq('status', 'approved');
      final requests = (reqRes as List).cast<Map<String, dynamic>>();
      final holRes = await client.from('holidays').select();
      final holidays = <DateTime>{};
      for (final h in (holRes as List).cast<Map<String, dynamic>>()) {
        final d = _parseDay(h['date']);
        if (d != null) holidays.add(d);
      }

      // Working days of the month (no Sundays, no holidays,
      // never beyond today).
      final today = DateTime.now();
      final todayDay = DateTime(today.year, today.month, today.day);
      final lastOfMonth = DateTime(_year, _month + 1, 0);
      final cap = lastOfMonth.isAfter(todayDay) ? todayDay : lastOfMonth;
      final workingDays = <DateTime>[];
      for (var d = DateTime(_year, _month, 1);
          !d.isAfter(cap);
          d = d.add(const Duration(days: 1))) {
        if (d.weekday == DateTime.sunday) continue;
        if (holidays.contains(d)) continue;
        workingDays.add(d);
      }
      final workingSet = workingDays.toSet();

      // Approved leave days per employee (working days only).
      final leaveDays = <String, Set<DateTime>>{};
      for (final r in requests) {
        final uid = r['user_id'] as String?;
        if (uid == null) continue;
        final det = (r['details'] ?? {}) as Map<String, dynamic>;
        final f = _parseDay(det['from']);
        final t = _parseDay(det['to']) ?? f;
        if (f == null || t == null) continue;
        var d = f;
        while (!d.isAfter(t)) {
          if (workingSet.contains(d)) {
            (leaveDays[uid] ??= {}).add(d);
          }
          d = d.add(const Duration(days: 1));
        }
      }

      // WiFi sessions grouped per employee per PKT day.
      // day -> (first entry, last effective exit) in PKT wall time.
      final byUser = <String, Map<DateTime, List<DateTime>>>{};
      final nowWall = _pkt(DateTime.now());
      for (final s in sessions) {
        if (s['source'] == 'manual') continue; // WiFi track only
        final uid = s['user_id'] as String?;
        final entryRaw = s['entry_at'] as String?;
        if (uid == null || entryRaw == null) continue;
        final entry = _pkt(DateTime.parse(entryRaw));
        final day = DateTime.utc(entry.year, entry.month, entry.day);
        DateTime exit;
        final exitRaw = s['exit_at'] as String?;
        if (exitRaw != null) {
          exit = _pkt(DateTime.parse(exitRaw));
        } else if (day ==
            DateTime.utc(nowWall.year, nowWall.month, nowWall.day)) {
          exit = nowWall; // still in today
        } else {
          exit = day.add(const Duration(hours: 23, minutes: 59));
        }
        final days = byUser[uid] ??= {};
        (days[day] ??= []).addAll([entry, exit]);
      }

      final deptSet = <String>{};
      final rows = <_RegRow>[];
      for (final p in profiles) {
        final uid = p['id'] as String;
        final name = ((p['name'] ?? '') as String).isNotEmpty
            ? (p['name'] as String)
            : ((p['email'] ?? '') as String);
        final dept = ((p['department'] ?? '') as String).trim();
        if (dept.isNotEmpty) deptSet.add(dept);
        if (_department.isNotEmpty && dept != _department) continue;
        final row = _RegRow(
          ((p['emp_code'] ?? '') as String).trim(),
          name,
          dept,
        );
        final days = byUser[uid] ?? {};
        for (final d in workingDays) {
          final key = DateTime.utc(d.year, d.month, d.day);
          final stamps = days[key];
          if (stamps != null && stamps.isNotEmpty) {
            final first = stamps.reduce((a, b) => a.isBefore(b) ? a : b);
            final last = stamps.reduce((a, b) => a.isAfter(b) ? a : b);
            final spanH = last.difference(first).inMinutes / 60.0;
            if (spanH >= _halfDayHours) {
              row.present++;
            } else {
              row.halfDay++;
            }
            final tenAm = DateTime.utc(d.year, d.month, d.day, _lateHour);
            if (first.isAfter(tenAm)) {
              row.lateMarks++;
              row.lateMin += first.difference(tenAm).inMinutes;
            }
            if (spanH > _fullDayHours) row.overtime += spanH - _fullDayHours;
          } else if ((leaveDays[uid] ?? const {}).contains(d)) {
            row.leave++;
          } else {
            row.absent++;
          }
        }
        rows.add(row);
      }
      rows.sort((a, b) {
        final c = a.code.compareTo(b.code);
        if (a.code.isNotEmpty && b.code.isNotEmpty && c != 0) return c;
        if (a.code.isNotEmpty && b.code.isEmpty) return -1;
        if (a.code.isEmpty && b.code.isNotEmpty) return 1;
        return a.name.compareTo(b.name);
      });

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _departments = deptSet.toList()..sort();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = [
      for (var y = DateTime.now().year - 1; y <= DateTime.now().year + 1; y++)
        y
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Register')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    decoration: const InputDecoration(labelText: 'Month'),
                    items: [
                      for (var i = 1; i <= 12; i++)
                        DropdownMenuItem(
                            value: i, child: Text(_monthNames[i - 1])),
                    ],
                    onChanged: (v) => setState(() => _month = v ?? _month),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    decoration: const InputDecoration(labelText: 'Year'),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _year = v ?? _year),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    initialValue: _department,
                    decoration:
                        const InputDecoration(labelText: 'Department'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('All departments')),
                      for (final d in _departments)
                        DropdownMenuItem(value: d, child: Text(d)),
                    ],
                    onChanged: (v) =>
                        setState(() => _department = v ?? ''),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _run,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Run Report'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Rules: Present = 4 hrs or more in office (WiFi) that day · '
                'Half day = less than 4 hrs · Late = first entry after '
                '10:00 AM · Overtime = hours past 9 in a day · Sundays and '
                'holidays are not working days.',
                style: TextStyle(fontSize: 11.5, color: AppTheme.muted),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _rows.isEmpty
                        ? const Center(
                            child: Text('No employees found.'))
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Code')),
                                  DataColumn(label: Text('Employee')),
                                  DataColumn(label: Text('Department')),
                                  DataColumn(label: Text('Present'), numeric: true),
                                  DataColumn(label: Text('Half day'), numeric: true),
                                  DataColumn(label: Text('Leave'), numeric: true),
                                  DataColumn(label: Text('Absent'), numeric: true),
                                  DataColumn(label: Text('Late marks'), numeric: true),
                                  DataColumn(label: Text('Late (min)'), numeric: true),
                                  DataColumn(label: Text('Overtime (hrs)'), numeric: true),
                                ],
                                rows: [
                                  for (final r in _rows)
                                    DataRow(cells: [
                                      DataCell(Text(r.code.isEmpty ? '—' : r.code)),
                                      DataCell(Text(r.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600))),
                                      DataCell(Text(r.department.isEmpty
                                          ? '—'
                                          : r.department)),
                                      DataCell(Text('${r.present}')),
                                      DataCell(Text('${r.halfDay}')),
                                      DataCell(Text('${r.leave}')),
                                      DataCell(Text('${r.absent}')),
                                      DataCell(Text('${r.lateMarks}')),
                                      DataCell(Text('${r.lateMin}')),
                                      DataCell(Text('${r.overtime.round()}')),
                                    ]),
                                ],
                              ),
                            ),
                          ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${fmtMonth(DateTime(_year, _month))} · ${_rows.length} employee(s)',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
