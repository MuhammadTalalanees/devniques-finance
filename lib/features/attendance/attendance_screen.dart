import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

/// Attendance — day view, one ROW per session (Talal,
/// 2026-10-23: the old month-of-cards layout made endless
/// long columns on PC).
///
/// Har employee ka apna block hai; us ke andar us din ki har
/// session ek saaf row hai — entry, exit, source, duration.
/// Admin kisi bhi row ko wahin se Edit/Delete kar sakta hai
/// (attendance correction, migration v15) — baaki sab ke liye
/// records waise hi lock hain jaise pehle thay. Working hours
/// ka rule wahi purana: pehli WiFi entry se aakhri WiFi exit
/// tak ka span. Saare times Pakistan time mein.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

/// An instant re-framed as Pakistan wall time (UTC+5, no DST):
/// its fields read as the PKT clock. Attendance days and times
/// are always shown in PKT, wherever the viewer is.
DateTime pkt(DateTime t) => t.toUtc().add(const Duration(hours: 5));

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime _day = _todayPkt();

  static DateTime _todayPkt() {
    final n = pkt(DateTime.now());
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _month => firstOfMonth(_day);

  static final _time = DateFormat('hh:mm a');

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  bool _isToday(DateTime d) {
    final t = _todayPkt();
    return d.year == t.year && d.month == t.month && d.day == t.day;
  }

  void _shiftDay(int delta) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));
  }

  /// PKT wall fields -> the real instant.
  DateTime _instantFromWall(DateTime wall) => DateTime.utc(
        wall.year,
        wall.month,
        wall.day,
        wall.hour,
        wall.minute,
      ).subtract(const Duration(hours: 5));

  Future<DateTime?> _pickWall(
      BuildContext context, DateTime initialWall) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initialWall,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (d == null || !context.mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialWall),
    );
    if (t == null) return null;
    return DateTime.utc(d.year, d.month, d.day, t.hour, t.minute);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editSession(AttendanceSession s) async {
    var entryWall = pkt(s.entryAt);
    var exitWall = s.exitAt != null ? pkt(s.exitAt!) : null;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Edit attendance'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.isManual
                        ? 'Manual session'
                        : 'WiFi session${s.ssid.isNotEmpty ? ' · ${s.ssid}' : ''}',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.login, size: 18),
                    label: Text('Entry: ${fmtDate(entryWall)} '
                        '${_time.format(entryWall)}'),
                    onPressed: () async {
                      final w = await _pickWall(context, entryWall);
                      if (w != null) setLocal(() => entryWall = w);
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text(exitWall == null
                        ? 'Exit: still in office'
                        : 'Exit: ${fmtDate(exitWall!)} '
                            '${_time.format(exitWall!)}'),
                    onPressed: () async {
                      final w =
                          await _pickWall(context, exitWall ?? entryWall);
                      if (w != null) setLocal(() => exitWall = w);
                    },
                  ),
                  if (exitWall != null)
                    TextButton(
                      onPressed: () => setLocal(() => exitWall = null),
                      child: const Text('Clear exit (still in office)'),
                    ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save')),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok) return;
    if (exitWall != null && !exitWall!.isAfter(entryWall)) {
      _snack('Exit must be after entry.');
      return;
    }
    try {
      await ref.read(supaServiceProvider).updateRow(
          'attendance_sessions', s.id, {
        'entry_at': _instantFromWall(entryWall).toIso8601String(),
        'exit_at': exitWall == null
            ? null
            : _instantFromWall(exitWall!).toIso8601String(),
      });
      ref.invalidate(attendanceMonthProvider(_month));
      _snack('Attendance updated.');
    } catch (e) {
      _snack('Could not save: $e');
    }
  }

  Future<void> _deleteSession(AttendanceSession s) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete this session?'),
            content: Text(
                '${_time.format(pkt(s.entryAt))}'
                '${s.exitAt != null ? ' → ${_time.format(pkt(s.exitAt!))}' : ' → still in'}'
                ' will be removed from the database. '
                'This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ref
          .read(supaServiceProvider)
          .deleteRow('attendance_sessions', s.id);
      ref.invalidate(attendanceMonthProvider(_month));
      _snack('Session deleted.');
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(attendanceMonthProvider(_month));
    final namesAsync = ref.watch(profileNamesProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin = profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final myId = profile.whenData((p) => p?.id).value;
    final names = namesAsync.value ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Human Resources (HR)')),
      body: Column(
        children: [
          // ---- day selector ----
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftDay(-1),
                ),
                Column(
                  children: [
                    Text(
                      _isToday(_day)
                          ? 'Today'
                          : DateFormat('EEEE').format(_day),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    Text(fmtDate(_day),
                        style: const TextStyle(
                            fontSize: 12.5, color: AppTheme.muted)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_isToday(_day))
                      TextButton(
                        onPressed: () => setState(() => _day = _todayPkt()),
                        child: const Text('Today'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _isToday(_day) ? null : () => _shiftDay(1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Attendance is recorded automatically via office WiFi, '
              'or marked manually from the attendance app (Manual '
              'badge). Working hours run from the first WiFi entry '
              'to the last WiFi exit of the day. Only the admin can '
              'correct a record, with the Edit and Delete buttons. '
              'All times are Pakistan time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(attendanceMonthProvider(_month));
                ref.invalidate(profileNamesProvider);
              },
              child: sessionsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  const SizedBox(height: 120),
                  Center(
                      child: Text('Could not load attendance.\n$e',
                          textAlign: TextAlign.center)),
                ]),
                data: (sessions) {
                  // This day's sessions, grouped per employee.
                  final daySessions = sessions.where((s) {
                    final p = pkt(s.entryAt);
                    return p.year == _day.year &&
                        p.month == _day.month &&
                        p.day == _day.day;
                  }).toList();
                  if (daySessions.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 120),
                      Center(
                          child:
                              Text('No attendance recorded for this day.')),
                    ]);
                  }
                  final byUser = <String, List<AttendanceSession>>{};
                  for (final s in daySessions) {
                    byUser.putIfAbsent(s.userId, () => []).add(s);
                  }
                  final monthByUser = <String, List<AttendanceSession>>{};
                  for (final s in sessions) {
                    monthByUser.putIfAbsent(s.userId, () => []).add(s);
                  }
                  final userIds = byUser.keys.toList()
                    ..sort(
                        (a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: userIds.length,
                    itemBuilder: (context, i) {
                      final uid = userIds[i];
                      final list = byUser[uid]!
                        ..sort((a, b) => a.entryAt.compareTo(b.entryAt));
                      final daySum = _DaySummary(day: _day, sessions: list);
                      final open = daySum.anyOpen;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ---- employee header ----
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 6),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppTheme.primary,
                                    child: Icon(Icons.person,
                                        size: 18, color: Colors.white),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      uid == myId
                                          ? '${names[uid] ?? 'Me'} '
                                              '(${isAdmin ? 'Admin' : 'Me'})'
                                          : (names[uid] ?? 'User'),
                                      style: const TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (open)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.income
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Text('In office',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.income,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Day ${_fmtDur(daySum.total)} · '
                                    'Month ${_fmtDur(_monthTotal(monthByUser[uid]!))}',
                                    style: const TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            // ---- one row per session ----
                            ...list.map(
                                (s) => _sessionRow(s, daySum, isAdmin)),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionRow(
      AttendanceSession s, _DaySummary daySum, bool isAdmin) {
    final eff = daySum.effExit(s);
    final isOpenNow = eff == null;
    final autoClosed = s.isOpen && eff != null;
    final dur = (eff ?? DateTime.now()).difference(s.entryAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(
            s.isManual ? Icons.touch_app : Icons.wifi,
            size: 19,
            color: isOpenNow ? AppTheme.income : AppTheme.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_time.format(pkt(s.entryAt))}  →  '
              '${isOpenNow ? 'still in office' : _time.format(pkt(eff))}'
              '${autoClosed ? ' (auto)' : ''}',
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: s.isManual
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              s.isManual ? 'Manual' : 'WiFi',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: s.isManual
                      ? const Color(0xFFE65100)
                      : const Color(0xFF1565C0)),
            ),
          ),
          const SizedBox(width: 10),
          Text(_fmtDur(dur.isNegative ? Duration.zero : dur),
              style: const TextStyle(
                  color: AppTheme.muted, fontWeight: FontWeight.w600)),
          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 19),
              color: AppTheme.primary,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: () => _editSession(s),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 19),
              color: Colors.redAccent,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteSession(s),
            ),
          ],
        ],
      ),
    );
  }

  Duration _monthTotal(List<AttendanceSession> sessions) {
    final byDay = <DateTime, List<AttendanceSession>>{};
    for (final s in sessions) {
      final p = pkt(s.entryAt);
      final day = DateTime(p.year, p.month, p.day);
      byDay.putIfAbsent(day, () => []).add(s);
    }
    var total = Duration.zero;
    for (final e in byDay.entries) {
      final list = e.value..sort((a, b) => a.entryAt.compareTo(b.entryAt));
      total += _DaySummary(day: e.key, sessions: list).total;
    }
    return total;
  }
}

class _DaySummary {
  final DateTime day;
  final List<AttendanceSession> sessions;
  _DaySummary({required this.day, required this.sessions});

  List<AttendanceSession> get wifiSessions =>
      sessions.where((s) => !s.isManual).toList();

  /// The track whose span counts as working hours: the WiFi track
  /// whenever the day has any WiFi sessions (Talal's rule,
  /// 2026-10-21) — manual entries never stretch the day. A
  /// manual-only day falls back to the manual span.
  List<AttendanceSession> get track =>
      wifiSessions.isNotEmpty ? wifiSessions : sessions;

  DateTime get trackFirst => track.first.entryAt;

  /// A session's effective exit, for display and totals. Its
  /// real exit wins. A MANUAL session is never closed by a
  /// WiFi exit — it ends only by its own Mark exit (Talal
  /// reversed the 2026-10-21 rule on 2026-10-22).
  DateTime? effExit(AttendanceSession s) {
    if (s.exitAt != null) return s.exitAt;
    // A session still open from a PREVIOUS (PKT) day: the
    // exit was missed (detector off/dead), so the day counts
    // as closed at midnight — the same boundary the detector
    // writes in the database (Talal, 2026-10-22). Today's
    // open sessions stay genuinely open.
    final ep = pkt(s.entryAt);
    final np = pkt(DateTime.now());
    if (DateTime(ep.year, ep.month, ep.day)
        .isBefore(DateTime(np.year, np.month, np.day))) {
      return DateTime.utc(ep.year, ep.month, ep.day + 1)
          .subtract(const Duration(hours: 5));
    }
    return null;
  }

  bool get anyOpen => sessions.any((s) => effExit(s) == null);

  /// Working hours: the counting track's span — first entry to
  /// last exit, beech ka waqt bhi shamil (Talal ka rule,
  /// 2026-10-20/21).
  Duration get total {
    final first = trackFirst;
    final end = track.any((s) => effExit(s) == null)
        ? DateTime.now()
        : track
            .map((s) => effExit(s)!)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final dur = end.difference(first);
    return dur.isNegative ? Duration.zero : dur;
  }
}
