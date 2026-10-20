import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos.dart';

/// Monthly attendance list (migration v7).
///
/// Attendance auto-record hoti hai jab employee ka phone office WiFi se
/// connect/disconnect hota hai. Yahan sirf DISPLAY hai — koi edit/delete
/// nahi. Employee ko sirf apni, admin ko sab ki attendance dikhti hai
/// (ye farq Supabase RLS se enforce hota hai).
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime _month = firstOfMonth(DateTime.now());

  static final _time = DateFormat('hh:mm a');

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(attendanceMonthProvider(_month));
    final namesAsync = ref.watch(profileNamesProvider);
    final profile = ref.watch(profileProvider);
    final isAdmin = profile.whenData((p) => p?.isAdmin ?? false).value ?? false;
    final myId = profile.whenData((p) => p?.id).value;
    final names = namesAsync.value ?? const <String, String>{};

    final now = DateTime.now();
    final canGoNext =
        _month.year < now.year || (_month.year == now.year && _month.month < now.month);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: Column(
        children: [
          // ---- month selector ----
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() =>
                      _month = DateTime(_month.year, _month.month - 1, 1)),
                ),
                Text(fmtMonth(_month),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: canGoNext
                      ? () => setState(() =>
                          _month = DateTime(_month.year, _month.month + 1, 1))
                      : null,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Attendance office WiFi se auto lagti hai. '
              'Record edit ya delete nahi hota.',
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
                      child: Text('Attendance load nahi ho saki.\n$e',
                          textAlign: TextAlign.center)),
                ]),
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 120),
                      Center(
                          child: Text('Is month mein koi attendance nahi.')),
                    ]);
                  }
                  // Group: user -> day -> sessions
                  final byUser = <String, List<AttendanceSession>>{};
                  for (final s in sessions) {
                    byUser.putIfAbsent(s.userId, () => []).add(s);
                  }
                  final userIds = byUser.keys.toList()
                    ..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: userIds.length,
                    itemBuilder: (context, i) {
                      final uid = userIds[i];
                      final userSessions = byUser[uid]!;
                      final days = _groupByDay(userSessions);
                      // Working hours = first entry se last exit tak (span),
                      // Talal ka rule 2026-10-20. Month total = dinon ke
                      // spans ka jor.
                      final monthTotal = days.fold<Duration>(
                          Duration.zero, (sum, d) => sum + d.total);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isAdmin || userIds.length > 1)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 6),
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
                                          ? '${names[uid] ?? 'Mein'} (Mein)'
                                          : (names[uid] ?? 'User'),
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text('Total: ${_fmtDur(monthTotal)}',
                                      style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ...days.map((d) => _dayTile(d)),
                        ],
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

  List<_DaySummary> _groupByDay(List<AttendanceSession> sessions) {
    final byDay = <DateTime, List<AttendanceSession>>{};
    for (final s in sessions) {
      final day = DateTime(s.entryAt.year, s.entryAt.month, s.entryAt.day);
      byDay.putIfAbsent(day, () => []).add(s);
    }
    final days = byDay.entries.map((e) {
      final list = e.value..sort((a, b) => a.entryAt.compareTo(b.entryAt));
      return _DaySummary(day: e.key, sessions: list);
    }).toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return days;
  }

  Widget _dayTile(_DaySummary d) {
    final firstIn = d.sessions.first.entryAt;
    final open = d.sessions.any((s) => s.isOpen);
    final lastOut = open
        ? null
        : d.sessions
            .map((s) => s.exitAt!)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        title: Row(
          children: [
            Expanded(
              child: Text(fmtDate(d.day),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (open)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.income.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Office mein hai',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.income,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        subtitle: Text(
          'In ${_time.format(firstIn)}'
          '${lastOut != null ? '  •  Out ${_time.format(lastOut)}' : ''}'
          '  •  ${_fmtDur(d.total)}'
          '${d.sessions.length > 1 ? '  •  ${d.sessions.length} sessions' : ''}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
        ),
        children: d.sessions
            .map(
              (s) => ListTile(
                dense: true,
                leading: Icon(
                  s.isOpen ? Icons.login : Icons.logout,
                  size: 18,
                  color: s.isOpen ? AppTheme.income : AppTheme.muted,
                ),
                title: Text(
                  '${_time.format(s.entryAt)}  →  '
                  '${s.isOpen ? 'abhi tak' : _time.format(s.exitAt!)}',
                  style: const TextStyle(fontSize: 13.5),
                ),
                trailing: Text(_fmtDur(s.duration),
                    style: const TextStyle(
                        color: AppTheme.muted, fontWeight: FontWeight.w600)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DaySummary {
  final DateTime day;
  final List<AttendanceSession> sessions;
  _DaySummary({required this.day, required this.sessions});

  /// Working hours: pehli entry se akhri exit tak ka span — beech mein
  /// employee kitni baar bhi bahir jaye, wo time bhi count hota hai
  /// (Talal ka rule, 2026-10-20). Sessions ki tafseel alag dikhti hai.
  Duration get total {
    final first = sessions.first.entryAt;
    final end = sessions.any((s) => s.isOpen)
        ? DateTime.now()
        : sessions
            .map((s) => s.exitAt!)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    return end.difference(first);
  }
}
