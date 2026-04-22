// attendance_screen.dart
//
// Add this to pubspec.yaml dependencies:
//   shared_preferences: ^2.2.2
//
// Then run: flutter pub get

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'timetable_screen.dart';

// ─────────────────────────────────────────────
//  MODELS
// ─────────────────────────────────────────────

enum AttendanceMark { notMarked, off, missed, attended, mixed }

class Subject {
  String name;
  int attended;
  int missed;
  int off;
  int criteria;

  Subject({
    required this.name,
    this.attended = 0,
    this.missed = 0,
    this.off = 0,
    this.criteria = 75,
  });

  int get total => attended + missed;
  double get percentage => total == 0 ? 0 : (attended / total * 100);

  int get lecturesNeeded {
    if (percentage >= criteria) return 0;
    if (criteria >= 100) return -1;
    double x = (criteria / 100 * total - attended) / (1 - criteria / 100);
    return x <= 0 ? 0 : x.ceil();
  }

  int get canSkip {
    if (percentage < criteria) return 0;
    if (criteria == 0) return 9999;
    double x = (attended * 100 / criteria) - total;
    return x <= 0 ? 0 : x.floor();
  }

  String get statusMessage {
    if (total == 0) return 'no lectures yet';
    if (percentage >= 100) return "can't miss the next lecture";
    if (lecturesNeeded > 0) return "need to attend $lecturesNeeded lectures";
    if (canSkip > 0) return "can skip $canSkip lectures";
    return "can't miss the next lecture";
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'attended': attended,
    'missed': missed,
    'off': off,
    'criteria': criteria,
  };

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
    name: j['name'] as String,
    attended: j['attended'] as int,
    missed: j['missed'] as int,
    off: j['off'] as int,
    criteria: j['criteria'] as int,
  );
}

class DayLog {
  final DateTime date;
  Map<String, AttendanceMark> subjectMarks;

  DayLog({required this.date, Map<String, AttendanceMark>? subjectMarks})
      : subjectMarks = subjectMarks ?? {};

  AttendanceMark get dayStatus {
    if (subjectMarks.isEmpty) return AttendanceMark.notMarked;
    final vals = subjectMarks.values.toSet();
    if (vals.length == 1) return vals.first;
    return AttendanceMark.mixed;
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'marks': subjectMarks.map((k, v) => MapEntry(k, v.index)),
  };

  factory DayLog.fromJson(Map<String, dynamic> j) {
    final marks = (j['marks'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, AttendanceMark.values[v as int]));
    return DayLog(
      date: DateTime.parse(j['date'] as String),
      subjectMarks: marks,
    );
  }
}

// ─────────────────────────────────────────────
//  PERSISTENCE
// ─────────────────────────────────────────────

class _Store {
  static const _kSubjects = 'att_subjects';
  static const _kDayLogs  = 'att_daylogs';
  static const _kCriteria = 'att_criteria';
  static const _kTheme    = 'att_theme';

  static Future<void> save({
    required List<Subject> subjects,
    required Map<String, DayLog> dayLogs,
    required int criteria,
    required String theme,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSubjects, jsonEncode(subjects.map((s) => s.toJson()).toList()));
    await p.setString(_kDayLogs, jsonEncode(dayLogs.map((k, v) => MapEntry(k, v.toJson()))));
    await p.setInt(_kCriteria, criteria);
    await p.setString(_kTheme, theme);
  }

  static Future<Map<String, dynamic>> load() async {
    final p = await SharedPreferences.getInstance();

    List<Subject> subjects = [];
    final sr = p.getString(_kSubjects);
    if (sr != null) {
      subjects = (jsonDecode(sr) as List)
          .map((e) => Subject.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    Map<String, DayLog> dayLogs = {};
    final lr = p.getString(_kDayLogs);
    if (lr != null) {
      dayLogs = (jsonDecode(lr) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, DayLog.fromJson(v as Map<String, dynamic>)));
    }

    return {
      'subjects': subjects,
      'dayLogs': dayLogs,
      'criteria': p.getInt(_kCriteria) ?? 75,
      'theme': p.getString(_kTheme) ?? 'System Default',
    };
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSubjects);
    await p.remove(_kDayLogs);
    await p.remove(_kCriteria);
    await p.remove(_kTheme);
  }
}

// ─────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int    _tab      = 0;
  int    _criteria = 75;
  String _theme    = 'System Default';
  bool   _loading  = true;

  List<Subject>         _subjects = [];
  Map<String, DayLog>   _dayLogs  = {};
  DateTime _calMonth     = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  // Default timetable (weekday 1=Mon .. 7=Sun)
  final Map<int, List<String>> _timetable = {
    1: ['PSDL', 'Devops', 'DE',  'ICS', 'CC'],
    2: ['EBI',  'CC',     'FSD', 'ICS', 'FSDL'],
    3: ['DEL',  'Devops', 'ICS', 'CC',  'DE'],
    4: ['FSD',  'EBI',    'CCL', '',    ''],
    5: ['Devops','DE',   'PSDL','FSD',  ''],
    6: [], 7: [],
  };

  // Used only when no saved data exists (first launch → zero attendance)
  static const _defaultNames = [
    'DEL','Devops','ICS','CC','CCL','DE','EBI','FSD','PSDL','FSDL'
  ];

  // ── lifecycle ────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _Store.load();
    setState(() {
      _criteria = data['criteria'] as int;
      _theme    = data['theme']    as String;
      _dayLogs  = data['dayLogs']  as Map<String, DayLog>;
      final saved = data['subjects'] as List<Subject>;
      _subjects = saved.isNotEmpty
          ? saved
          : _defaultNames.map((n) => Subject(name: n, criteria: _criteria)).toList();
      _loading = false;
    });
  }

  Future<void> _persist() => _Store.save(
      subjects: _subjects,
      dayLogs:  _dayLogs,
      criteria: _criteria,
      theme:    _theme);

  // ── helpers ──────────────────────────────────

  String _dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  DayLog _logOf(DateTime d) =>
      _dayLogs.putIfAbsent(_dk(d), () => DayLog(date: d));

  Subject? _sub(String name) {
    try { return _subjects.firstWhere((s) => s.name == name); }
    catch (_) { return null; }
  }

  double get _overallPct {
    int a = _subjects.fold(0, (s, e) => s + e.attended);
    int t = _subjects.fold(0, (s, e) => s + e.total);
    return t == 0 ? 0 : a / t * 100;
  }

  int get _overallNeeded {
    int a = _subjects.fold(0, (s, e) => s + e.attended);
    int t = _subjects.fold(0, (s, e) => s + e.total);
    if (_criteria >= 100) return -1;
    double x = (_criteria / 100 * t - a) / (1 - _criteria / 100);
    return x <= 0 ? 0 : x.ceil();
  }

  void _mark(Subject sub, AttendanceMark mark, DateTime date) {
    setState(() {
      final log  = _logOf(date);
      final prev = log.subjectMarks[sub.name];
      if (prev == AttendanceMark.attended) sub.attended = (sub.attended - 1).clamp(0, 9999);
      if (prev == AttendanceMark.missed)   sub.missed   = (sub.missed   - 1).clamp(0, 9999);
      if (prev == AttendanceMark.off)      sub.off      = (sub.off      - 1).clamp(0, 9999);
      if (prev == mark) {
        log.subjectMarks.remove(sub.name);
      } else {
        log.subjectMarks[sub.name] = mark;
        if (mark == AttendanceMark.attended) sub.attended++;
        if (mark == AttendanceMark.missed)   sub.missed++;
        if (mark == AttendanceMark.off)      sub.off++;
      }
    });
    _persist();
  }

  void _markAll(AttendanceMark mark, DateTime date) {
    for (final n in (_timetable[date.weekday] ?? []).where((n) => n.isNotEmpty)) {
      final s = _sub(n);
      if (s != null) _mark(s, mark, date);
    }
  }

  Color _dotColor(AttendanceMark m) {
    switch (m) {
      case AttendanceMark.attended: return Colors.green;
      case AttendanceMark.missed:   return Colors.red;
      case AttendanceMark.off:      return Colors.orange;
      case AttendanceMark.mixed:    return Colors.purple;
      default:                      return Colors.grey.shade400;
    }
  }

  String _wd(int w) => const ['','Mon','Tue','Wed','Thu','Fri','Sat','Sun'][w];
  String _mn(int m) => const ['','January','February','March','April','May','June',
    'July','August','September','October','November','December'][m];

  // ── build ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: _appBar(),
      body: _body(),
      bottomNavigationBar: SafeArea(top: false, child: _bottomNav()),
    );
  }

  // ── app bar ───────────────────────────────────

  PreferredSizeWidget _appBar() {
    String title;
    final List<Widget> actions = [];

    if (_tab != 4) {
      actions.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${_overallPct.toStringAsFixed(2)} | $_criteria',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ));
    }

    switch (_tab) {
      case 0:
        final d = _selectedDate;
        title = '${_wd(d.weekday)}, ${d.day} ${_mn(d.month)} ${d.year}';
        actions.add(IconButton(icon: const Icon(Icons.add), onPressed: _dlgAddSubject));
        break;
      case 2: title = 'Calendar'; break;
      case 3:
        title = 'Subjects';
        actions.add(IconButton(icon: const Icon(Icons.add), onPressed: _dlgAddSubject));
        actions.add(IconButton(icon: const Icon(Icons.more_vert), onPressed: _sheetSubjectsMenu));
        break;
      case 4:
        title = 'Settings';
        actions.add(TextButton(
          onPressed: () {},
          child: const Text('REMOVE ADS', style: TextStyle(fontSize: 11)),
        ));
        break;
      default: title = 'Attendance';
    }

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      title: Text(title,
          style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
      actions: actions,
    );
  }

  // ── body router ───────────────────────────────

  Widget _body() {
    switch (_tab) {
      case 0: return _tabToday();
      case 2: return _tabCalendar();
      case 3: return _tabSubjects();
      case 4: return _tabSettings();
      default: return _tabToday();
    }
  }

  // ═════════════════════════════════════════════
  //  TODAY TAB
  // ═════════════════════════════════════════════

  Widget _tabToday() {
    final log  = _logOf(_selectedDate);
    final subs = (_timetable[_selectedDate.weekday] ?? [])
        .where((n) => n.isNotEmpty)
        .map(_sub)
        .whereType<Subject>()
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ─ Day banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.teal.shade700, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Day status:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text(_statusLabel(log.dayStatus),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            )),
            _bulkBtn(Icons.block,                 'Clear', () => _markAll(AttendanceMark.notMarked, _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.remove_circle_outline, 'Off',   () => _markAll(AttendanceMark.off,       _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.close,                 'Miss',  () => _markAll(AttendanceMark.missed,    _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.check,                 'Att',   () => _markAll(AttendanceMark.attended,  _selectedDate), active: true),
          ]),
        ),
        const SizedBox(height: 10),
        if (subs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('No classes today', style: TextStyle(color: Colors.grey.shade500))),
          ),
        ...subs.map((s) => _cardToday(s, log.subjectMarks[s.name] ?? AttendanceMark.notMarked)),
      ],
    );
  }

  String _statusLabel(AttendanceMark m) {
    switch (m) {
      case AttendanceMark.attended: return 'All Attended';
      case AttendanceMark.missed:   return 'All Missed';
      case AttendanceMark.off:      return 'Holiday / Off';
      case AttendanceMark.mixed:    return 'Mixed';
      default:                      return 'Not marked';
    }
  }

  Widget _bulkBtn(IconData icon, String label, VoidCallback cb, {bool active = false}) =>
      GestureDetector(
        onTap: cb,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.green.shade600 : Colors.black26,
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ]),
      );

  Widget _cardToday(Subject sub, AttendanceMark cur) {
    final pColor = sub.percentage >= sub.criteria ? Colors.green.shade600 : Colors.red.shade400;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            _pctBadge(sub.percentage, sub.criteria, pColor),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(sub.statusMessage, style: TextStyle(color: pColor, fontSize: 12)),
              ],
            )),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _mkBtn(Icons.block,                 AttendanceMark.notMarked, cur, sub),
              const SizedBox(width: 12),
              _mkBtn(Icons.remove_circle_outline, AttendanceMark.off,       cur, sub),
              const SizedBox(width: 12),
              _mkBtn(Icons.close,                 AttendanceMark.missed,    cur, sub),
              const SizedBox(width: 12),
              _mkBtn(Icons.check,                 AttendanceMark.attended,  cur, sub),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _mkBtn(IconData icon, AttendanceMark mark, AttendanceMark cur, Subject sub) {
    final on = cur == mark;
    final c = mark == AttendanceMark.attended ? Colors.green
        : mark == AttendanceMark.missed   ? Colors.red
        : mark == AttendanceMark.off      ? Colors.orange
        : Colors.grey;
    return GestureDetector(
      onTap: () => _mark(sub, mark, _selectedDate),
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? c : Colors.transparent,
          border: Border.all(color: on ? c : Colors.grey.shade300),
        ),
        child: Icon(icon, size: 16, color: on ? Colors.white : Colors.grey.shade400),
      ),
    );
  }

  // ═════════════════════════════════════════════
  //  CALENDAR TAB
  // ═════════════════════════════════════════════

  Widget _tabCalendar() {
    final now      = DateTime.now();
    final first    = DateTime(_calMonth.year, _calMonth.month, 1);
    final days     = DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final offset   = first.weekday - 1;

    int nm = 0, off = 0, miss = 0, att = 0, mix = 0;
    for (int d = 1; d <= days; d++) {
      final date = DateTime(_calMonth.year, _calMonth.month, d);
      final log  = _dayLogs[_dk(date)];
      switch (log?.dayStatus ?? AttendanceMark.notMarked) {
        case AttendanceMark.attended: att++;  break;
        case AttendanceMark.missed:   miss++; break;
        case AttendanceMark.off:      off++;  break;
        case AttendanceMark.mixed:    mix++;  break;
        default:                      nm++;
      }
    }
    int ta = _subjects.fold(0,(s,e)=>s+e.attended);
    int tm = _subjects.fold(0,(s,e)=>s+e.missed);
    int to = _subjects.fold(0,(s,e)=>s+e.off);
    int tt = _subjects.fold(0,(s,e)=>s+e.total);

    return SingleChildScrollView(child: Column(children: [
      // Month nav
      Container(color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month-1))),
          Text('${_mn(_calMonth.month)} ${_calMonth.year}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          IconButton(icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month+1))),
        ]),
      ),
      // Weekday header
      Container(color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map((d) =>
            Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))))
        ).toList()),
      ),
      // Grid
      Container(color: Colors.white, padding: const EdgeInsets.only(bottom: 10),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.85),
          itemCount: offset + days,
          itemBuilder: (ctx, i) {
            if (i < offset) return const SizedBox();
            final day  = i - offset + 1;
            final date = DateTime(_calMonth.year, _calMonth.month, day);
            final log  = _dayLogs[_dk(date)];
            final mark = (log != null && log.subjectMarks.isNotEmpty)
                ? log.dayStatus : AttendanceMark.notMarked;
            final isToday  = date.year==now.year && date.month==now.month && date.day==now.day;
            final isSel    = date.year==_selectedDate.year && date.month==_selectedDate.month && date.day==_selectedDate.day;
            return GestureDetector(
              onTap: () => setState(() { _selectedDate = date; _tab = 0; }),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isToday ? Border.all(color: Colors.teal.shade400, width: 2) : null,
                    color:  isSel && !isToday ? Colors.teal.shade100 : null,
                  ),
                  child: Center(child: Text('$day', style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: isToday ? Colors.teal.shade700 : Colors.black87,
                  ))),
                ),
                const SizedBox(height: 2),
                Container(width:5,height:5,decoration: BoxDecoration(shape: BoxShape.circle, color: _dotColor(mark))),
              ]),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
      // Day summary
      _smCard(
        children: [
          _calStat('$nm',   'Not marked', Colors.grey.shade400),
          _calStat('$off',  'Off',         Colors.orange),
          _calStat('$miss', 'Missed',      Colors.red),
          _calStat('$att',  'Attended',    Colors.green),
          _calStat('$mix',  'Mixed',       Colors.purple),
        ],
        footer: 'Days',
      ),
      const SizedBox(height: 8),
      // Lecture totals
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _calStat('$to', 'Off',     Colors.grey),
          _calStat('$tm', 'Missed',  Colors.grey),
          _calStat('$ta', 'Attended',Colors.grey),
          _calStat('$tt', 'Total',   Colors.grey),
          _calStat('${_overallPct.toStringAsFixed(2)}%', 'Percent', Colors.grey),
        ]),
      ),
      const SizedBox(height: 16),
    ]));
  }

  Widget _smCard({required List<Widget> children, required String footer}) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: children),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.teal.shade700,
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
            ),
            child: Center(child: Text(footer, style: const TextStyle(color: Colors.white, fontSize: 12))),
          ),
        ]),
      );

  Widget _calStat(String v, String label, Color dot) => Column(children: [
    Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width:7,height:7,decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
      const SizedBox(width: 3),
      Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    ]),
    Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
  ]);

  // ═════════════════════════════════════════════
  //  SUBJECTS TAB
  // ═════════════════════════════════════════════

  Widget _tabSubjects() {
    int ta=_subjects.fold(0,(s,e)=>s+e.attended);
    int tm=_subjects.fold(0,(s,e)=>s+e.missed);
    int to=_subjects.fold(0,(s,e)=>s+e.off);
    int tt=_subjects.fold(0,(s,e)=>s+e.total);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _subCard(
          name: 'Overall',
          pct: _overallPct, criteria: _criteria,
          msg: _overallNeeded > 0 ? 'need to attend $_overallNeeded lectures' : tt==0 ? 'no lectures yet' : 'on track',
          att: ta, miss: tm, off: to, tot: tt, onTap: () {},
        ),
        ..._subjects.map((s) => _subCard(
          name: s.name, pct: s.percentage, criteria: s.criteria,
          msg: s.statusMessage, att: s.attended, miss: s.missed, off: s.off, tot: s.total,
          onTap: () => _sheetSubjectDetail(s),
        )),
      ],
    );
  }

  Widget _subCard({
    required String name, required double pct, required int criteria,
    required String msg, required int att, required int miss, required int off, required int tot,
    required VoidCallback onTap,
  }) {
    final ok = pct >= criteria;
    final c  = ok ? Colors.green.shade600 : Colors.red.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
          border: Border(left: BorderSide(color: c, width: 4)),
        ),
        child: Row(children: [
          _pctBadge(pct, criteria, c),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(msg, style: TextStyle(color: c, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Att: $att  Miss: $miss  Off: $off  Tot: $tot',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ])),
        ]),
      ),
    );
  }

  Widget _pctBadge(double pct, int criteria, Color c) => Container(
    width: 54, height: 54,
    decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(pct.toStringAsFixed(2), style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 12)),
      Container(height: 1, color: c.withOpacity(0.4), width: 40),
      Text('$criteria', style: TextStyle(color: c.withOpacity(0.8), fontSize: 12)),
    ]),
  );

  // ═════════════════════════════════════════════
  //  SETTINGS TAB
  // ═════════════════════════════════════════════

  Widget _tabSettings() => ListView(children: [
    _sSection('General'),
    _sTile(icon: Icons.track_changes,      title: 'Set criteria',  subtitle: '$_criteria%',                     onTap: _dlgCriteria),
    _sTile(icon: Icons.brightness_medium,  title: 'Set theme',     subtitle: '$_theme, using App colors',       onTap: _dlgTheme),
    _sSection('Database'),
    _sTile(icon: Icons.import_export,      title: 'Backup / Restore', subtitle: 'Save or load your attendance data.',         onTap: _dlgBackupRestore),
    _sTile(icon: Icons.description_outlined, title: 'Export data as CSV', subtitle: 'Preview a CSV summary of all subjects.', onTap: _exportCsv),
    _sSection('Attendance'),
    _sTile(icon: Icons.restart_alt, title: 'Reset all attendance',
        subtitle: 'Clears every subject back to 0 and deletes all day logs.',
        onTap: _dlgReset, titleColor: Colors.red.shade600),
    _sSection('App'),
    _sTile(icon: Icons.workspace_premium, title: 'Upgrade to Premium', onTap: () => _snack('Premium coming soon!')),
    _sTile(icon: Icons.share,             title: 'Share App',           onTap: () => _snack('Share feature coming soon!')),
    _sTile(icon: Icons.star_rate,         title: 'Rate on Google Play', onTap: () => _snack('Opening Play Store...')),
    _sTile(icon: Icons.people_outline,    title: 'Contact us', subtitle: 'Suggestions, bugs, questions', onTap: _dlgContact),
    _sTile(icon: Icons.info_outline,      title: 'App info',            onTap: _dlgAppInfo),
    const SizedBox(height: 20),
  ]);

  Widget _sSection(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16,18,16,4),
    child: Text(t, style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.w600, fontSize: 13)),
  );

  Widget _sTile({required IconData icon, required String title, String? subtitle,
    required VoidCallback onTap, Color? titleColor}) =>
      ListTile(
        tileColor: Colors.white,
        leading: Icon(icon, color: titleColor ?? Colors.grey.shade600),
        title: Text(title, style: TextStyle(fontSize: 14, color: titleColor ?? Colors.black87)),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)) : null,
        onTap: onTap,
      );

  // ═════════════════════════════════════════════
  //  BOTTOM NAV
  // ═════════════════════════════════════════════

  Widget _bottomNav() {
    final items = [
      {'icon': Icons.view_day_outlined,      'label': 'Today'},
      {'icon': Icons.view_column_outlined,   'label': 'Timetable'},
      {'icon': Icons.calendar_month_outlined,'label': 'Calendar'},
      {'icon': Icons.list_alt_outlined,      'label': 'Subjects'},
      {'icon': Icons.settings_outlined,      'label': 'Settings'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = _tab == i;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (i == 1) {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => TimetableScreen()));
                } else {
                  setState(() => _tab = i);
                }
              },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (active)
                  Container(
                    width: 38, height: 26,
                    decoration: BoxDecoration(
                      color: Colors.teal.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(items[i]['icon'] as IconData, color: Colors.white, size: 16),
                  )
                else
                  Icon(items[i]['icon'] as IconData, color: Colors.grey.shade500, size: 22),
                const SizedBox(height: 2),
                Text(
                  items[i]['label'] as String,
                  style: TextStyle(
                    fontSize: 10,
                    color: active ? Colors.teal.shade700 : Colors.grey.shade500,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ═════════════════════════════════════════════
  //  DIALOGS
  // ═════════════════════════════════════════════

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  // — Criteria ——
  void _dlgCriteria() {
    int tmp = _criteria;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Set Attendance Criteria'),
      content: StatefulBuilder(builder: (ctx, ss) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$tmp%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        Slider(value: tmp.toDouble(), min: 0, max: 100, divisions: 20,
            activeColor: Colors.teal, label: '$tmp%',
            onChanged: (v) => ss(() => tmp = v.round())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () {
          setState(() { _criteria = tmp; for (final s in _subjects) s.criteria = tmp; });
          _persist(); Navigator.pop(ctx);
        }, child: const Text('Save')),
      ],
    ));
  }

  // — Theme ——
  void _dlgTheme() {
    showDialog(context: context, builder: (ctx) => SimpleDialog(
      title: const Text('Set Theme'),
      children: ['System Default','Light','Dark'].map((opt) => RadioListTile<String>(
        value: opt, groupValue: _theme, title: Text(opt),
        onChanged: (v) {
          if (v != null) { setState(() => _theme = v); _persist(); _snack('Theme set to $v'); }
          Navigator.pop(ctx);
        },
      )).toList(),
    ));
  }

  // — Backup/Restore ——
  void _dlgBackupRestore() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Backup / Restore'),
      content: const Text('Backup saves your current data locally.\nRestore reloads the last saved state.'),
      actions: [
        TextButton(onPressed: () { _persist(); Navigator.pop(ctx); _snack('Backup saved!'); },
            child: const Text('Backup')),
        TextButton(onPressed: () async { Navigator.pop(ctx); await _load(); _snack('Data restored.'); },
            child: const Text('Restore')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ],
    ));
  }

  // — Export CSV ——
  void _exportCsv() {
    final sb = StringBuffer('Subject,Attended,Missed,Off,Total,Percentage\n');
    for (final s in _subjects) {
      sb.writeln('${s.name},${s.attended},${s.missed},${s.off},${s.total},${s.percentage.toStringAsFixed(2)}%');
    }
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('CSV Export Preview'),
      content: SingleChildScrollView(
          child: SelectableText(sb.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }

  // — Reset ——
  void _dlgReset() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Reset All Attendance'),
      content: const Text(
          'This will permanently delete all attendance records and reset every subject to 0.\n\nThis cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () async {
            await _Store.clear();
            setState(() {
              for (final s in _subjects) { s.attended = 0; s.missed = 0; s.off = 0; }
              _dayLogs.clear();
            });
            await _persist();
            if (mounted) Navigator.pop(ctx);
            _snack('All attendance data has been reset.');
          },
          child: const Text('Reset Everything'),
        ),
      ],
    ));
  }

  // — Contact ——
  void _dlgContact() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Contact Us'),
      content: const Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Suggestions, bugs, or questions?'),
            SizedBox(height: 10),
            Text('📧  support@collegeapp.dev', style: TextStyle(fontWeight: FontWeight.w500)),
          ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ));
  }

  // — App info ——
  void _dlgAppInfo() => showAboutDialog(
    context: context,
    applicationName: 'Attendance Tracker',
    applicationVersion: '1.0.0',
    applicationLegalese: '© 2026 College App',
    children: const [
      SizedBox(height: 10),
      Text('Track lecture attendance and never fall below your required percentage.'),
    ],
  );

  // — Add Subject ——
  void _dlgAddSubject() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Subject'),
      content: TextField(
        controller: ctrl, autofocus: true,
        decoration: const InputDecoration(hintText: 'Subject name (e.g. MATH)'),
        textCapitalization: TextCapitalization.characters,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () {
          final n = ctrl.text.trim().toUpperCase();
          if (n.isNotEmpty && !_subjects.any((s) => s.name == n)) {
            setState(() => _subjects.add(Subject(name: n, criteria: _criteria)));
            _persist();
          }
          Navigator.pop(ctx);
        }, child: const Text('Add')),
      ],
    ));
  }

  // — Subjects menu ——
  void _sheetSubjectsMenu() {
    showModalBottomSheet(context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.add), title: const Text('Add Subject'),
            onTap: () { Navigator.pop(ctx); _dlgAddSubject(); }),
        ListTile(
          leading: Icon(Icons.restart_alt, color: Colors.red.shade400),
          title: Text('Reset All Attendance', style: TextStyle(color: Colors.red.shade400)),
          onTap: () { Navigator.pop(ctx); _dlgReset(); },
        ),
      ])),
    );
  }

  // — Subject detail ——
  void _sheetSubjectDetail(Subject sub) {
    showModalBottomSheet(context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(child: StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 4),
          Text(sub.statusMessage, style: TextStyle(
              color: sub.percentage >= sub.criteria ? Colors.green : Colors.red, fontSize: 13)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _editStat('Att',  sub.attended, Colors.green,
                    () { ss(()=>sub.attended++);           setState((){}); _persist(); },
                    () { if(sub.attended>0) ss(()=>sub.attended--); setState((){}); _persist(); }),
            _editStat('Miss', sub.missed,   Colors.red,
                    () { ss(()=>sub.missed++);             setState((){}); _persist(); },
                    () { if(sub.missed>0) ss(()=>sub.missed--); setState((){}); _persist(); }),
            _editStat('Off',  sub.off,      Colors.orange,
                    () { ss(()=>sub.off++);                setState((){}); _persist(); },
                    () { if(sub.off>0) ss(()=>sub.off--);       setState((){}); _persist(); }),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(
              onPressed: () => showDialog(context: ctx, builder: (c) => AlertDialog(
                title: Text('Delete ${sub.name}?'),
                content: const Text('Removes the subject and all its data.'),
                actions: [
                  TextButton(onPressed: ()=>Navigator.pop(c), child: const Text('Cancel')),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () {
                      setState(()=>_subjects.remove(sub)); _persist();
                      Navigator.pop(c); Navigator.pop(ctx);
                    },
                    child: const Text('Delete'),
                  ),
                ],
              )),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Done')),
          ]),
        ]),
      ))),
    );
  }

  Widget _editStat(String label, int value, Color color, VoidCallback inc, VoidCallback dec) =>
      Column(children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: dec, iconSize: 20,
              color: Colors.grey.shade600),
          Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: inc, iconSize: 20,
              color: Colors.grey.shade600),
        ]),
      ]);
}