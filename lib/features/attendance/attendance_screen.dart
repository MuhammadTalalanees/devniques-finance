import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

/// Attendance — calendar + monthly view (Talal, 2026-10-23).
///
/// Upar ek calendar hai: month wahin se badalta hai, kisi date
/// par tap karo to sirf us din ki attendance dikhti hai
/// (dobara tap / All month se pura month wapas). Neeche mahine
/// ki attendance dates ke hisaab se aati hai — har date par
/// sab employees alag alag columns mein (PC par 4 columns).
/// Details band rehti hain: employee par tap karne se us ki
/// sessions khulti hain, aur admin wahin se Edit/Delete kar
/// sakta hai (attendance correction, migration v15). Working
/// hours ka rule wahi purana: pehli WiFi entry se aakhri WiFi
/// exit tak ka span. Saare times Pakistan time mein.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

/// An instant re-framed as Pakistan wall time (UTC+5, no DST):
/// its fields read as the PKT clock.
DateTime pkt(DateTime t) => t.toUtc().add(const Duration(hours: 5));

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime _month = firstOfMonth(pkt(DateTime.now()));
  DateTime? _selectedDay;
  final Set<String> _openCells = {};

  static final _time = DateFormat('hh:mm a');

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static DateTime _todayPkt() {
    final n = pkt(DateTime.now());
    return DateTime(n.year, n.month, n.day);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  // ---------------- calendar ----------------

  Widget _calendar(Set<DateTime> daysWithData) {
    final first = _month;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final leadBlanks = first.weekday - 1; // Monday first
    final today = _todayPkt();
    final canNext = first.year < today.year ||
        (first.year == today.year && first.month < today.month);
    const weekDays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                    _month = DateTime(first.year, first.month - 1, 1);
                    _selectedDay = null;
                  }),
                ),
                Text(fmtMonth(first),
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedDay != null)
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedDay = null),
                        child: const Text('All month'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: canNext
                          ? () => setState(() {
                                _month =
                                    DateTime(first.year, first.month + 1, 1);
                                _selectedDay = null;
                              })
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            Row(
              children: weekDays
                  .map((w) => Expanded(
                        child: Center(
                          child: Text(w,
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.muted)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 34,
              ),
              itemCount: leadBlanks + daysInMonth,
              itemBuilder: (_, i) {
                if (i < leadBlanks) return const SizedBox.shrink();
                final dayNum = i - leadBlanks + 1;
                final date = DateTime(first.year, first.month, dayNum);
                final isToday = _sameDay(date, today);
                final isSel =
                    _selectedDay != null && _sameDay(date, _selectedDay!);
                final hasData = daysWithData.any((d) => _sameDay(d, date));
                return InkWell(
                  onTap: () => setState(() =>
                      _selectedDay = isSel ? null : date),
                  borderRadius: BorderRadius.circular(17),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSel ? AppTheme.primary : null,
                      border: isToday && !isSel
                          ? Border.all(color: AppTheme.primary, width: 1.4)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$dayNum',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  isSel || isToday ? FontWeight.w700 : null,
                              color: isSel ? Colors.white : null,
                            )),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasData
                                ? (isSel ? Colors.white : AppTheme.income)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- month body ----------------

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(attendanceMonthProvider(_month));
    final namesAsync = ref.watch(profileNamesProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin = profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final names = namesAsync.value ?? const <String, String>{};
    final sessions = sessionsAsync.value ?? const <AttendanceSession>[];

    final daysWithData = <DateTime>{};
    for (final s in sessions) {
      final p = pkt(s.entryAt);
      daysWithData.add(DateTime(p.year, p.month, p.day));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Human Resources (HR)')),
      body: Column(
        children: [
          _calendar(daysWithData),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Tap a date to see only that day. Tap an employee to '
              'open the details. Only the admin can correct a '
              'record (Edit / Delete). All times are Pakistan time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
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
                data: (_) => _monthList(sessions, names, isAdmin),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthList(List<AttendanceSession> sessions,
      Map<String, String> names, bool isAdmin) {
    // Group: day -> user -> sessions (month from the provider,
    // optionally narrowed to the calendar's selected day).
    final byDay = <DateTime, Map<String, List<AttendanceSession>>>{};
    for (final s in sessions) {
      final p = pkt(s.entryAt);
      final day = DateTime(p.year, p.month, p.day);
      if (_selectedDay != null && !_sameDay(day, _selectedDay!)) {
        continue;
      }
      byDay
          .putIfAbsent(day, () => {})
          .putIfAbsent(s.userId, () => [])
          .add(s);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    if (days.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 100),
        Center(child: Text('No attendance recorded.')),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final byUser = byDay[day]!;
        final userIds = byUser.keys.toList()
          ..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                '${DateFormat('EEEE, ').format(day)}${fmtDate(day)}',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final cols = w >= 1050 ? 4 : (w >= 640 ? 2 : 1);
                final cellW = (w - 24 - (cols - 1) * 10) / cols;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: userIds
                        .map((uid) => SizedBox(
                              width: cellW,
                              child: _employeeCell(
                                day,
                                uid,
                                names[uid] ?? 'User',
                                byUser[uid]!,
                                isAdmin,
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _employeeCell(DateTime day, String uid, String name,
      List<AttendanceSession> list, bool isAdmin) {
    final sorted = [...list]..sort((a, b) => a.entryAt.compareTo(b.entryAt));
    final sum = _DaySummary(day: day, sessions: sorted);
    final key = '${day.toIso8601String()}|$uid';
    final open = _openCells.contains(key);
    final firstIn = sum.trackFirst;
    final lastOut = sum.trackOpen ? null : sum.trackLastExit;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(
                () => open ? _openCells.remove(key) : _openCells.add(key)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: AppTheme.primary,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (sum.trackOpen)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.income.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('In office',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.income,
                                        fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_time.format(pkt(firstIn))} → '
                          '${lastOut != null ? _time.format(pkt(lastOut)) : 'still in'}'
                          '  ·  ${_fmtDur(sum.total)}',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      color: AppTheme.muted, size: 20),
                ],
              ),
            ),
          ),
          if (open) ...[
            const Divider(height: 1),
            ...sorted.map((s) => _sessionRow(s, sum, isAdmin)),
            const SizedBox(height: 4),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Icon(
            s.isManual ? Icons.touch_app : Icons.wifi,
            size: 16,
            color: isOpenNow ? AppTheme.income : AppTheme.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_time.format(pkt(s.entryAt))} → '
              '${isOpenNow ? 'still in' : _time.format(pkt(eff))}'
              '${autoClosed ? ' (auto)' : ''}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: s.isManual
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              s.isManual ? 'Manual' : 'WiFi',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: s.isManual
                      ? const Color(0xFFE65100)
                      : const Color(0xFF1565C0)),
            ),
          ),
          const SizedBox(width: 7),
          Text(_fmtDur(dur.isNegative ? Duration.zero : dur),
              style: const TextStyle(
                  color: AppTheme.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
          if (isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit, size: 17),
              color: AppTheme.primary,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _editSession(s),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 17),
              color: Colors.redAccent,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _deleteSession(s),
            ),
          ],
        ],
      ),
    );
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

  /// "In office" comes ONLY from the WiFi track (Talal's final
  /// model) — an open MANUAL session never makes the day look
  /// still-in. The header span end is the WiFi track's too.
  bool get trackOpen => track.any((s) => effExit(s) == null);

  DateTime? get trackLastExit {
    DateTime? last;
    for (final s in track) {
      final e = effExit(s);
      if (e != null && (last == null || e.isAfter(last))) last = e;
    }
    return last;
  }

  DateTime? get lastEffExit {
    DateTime? last;
    for (final s in sessions) {
      final e = effExit(s);
      if (e != null && (last == null || e.isAfter(last))) last = e;
    }
    return last;
  }

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
