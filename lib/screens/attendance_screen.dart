import 'package:flutter/material.dart';
import 'timetable_screen.dart';

// ─────────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────────

class Subject {
  String name;
  int attended;
  int missed;
  int off;
  int criteria; // e.g. 75

  Subject({
    required this.name,
    this.attended = 0,
    this.missed = 0,
    this.off = 0,
    this.criteria = 75,
  });

  int get total => attended + missed;

  double get percentage =>
      total == 0 ? 0 : (attended / total * 100);

  // How many consecutive lectures to attend to reach criteria
  int get lecturesNeeded {
    if (percentage >= criteria) return 0;
    // attended + x / (total + x) >= criteria/100
    // => x >= (criteria * total - 100 * attended) / (100 - criteria)
    if (criteria >= 100) return -1; // impossible
    double x = (criteria / 100 * total - attended) / (1 - criteria / 100);
    return x <= 0 ? 0 : x.ceil();
  }

  // How many can be skipped while staying above criteria
  int get canSkip {
    if (percentage < criteria) return 0;
    // attended / (total + x) >= criteria/100
    // => x <= (100 * attended / criteria) - total
    if (criteria == 0) return 9999;
    double x = (attended * 100 / criteria) - total;
    return x <= 0 ? 0 : x.floor();
  }

  String get statusMessage {
    if (percentage >= 100) return "can't miss the next lecture";
    if (lecturesNeeded > 0) return "need to attend $lecturesNeeded lectures";
    if (canSkip > 0) return "can skip $canSkip lectures";
    return "can't miss the next lecture";
  }

  Color statusColor(BuildContext context) {
    if (percentage >= criteria) return Colors.green.shade600;
    return Colors.red.shade400;
  }
}

// Day log: each day can have per-subject attendance marks
enum AttendanceMark { notMarked, off, missed, attended, mixed }

class DayLog {
  final DateTime date;
  Map<String, AttendanceMark> subjectMarks; // subjectName -> mark

  DayLog({required this.date, Map<String, AttendanceMark>? subjectMarks})
      : subjectMarks = subjectMarks ?? {};

  AttendanceMark get dayStatus {
    if (subjectMarks.isEmpty) return AttendanceMark.notMarked;
    final vals = subjectMarks.values.toSet();
    if (vals.length == 1) return vals.first;
    return AttendanceMark.mixed;
  }
}

// ─────────────────────────────────────────────
//  MAIN SCREEN
// ─────────────────────────────────────────────

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int _currentTab = 0; // 0=Today,1=Timetable,2=Calendar,3=Subjects,4=Settings

  // Global criteria
  int _criteria = 75;

  // Subjects list
  List<Subject> _subjects = [
    Subject(name: 'DEL', attended: 2, missed: 0, off: 1, criteria: 75),
    Subject(name: 'Devops', attended: 3, missed: 2, off: 3, criteria: 75),
    Subject(name: 'ICS', attended: 2, missed: 1, off: 1, criteria: 75),
    Subject(name: 'CC', attended: 1, missed: 2, off: 0, criteria: 75),
    Subject(name: 'CCL', attended: 1, missed: 0, off: 1, criteria: 75),
    Subject(name: 'DE', attended: 0, missed: 3, off: 3, criteria: 75),
    Subject(name: 'EBI', attended: 1, missed: 2, off: 2, criteria: 75),
    Subject(name: 'FSD', attended: 1, missed: 2, off: 4, criteria: 75),
    Subject(name: 'PSDL', attended: 4, missed: 0, off: 1, criteria: 75),
    Subject(name: 'FSDL', attended: 3, missed: 0, off: 0, criteria: 75),
  ];

  // Day logs map: "yyyy-MM-dd" -> DayLog
  final Map<String, DayLog> _dayLogs = {};

  DateTime _calendarMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  // Timetable: weekday (1=Mon..7=Sun) -> list of subject names per slot
  final Map<int, List<String>> _timetable = {
    1: ['PSDL', 'Devops', 'DE', 'ICS', 'CC'],
    2: ['EBI', 'CC', 'FSD', 'ICS', 'FSDL'],
    3: ['DEL', 'Devops', 'ICS', 'CC', 'DE'],
    4: ['FSD', 'EBI', 'CCL', '', ''],
    5: ['Devops', 'DE', 'PSDL', 'FSD', ''],
    6: [],
    7: [],
  };

  // ── helpers ──────────────────────────────────

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DayLog _getOrCreateLog(DateTime date) {
    final key = _dateKey(date);
    return _dayLogs.putIfAbsent(key, () => DayLog(date: date));
  }

  Subject? _findSubject(String name) {
    try {
      return _subjects.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }

  double get _overallPercentage {
    int att = _subjects.fold(0, (s, e) => s + e.attended);
    int tot = _subjects.fold(0, (s, e) => s + e.total);
    if (tot == 0) return 0;
    return att / tot * 100;
  }

  int get _overallLecturesNeeded {
    int att = _subjects.fold(0, (s, e) => s + e.attended);
    int tot = _subjects.fold(0, (s, e) => s + e.total);
    int off = _subjects.fold(0, (s, e) => s + e.off);
    if (_criteria >= 100) return -1;
    double x = (_criteria / 100 * tot - att) / (1 - _criteria / 100);
    return x <= 0 ? 0 : x.ceil();
  }

  void _markSubjectToday(Subject subject, AttendanceMark mark) {
    setState(() {
      final log = _getOrCreateLog(_selectedDate);
      final prev = log.subjectMarks[subject.name];

      // Undo previous mark on subject stats
      if (prev == AttendanceMark.attended) subject.attended--;
      if (prev == AttendanceMark.missed) subject.missed--;
      if (prev == AttendanceMark.off) subject.off--;

      if (prev == mark) {
        // toggle off
        log.subjectMarks.remove(subject.name);
      } else {
        log.subjectMarks[subject.name] = mark;
        if (mark == AttendanceMark.attended) subject.attended++;
        if (mark == AttendanceMark.missed) subject.missed++;
        if (mark == AttendanceMark.off) subject.off++;
      }
    });
  }

  void _markAllToday(AttendanceMark mark) {
    setState(() {
      final todaySubjects = _timetable[_selectedDate.weekday] ?? [];
      for (final name in todaySubjects.where((n) => n.isNotEmpty)) {
        final sub = _findSubject(name);
        if (sub != null) _markSubjectToday(sub, mark);
      }
    });
  }

  // ── UI helpers ────────────────────────────────

  Color _dotColor(AttendanceMark m) {
    switch (m) {
      case AttendanceMark.attended:
        return Colors.green;
      case AttendanceMark.missed:
        return Colors.red;
      case AttendanceMark.off:
        return Colors.orange;
      case AttendanceMark.mixed:
        return Colors.purple;
      case AttendanceMark.notMarked:
        return Colors.grey.shade400;
    }
  }

  // ── BUILD ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    String title = '';
    Widget? trailing;

    switch (_currentTab) {
      case 0:
        title =
        'Wed, ${_selectedDate.day} ${_monthName(_selectedDate.month)} ${_selectedDate.year}';
        trailing = IconButton(
          icon: const Icon(Icons.add),
          onPressed: _showAddSubjectDialog,
        );
        break;
      case 1:
        title = 'Timetable';
        break;
      case 2:
        title = 'Calendar';
        break;
      case 3:
        title = 'Subjects';
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.add), onPressed: _showAddSubjectDialog),
            IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
          ],
        );
        break;
      case 4:
        title = 'Settings';
        trailing = TextButton(
          onPressed: () {},
          child: const Text('REMOVE ADS', style: TextStyle(fontSize: 12)),
        );
        break;
    }

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: _currentTab != 0
          ? null
          : null,
      title: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
        ],
      ),
      actions: [
        // percentage badge
        if (_currentTab != 4)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_overallPercentage.toStringAsFixed(2)} | $_criteria',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case 0:
        return _buildTodayTab();
      case 1:
      // Navigate to timetable_screen.dart
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TimetableScreen()),
          ).then((_) => setState(() => _currentTab = 0));
        });
        return const SizedBox.shrink();
      case 2:
        return _buildCalendarTab();
      case 3:
        return _buildSubjectsTab();
      case 4:
        return _buildSettingsTab();
      default:
        return _buildTodayTab();
    }
  }

  // ─────────────────────────────────────────────
  //  TODAY TAB
  // ─────────────────────────────────────────────

  Widget _buildTodayTab() {
    final log = _getOrCreateLog(_selectedDate);
    final todaySubjectNames =
    (_timetable[_selectedDate.weekday] ?? []).where((n) => n.isNotEmpty).toList();
    final todaySubjects =
    todaySubjectNames.map((n) => _findSubject(n)).whereType<Subject>().toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Day status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.teal.shade600,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Day status:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('Not marked',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
              _dayActionBtn(Icons.block, 'Clear', () => _markAllToday(AttendanceMark.notMarked)),
              const SizedBox(width: 6),
              _dayActionBtn(Icons.remove_circle_outline, 'Off',
                      () => _markAllToday(AttendanceMark.off)),
              const SizedBox(width: 6),
              _dayActionBtn(Icons.close, 'Miss', () => _markAllToday(AttendanceMark.missed)),
              const SizedBox(width: 6),
              _dayActionBtn(Icons.check, 'Att', () => _markAllToday(AttendanceMark.attended),
                  active: true),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (todaySubjects.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No classes today', style: TextStyle(color: Colors.grey))),
          ),
        ...todaySubjects.map((sub) {
          final mark = log.subjectMarks[sub.name] ?? AttendanceMark.notMarked;
          return _subjectTodayCard(sub, mark);
        }),
      ],
    );
  }

  Widget _dayActionBtn(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.green : Colors.black26,
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _subjectTodayCard(Subject sub, AttendanceMark currentMark) {
    Color pColor = sub.percentage >= sub.criteria ? Colors.green.shade600 : Colors.red.shade400;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                _percentBadge(sub.percentage, sub.criteria, pColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sub.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(sub.statusMessage,
                          style: TextStyle(color: pColor, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _markBtn(Icons.block, AttendanceMark.notMarked, currentMark, sub),
                const SizedBox(width: 12),
                _markBtn(Icons.remove_circle_outline, AttendanceMark.off, currentMark, sub),
                const SizedBox(width: 12),
                _markBtn(Icons.close, AttendanceMark.missed, currentMark, sub),
                const SizedBox(width: 12),
                _markBtn(Icons.check, AttendanceMark.attended, currentMark, sub),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _markBtn(IconData icon, AttendanceMark mark, AttendanceMark current, Subject sub) {
    bool isActive = current == mark;
    Color color;
    switch (mark) {
      case AttendanceMark.attended:
        color = Colors.green;
        break;
      case AttendanceMark.missed:
        color = Colors.red;
        break;
      case AttendanceMark.off:
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }
    return GestureDetector(
      onTap: () => _markSubjectToday(sub, mark),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? color : Colors.transparent,
          border: Border.all(color: isActive ? color : Colors.grey.shade300),
        ),
        child: Icon(icon, size: 16, color: isActive ? Colors.white : Colors.grey.shade400),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  CALENDAR TAB
  // ─────────────────────────────────────────────

  Widget _buildCalendarTab() {
    final now = DateTime.now();
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    // offset: 0=Mon
    int startWeekday = firstDay.weekday - 1; // 0=Mon

    // Stats for this month
    int notMarked = 0, off = 0, missed = 0, attended = 0, mixed = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_calendarMonth.year, _calendarMonth.month, d);
      final key = _dateKey(date);
      final log = _dayLogs[key];
      if (log == null || log.subjectMarks.isEmpty) {
        notMarked++;
      } else {
        switch (log.dayStatus) {
          case AttendanceMark.attended:
            attended++;
            break;
          case AttendanceMark.missed:
            missed++;
            break;
          case AttendanceMark.off:
            off++;
            break;
          case AttendanceMark.mixed:
            mixed++;
            break;
          default:
            notMarked++;
        }
      }
    }

    // Global totals across all subjects
    int totalAtt = _subjects.fold(0, (s, e) => s + e.attended);
    int totalMiss = _subjects.fold(0, (s, e) => s + e.missed);
    int totalOff = _subjects.fold(0, (s, e) => s + e.off);
    int totalTot = _subjects.fold(0, (s, e) => s + e.total);

    return SingleChildScrollView(
      child: Column(
        children: [
          // Month header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _calendarMonth =
                        DateTime(_calendarMonth.year, _calendarMonth.month - 1))),
                Text(
                  '${_monthName(_calendarMonth.month)} ${_calendarMonth.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _calendarMonth =
                        DateTime(_calendarMonth.year, _calendarMonth.month + 1))),
              ],
            ),
          ),
          // Weekday headers
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                  .map((d) => Expanded(
                child: Center(
                    child: Text(d,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600))),
              ))
                  .toList(),
            ),
          ),
          // Grid
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 0.9),
              itemCount: startWeekday + daysInMonth,
              itemBuilder: (ctx, i) {
                if (i < startWeekday) return const SizedBox();
                final day = i - startWeekday + 1;
                final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
                final key = _dateKey(date);
                final log = _dayLogs[key];
                AttendanceMark mark = AttendanceMark.notMarked;
                if (log != null && log.subjectMarks.isNotEmpty) mark = log.dayStatus;
                bool isToday = date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
                bool isSelected = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedDate = date;
                    _currentTab = 0;
                  }),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: isToday
                              ? Border.all(color: Colors.teal.shade400, width: 2)
                              : null,
                          color: isSelected && !isToday ? Colors.teal.shade100 : null,
                        ),
                        child: Center(
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontWeight:
                              isToday ? FontWeight.bold : FontWeight.normal,
                              color: isToday ? Colors.teal.shade700 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _dotColor(mark),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Day summary
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _calStat('$notMarked', 'Not marked', Colors.grey.shade400),
                      _calStat('$off', 'Off', Colors.orange),
                      _calStat('$missed', 'Missed', Colors.red),
                      _calStat('$attended', 'Attended', Colors.green),
                      _calStat('$mixed', 'Mixed', Colors.purple),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade700,
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10)),
                  ),
                  child: const Center(
                    child: Text('Days', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Lecture totals
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _calStat('$totalOff', 'Off', Colors.grey),
                _calStat('$totalMiss', 'Missed', Colors.grey),
                _calStat('$totalAtt', 'Attended', Colors.grey),
                _calStat('$totalTot', 'Total', Colors.grey),
                _calStat('${_overallPercentage.toStringAsFixed(2)}%', 'Percent', Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _calStat(String value, String label, Color dotColor) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
            ),
            const SizedBox(width: 4),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  SUBJECTS TAB
  // ─────────────────────────────────────────────

  Widget _buildSubjectsTab() {
    int totalAtt = _subjects.fold(0, (s, e) => s + e.attended);
    int totalMiss = _subjects.fold(0, (s, e) => s + e.missed);
    int totalOff = _subjects.fold(0, (s, e) => s + e.off);
    int totalTot = _subjects.fold(0, (s, e) => s + e.total);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Overall card
        _subjectListCard(
          name: 'Overall',
          percentage: _overallPercentage,
          criteria: _criteria,
          statusMsg: _overallLecturesNeeded > 0
              ? 'need to attend $_overallLecturesNeeded lectures'
              : 'on track',
          att: totalAtt,
          miss: totalMiss,
          off: totalOff,
          tot: totalTot,
          onTap: () {},
        ),
        ..._subjects.map((sub) => _subjectListCard(
          name: sub.name,
          percentage: sub.percentage,
          criteria: sub.criteria,
          statusMsg: sub.statusMessage,
          att: sub.attended,
          miss: sub.missed,
          off: sub.off,
          tot: sub.total,
          onTap: () => _showSubjectDetail(sub),
        )),
      ],
    );
  }

  Widget _subjectListCard({
    required String name,
    required double percentage,
    required int criteria,
    required String statusMsg,
    required int att,
    required int miss,
    required int off,
    required int tot,
    required VoidCallback onTap,
  }) {
    final bool isGood = percentage >= criteria;
    final Color pColor = isGood ? Colors.green.shade600 : Colors.red.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
          border: Border(left: BorderSide(color: pColor, width: 4)),
        ),
        child: Row(
          children: [
            _percentBadge(percentage, criteria, pColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(statusMsg, style: TextStyle(color: pColor, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    'Att: $att  Miss: $miss  Off: $off  Tot: $tot',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _percentBadge(double pct, int criteria, Color color) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(pct.toStringAsFixed(2),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          Container(height: 1, color: color.withOpacity(0.4), width: 40),
          Text('$criteria',
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  SETTINGS TAB
  // ─────────────────────────────────────────────

  Widget _buildSettingsTab() {
    return ListView(
      children: [
        _settingSection('General'),
        _settingTile(
          icon: Icons.track_changes,
          title: 'Set criteria',
          subtitle: '$_criteria%',
          onTap: _showCriteriaDialog,
        ),
        _settingTile(
          icon: Icons.brightness_medium,
          title: 'Set theme',
          subtitle: 'System Default, using App colors',
          onTap: () {},
        ),
        _settingSection('Database'),
        _settingTile(
          icon: Icons.import_export,
          title: 'Backup/Restore',
          subtitle: 'Avoid losing your data. Set up automatic backups or use manual export and import.',
          onTap: () {},
        ),
        _settingTile(
          icon: Icons.description,
          title: 'Export data as CSV',
          subtitle:
          'Generates a ZIP archive of CSV files readable by spreadsheet apps. These files cannot be imported back.',
          onTap: () {},
        ),
        _settingSection('App'),
        _settingTile(icon: Icons.star, title: 'Upgrade to Premium', onTap: () {}),
        _settingTile(icon: Icons.share, title: 'Share App', onTap: () {}),
        _settingTile(
            icon: Icons.grade, title: 'Rate this app on Google Play', onTap: () {}),
        _settingTile(
          icon: Icons.people,
          title: 'Contact us',
          subtitle: 'Suggestions, bugs, questions',
          onTap: () {},
        ),
        _settingTile(icon: Icons.info_outline, title: 'App info', onTap: () {}),
      ],
    );
  }

  Widget _settingSection(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(title,
        style: TextStyle(
            color: Colors.teal.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 13)),
  );

  Widget _settingTile(
      {required IconData icon,
        required String title,
        String? subtitle,
        required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade600),
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
          : null,
      onTap: onTap,
      tileColor: Colors.white,
    );
  }

  // ─────────────────────────────────────────────
  //  BOTTOM NAV
  // ─────────────────────────────────────────────

  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.view_day_outlined, 'label': 'Today'},
      {'icon': Icons.view_column_outlined, 'label': 'Timetable'},
      {'icon': Icons.calendar_month, 'label': 'Calendar'},
      {'icon': Icons.list_alt, 'label': 'Subjects'},
      {'icon': Icons.settings_outlined, 'label': 'Settings'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = _currentTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (i == 1) {
                  // Go to timetable_screen.dart directly
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TimetableScreen()),
                  );
                } else {
                  setState(() => _currentTab = i);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (active)
                      Container(
                        width: 36,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.teal.shade600,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(items[i]['icon'] as IconData,
                            color: Colors.white, size: 18),
                      )
                    else
                      Icon(items[i]['icon'] as IconData,
                          color: Colors.grey.shade500, size: 22),
                    const SizedBox(height: 2),
                    Text(
                      items[i]['label'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        color: active ? Colors.teal.shade700 : Colors.grey.shade500,
                        fontWeight:
                        active ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  DIALOGS
  // ─────────────────────────────────────────────

  void _showCriteriaDialog() {
    int tempCriteria = _criteria;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Criteria'),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$tempCriteria%',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Slider(
                value: tempCriteria.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                activeColor: Colors.teal,
                onChanged: (v) => setS(() => tempCriteria = v.round()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() {
                _criteria = tempCriteria;
                for (final s in _subjects) {
                  s.criteria = tempCriteria;
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddSubjectDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Subject'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Subject name'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => _subjects.add(
                    Subject(name: ctrl.text.trim().toUpperCase(), criteria: _criteria)));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showSubjectDetail(Subject sub) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sub.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _editStatBtn('Att', sub.attended, Colors.green, () {
                    setS(() => sub.attended++);
                    setState(() {});
                  }, () {
                    if (sub.attended > 0) setS(() => sub.attended--);
                    setState(() {});
                  }),
                  _editStatBtn('Miss', sub.missed, Colors.red, () {
                    setS(() => sub.missed++);
                    setState(() {});
                  }, () {
                    if (sub.missed > 0) setS(() => sub.missed--);
                    setState(() {});
                  }),
                  _editStatBtn('Off', sub.off, Colors.orange, () {
                    setS(() => sub.off++);
                    setState(() {});
                  }, () {
                    if (sub.off > 0) setS(() => sub.off--);
                    setState(() {});
                  }),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${sub.percentage.toStringAsFixed(2)}%  |  ${sub.statusMessage}',
                style: TextStyle(
                    color:
                    sub.percentage >= sub.criteria ? Colors.green : Colors.red),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _subjects.remove(sub));
                      Navigator.pop(ctx);
                    },
                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editStatBtn(
      String label, int value, Color color, VoidCallback inc, VoidCallback dec) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(icon: const Icon(Icons.remove), onPressed: dec, iconSize: 18),
            Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.add), onPressed: inc, iconSize: 18),
          ],
        ),
      ],
    );
  }

  // ── utils ─────────────────────────────────────

  String _monthName(int month) {
    const names = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[month];
  }
}