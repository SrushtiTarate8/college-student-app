// attendance_screen.dart
//
// Add this to pubspec.yaml dependencies:
//   shared_preferences: ^2.2.2
//
// Then run: flutter pub get

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _kSubjects  = 'att_subjects';
  static const _kDayLogs   = 'att_daylogs';
  static const _kCriteria  = 'att_criteria';
  static const _kTheme     = 'att_theme';
  static const _kTimetable = 'att_timetable';

  static Future<void> save({
    required List<Subject> subjects,
    required Map<String, DayLog> dayLogs,
    required int criteria,
    required String theme,
    required Map<int, List<String>> timetable,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSubjects, jsonEncode(subjects.map((s) => s.toJson()).toList()));
    await p.setString(_kDayLogs, jsonEncode(dayLogs.map((k, v) => MapEntry(k, v.toJson()))));
    await p.setInt(_kCriteria, criteria);
    await p.setString(_kTheme, theme);
    final ttEncoded = timetable.map((k, v) => MapEntry(k.toString(), v));
    await p.setString(_kTimetable, jsonEncode(ttEncoded));
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

    Map<int, List<String>> timetable = _defaultTimetable();
    final tr = p.getString(_kTimetable);
    if (tr != null) {
      final decoded = jsonDecode(tr) as Map<String, dynamic>;
      timetable = decoded.map((k, v) =>
          MapEntry(int.parse(k), List<String>.from(v as List)));
    }

    return {
      'subjects': subjects,
      'dayLogs': dayLogs,
      'criteria': p.getInt(_kCriteria) ?? 75,
      'theme': p.getString(_kTheme) ?? 'System Default',
      'timetable': timetable,
    };
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSubjects);
    await p.remove(_kDayLogs);
    await p.remove(_kCriteria);
    await p.remove(_kTheme);
  }

  static Map<int, List<String>> _defaultTimetable() => {
    1: ['PSDL', 'Devops', 'DE', 'ICS', 'CC'],
    2: ['EBI', 'CC', 'FSD', 'ICS', 'FSDL'],
    3: ['DEL', 'Devops', 'ICS', 'CC', 'DE'],
    4: ['FSD', 'EBI', 'CCL', '', ''],
    5: ['Devops', 'DE', 'PSDL', 'FSD', ''],
    6: [],
    7: [],
  };
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
  int _tab = 0;
  int _criteria = 75;
  String _theme = 'System Default';
  bool _loading = true;

  List<Subject> _subjects = [];
  Map<String, DayLog> _dayLogs = {};
  DateTime _calMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  Map<int, List<String>> _timetable = {};

  static const _defaultNames = [
    'DEL', 'Devops', 'ICS', 'CC', 'CCL', 'DE', 'EBI', 'FSD', 'PSDL', 'FSDL'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _Store.load();
    setState(() {
      _criteria = data['criteria'] as int;
      _theme = data['theme'] as String;
      _dayLogs = data['dayLogs'] as Map<String, DayLog>;
      _timetable = data['timetable'] as Map<int, List<String>>;
      final saved = data['subjects'] as List<Subject>;
      _subjects = saved.isNotEmpty
          ? saved
          : _defaultNames.map((n) => Subject(name: n, criteria: _criteria)).toList();
      _loading = false;
    });
  }

  Future<void> _persist() => _Store.save(
      subjects: _subjects,
      dayLogs: _dayLogs,
      criteria: _criteria,
      theme: _theme,
      timetable: _timetable);

  String _dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DayLog _logOf(DateTime d) =>
      _dayLogs.putIfAbsent(_dk(d), () => DayLog(date: d));

  Subject? _sub(String name) {
    try {
      return _subjects.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
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
      final log = _logOf(date);
      final prev = log.subjectMarks[sub.name];
      if (prev == AttendanceMark.attended) sub.attended = (sub.attended - 1).clamp(0, 9999);
      if (prev == AttendanceMark.missed) sub.missed = (sub.missed - 1).clamp(0, 9999);
      if (prev == AttendanceMark.off) sub.off = (sub.off - 1).clamp(0, 9999);
      if (prev == mark) {
        log.subjectMarks.remove(sub.name);
      } else {
        log.subjectMarks[sub.name] = mark;
        if (mark == AttendanceMark.attended) sub.attended++;
        if (mark == AttendanceMark.missed) sub.missed++;
        if (mark == AttendanceMark.off) sub.off++;
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

  String _wd(int w) => const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w];
  String _mn(int m) => const [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ][m];

  int get _maxSlots {
    int max = 0;
    for (int d = 1; d <= 7; d++) {
      final slots = (_timetable[d] ?? []).where((s) => s.isNotEmpty).length;
      if (slots > max) max = slots;
    }
    return max < 1 ? 1 : max;
  }

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
      case 1:
        title = 'Timetable';
        actions.add(IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit Timetable',
          onPressed: _sheetEditTimetable,
        ));
        break;
      case 2:
        title = 'Calendar';
        break;
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
      default:
        title = 'Attendance';
    }

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      title: Text(title,
          style: const TextStyle(
              fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
      actions: actions,
    );
  }

  Widget _body() {
    switch (_tab) {
      case 0: return _tabToday();
      case 1: return _tabTimetable();
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
    final log = _logOf(_selectedDate);
    final subs = (_timetable[_selectedDate.weekday] ?? [])
        .where((n) => n.isNotEmpty)
        .map(_sub)
        .whereType<Subject>()
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.teal.shade700,
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Day status:',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(_statusLabel(log.dayStatus),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ],
                )),
            _bulkBtn(Icons.block, 'Clear',
                    () => _markAll(AttendanceMark.notMarked, _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.remove_circle_outline, 'Off',
                    () => _markAll(AttendanceMark.off, _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.close, 'Miss',
                    () => _markAll(AttendanceMark.missed, _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.check, 'Att',
                    () => _markAll(AttendanceMark.attended, _selectedDate),
                active: true),
          ]),
        ),
        const SizedBox(height: 10),
        if (subs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
                child: Text('No classes today',
                    style: TextStyle(color: Colors.grey.shade500))),
          ),
        ...subs.map(
                (s) => _cardToday(s, log.subjectMarks[s.name] ?? AttendanceMark.notMarked)),
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

  Widget _bulkBtn(IconData icon, String label, VoidCallback cb,
      {bool active = false}) =>
      GestureDetector(
        onTap: cb,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
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
    final pColor =
    sub.percentage >= sub.criteria ? Colors.green.shade600 : Colors.red.shade400;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)
        ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            _pctBadge(sub.percentage, sub.criteria, pColor),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(sub.statusMessage,
                        style: TextStyle(color: pColor, fontSize: 12)),
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
              _mkBtn(Icons.block, AttendanceMark.notMarked, cur, sub),
              const SizedBox(width: 12),
              _mkBtn(Icons.remove_circle_outline, AttendanceMark.off, cur, sub),
              const SizedBox(width: 12),
              _mkBtn(Icons.close, AttendanceMark.missed, cur, sub),
              const SizedBox(width: 12),
              _mkBtn(Icons.check, AttendanceMark.attended, cur, sub),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _mkBtn(IconData icon, AttendanceMark mark, AttendanceMark cur, Subject sub) {
    final on = cur == mark;
    final c = mark == AttendanceMark.attended
        ? Colors.green
        : mark == AttendanceMark.missed
        ? Colors.red
        : mark == AttendanceMark.off
        ? Colors.orange
        : Colors.grey;
    return GestureDetector(
      onTap: () => _mark(sub, mark, _selectedDate),
      child: Container(
        width: 32,
        height: 32,
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
  //  TIMETABLE TAB
  // ═════════════════════════════════════════════

  Widget _tabTimetable() {
    final today = DateTime.now().weekday;
    final days = [1, 2, 3, 4, 5, 6, 7];
    final maxRows = _maxSlots;

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: days.map((d) {
              final isToday = d == today;
              return Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _wd(d),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                        isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday
                            ? Colors.teal.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                    if (isToday)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        height: 2,
                        width: 20,
                        color: Colors.teal.shade500,
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: days.map((d) {
                final slots =
                (_timetable[d] ?? []).where((s) => s.isNotEmpty).toList();
                final isToday = d == today;
                return Expanded(
                  child: Column(
                    children: List.generate(maxRows, (i) {
                      final name = i < slots.length ? slots[i] : '';
                      if (name.isEmpty) {
                        return Container(margin: const EdgeInsets.all(2), height: 72);
                      }
                      return GestureDetector(
                        onTap: () {
                          final now = DateTime.now();
                          int diff = d - now.weekday;
                          final target = now.add(Duration(days: diff));
                          setState(() {
                            _selectedDate = DateTime(
                                target.year, target.month, target.day);
                            _tab = 0;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          height: 72,
                          decoration: BoxDecoration(
                            color: isToday
                                ? Colors.teal.shade700
                                : Colors.blueGrey.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Stack(
                            children: [
                              Padding(
                                padding:
                                const EdgeInsets.fromLTRB(6, 6, 4, 4),
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (_sub(name) != null)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: Builder(builder: (_) {
                                    final s = _sub(name)!;
                                    final ok = s.percentage >= s.criteria;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: ok
                                            ? Colors.green.shade600
                                            : Colors.red.shade400,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${s.percentage.toStringAsFixed(0)}%',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 9),
                                      ),
                                    );
                                  }),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: Colors.teal.shade700,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Text("Today's classes",
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 16),
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: Colors.blueGrey.shade700,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Text('Other days',
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const Spacer(),
              Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 3),
              Text('Tap ✏ to edit',
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
        ),
      ],
    );
  }

  void _sheetEditTimetable() {
    final editTT = Map<int, List<String>>.fromEntries(
      List.generate(7, (i) {
        final d = i + 1;
        return MapEntry(d, List<String>.from(_timetable[d] ?? []));
      }),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _TimetableEditSheet(
        timetable: editTT,
        subjectNames: _subjects.map((s) => s.name).toList(),
        onSave: (updated) {
          setState(() => _timetable = updated);
          _persist();
          Navigator.pop(ctx);
          _snack('Timetable saved!');
        },
      ),
    );
  }

  // ═════════════════════════════════════════════
  //  CALENDAR TAB
  // ═════════════════════════════════════════════

  Widget _tabCalendar() {
    final now = DateTime.now();
    final first = DateTime(_calMonth.year, _calMonth.month, 1);
    final days = DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final offset = first.weekday - 1;

    int nm = 0, off = 0, miss = 0, att = 0, mix = 0;
    for (int d = 1; d <= days; d++) {
      final date = DateTime(_calMonth.year, _calMonth.month, d);
      final log = _dayLogs[_dk(date)];
      switch (log?.dayStatus ?? AttendanceMark.notMarked) {
        case AttendanceMark.attended: att++;  break;
        case AttendanceMark.missed:   miss++; break;
        case AttendanceMark.off:      off++;  break;
        case AttendanceMark.mixed:    mix++;  break;
        default:                      nm++;
      }
    }
    int ta = _subjects.fold(0, (s, e) => s + e.attended);
    int tm = _subjects.fold(0, (s, e) => s + e.missed);
    int to = _subjects.fold(0, (s, e) => s + e.off);
    int tt = _subjects.fold(0, (s, e) => s + e.total);

    return SingleChildScrollView(
        child: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() =>
                  _calMonth = DateTime(_calMonth.year, _calMonth.month - 1))),
              Text('${_mn(_calMonth.month)} ${_calMonth.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() =>
                  _calMonth = DateTime(_calMonth.year, _calMonth.month + 1))),
            ]),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
                children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                    .map((d) => Expanded(
                    child: Center(
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600)))))
                    .toList()),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 10),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 0.85),
              itemCount: offset + days,
              itemBuilder: (ctx, i) {
                if (i < offset) return const SizedBox();
                final day = i - offset + 1;
                final date = DateTime(_calMonth.year, _calMonth.month, day);
                final log = _dayLogs[_dk(date)];
                final mark = (log != null && log.subjectMarks.isNotEmpty)
                    ? log.dayStatus
                    : AttendanceMark.notMarked;
                final isToday = date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
                final isSel = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedDate = date;
                    _tab = 0;
                  }),
                  child:
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: isToday
                            ? Border.all(color: Colors.teal.shade400, width: 2)
                            : null,
                        color: isSel && !isToday ? Colors.teal.shade100 : null,
                      ),
                      child: Center(
                          child: Text('$day',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isToday
                                    ? Colors.teal.shade700
                                    : Colors.black87,
                              ))),
                    ),
                    const SizedBox(height: 2),
                    Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: _dotColor(mark))),
                  ]),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _smCard(
            children: [
              _calStat('$nm', 'Not marked', Colors.grey.shade400),
              _calStat('$off', 'Off', Colors.orange),
              _calStat('$miss', 'Missed', Colors.red),
              _calStat('$att', 'Attended', Colors.green),
              _calStat('$mix', 'Mixed', Colors.purple),
            ],
            footer: 'Days',
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _calStat('$to', 'Off', Colors.grey),
              _calStat('$tm', 'Missed', Colors.grey),
              _calStat('$ta', 'Attended', Colors.grey),
              _calStat('$tt', 'Total', Colors.grey),
              _calStat('${_overallPct.toStringAsFixed(2)}%', 'Percent', Colors.grey),
            ]),
          ),
          const SizedBox(height: 16),
        ]));
  }

  Widget _smCard({required List<Widget> children, required String footer}) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: children),
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
            child: Center(
                child: Text(footer,
                    style: const TextStyle(color: Colors.white, fontSize: 12))),
          ),
        ]),
      );

  Widget _calStat(String v, String label, Color dot) => Column(children: [
    Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 7,
          height: 7,
          decoration:
          BoxDecoration(shape: BoxShape.circle, color: dot)),
      const SizedBox(width: 3),
      Text(v,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14)),
    ]),
    Text(label,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 10)),
  ]);

  // ═════════════════════════════════════════════
  //  SUBJECTS TAB
  // ═════════════════════════════════════════════

  Widget _tabSubjects() {
    int ta = _subjects.fold(0, (s, e) => s + e.attended);
    int tm = _subjects.fold(0, (s, e) => s + e.missed);
    int to = _subjects.fold(0, (s, e) => s + e.off);
    int tt = _subjects.fold(0, (s, e) => s + e.total);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _subCard(
          name: 'Overall',
          pct: _overallPct,
          criteria: _criteria,
          msg: _overallNeeded > 0
              ? 'need to attend $_overallNeeded lectures'
              : tt == 0
              ? 'no lectures yet'
              : 'on track',
          att: ta,
          miss: tm,
          off: to,
          tot: tt,
          onTap: () {},
        ),
        ..._subjects.map((s) => _subCard(
          name: s.name,
          pct: s.percentage,
          criteria: s.criteria,
          msg: s.statusMessage,
          att: s.attended,
          miss: s.missed,
          off: s.off,
          tot: s.total,
          onTap: () => _sheetSubjectDetail(s),
        )),
      ],
    );
  }

  Widget _subCard({
    required String name,
    required double pct,
    required int criteria,
    required String msg,
    required int att,
    required int miss,
    required int off,
    required int tot,
    required VoidCallback onTap,
  }) {
    final ok = pct >= criteria;
    final c = ok ? Colors.green.shade600 : Colors.red.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)
          ],
          border: Border(left: BorderSide(color: c, width: 4)),
        ),
        child: Row(children: [
          _pctBadge(pct, criteria, c),
          const SizedBox(width: 14),
          Expanded(
              child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
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
    width: 54,
    height: 54,
    decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(pct.toStringAsFixed(2),
          style: TextStyle(
              color: c, fontWeight: FontWeight.bold, fontSize: 12)),
      Container(height: 1, color: c.withOpacity(0.4), width: 40),
      Text('$criteria',
          style: TextStyle(color: c.withOpacity(0.8), fontSize: 12)),
    ]),
  );

  // ═════════════════════════════════════════════
  //  SETTINGS TAB
  // ═════════════════════════════════════════════

  Widget _tabSettings() => ListView(children: [
    _sSection('General'),
    _sTile(
        icon: Icons.track_changes,
        title: 'Set criteria',
        subtitle: '$_criteria%',
        onTap: _dlgCriteria),
    _sSection('Database'),
    _sTile(
        icon: Icons.import_export,
        title: 'Backup / Restore',
        subtitle: 'Save or load your attendance data.',
        onTap: _dlgBackupRestore),
    _sTile(
        icon: Icons.description_outlined,
        title: 'Export data as CSV',
        subtitle: 'Preview a CSV summary of all subjects.',
        onTap: _exportCsv),
    _sSection('Attendance'),
    _sTile(
        icon: Icons.restart_alt,
        title: 'Reset all attendance',
        subtitle: 'Clears every subject back to 0 and deletes all day logs.',
        onTap: _dlgReset,
        titleColor: Colors.red.shade600),
    const SizedBox(height: 20),
  ]);

  Widget _sSection(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
    child: Text(t,
        style: TextStyle(
            color: Colors.teal.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 13)),
  );

  Widget _sTile(
      {required IconData icon,
        required String title,
        String? subtitle,
        required VoidCallback onTap,
        Color? titleColor}) =>
      ListTile(
        tileColor: Colors.white,
        leading: Icon(icon, color: titleColor ?? Colors.grey.shade600),
        title: Text(title,
            style:
            TextStyle(fontSize: 14, color: titleColor ?? Colors.black87)),
        subtitle: subtitle != null
            ? Text(subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
            : null,
        onTap: onTap,
      );

  // ═════════════════════════════════════════════
  //  BOTTOM NAV
  // ═════════════════════════════════════════════

  Widget _bottomNav() {
    final items = [
      {'icon': Icons.view_day_outlined, 'label': 'Today'},
      {'icon': Icons.view_column_outlined, 'label': 'Timetable'},
      {'icon': Icons.calendar_month_outlined, 'label': 'Calendar'},
      {'icon': Icons.list_alt_outlined, 'label': 'Subjects'},
      {'icon': Icons.settings_outlined, 'label': 'Settings'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = _tab == i;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _tab = i),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (active)
                  Container(
                    width: 38,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.teal.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(items[i]['icon'] as IconData,
                        color: Colors.white, size: 16),
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

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));

  void _dlgCriteria() {
    int tmp = _criteria;
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Set Attendance Criteria'),
          content: StatefulBuilder(
              builder: (ctx, ss) =>
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('$tmp%',
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                    Slider(
                        value: tmp.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        activeColor: Colors.teal,
                        label: '$tmp%',
                        onChanged: (v) => ss(() => tmp = v.round())),
                  ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  setState(() {
                    _criteria = tmp;
                    for (final s in _subjects) s.criteria = tmp;
                  });
                  _persist();
                  Navigator.pop(ctx);
                },
                child: const Text('Save')),
          ],
        ));
  }

  void _dlgBackupRestore() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup / Restore'),
          content: const Text(
              'Backup saves your current data locally.\nRestore reloads the last saved state.'),
          actions: [
            TextButton(
                onPressed: () {
                  _persist();
                  Navigator.pop(ctx);
                  _snack('Backup saved!');
                },
                child: const Text('Backup')),
            TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _load();
                  _snack('Data restored.');
                },
                child: const Text('Restore')),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
          ],
        ));
  }

  void _exportCsv() {
    final sb = StringBuffer('Subject,Attended,Missed,Off,Total,Percentage\n');
    for (final s in _subjects) {
      sb.writeln(
          '${s.name},${s.attended},${s.missed},${s.off},${s.total},${s.percentage.toStringAsFixed(2)}%');
    }
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CSV Export Preview'),
          content: SingleChildScrollView(
              child: SelectableText(sb.toString(),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'))
          ],
        ));
  }

  void _dlgReset() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reset All Attendance'),
          content: const Text(
              'This will permanently delete all attendance records and reset every subject to 0.\n\nThis cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                await _Store.clear();
                setState(() {
                  for (final s in _subjects) {
                    s.attended = 0;
                    s.missed = 0;
                    s.off = 0;
                  }
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

  void _dlgAddSubject() {
    final ctrl = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add Subject'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration:
            const InputDecoration(hintText: 'Subject name (e.g. MATH)'),
            textCapitalization: TextCapitalization.characters,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  final n = ctrl.text.trim().toUpperCase();
                  if (n.isNotEmpty && !_subjects.any((s) => s.name == n)) {
                    setState(() => _subjects
                        .add(Subject(name: n, criteria: _criteria)));
                    _persist();
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Add')),
          ],
        ));
  }

  void _sheetSubjectsMenu() {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
        builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add Subject'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _dlgAddSubject();
                  }),
              ListTile(
                leading: Icon(Icons.restart_alt, color: Colors.red.shade400),
                title: Text('Reset All Attendance',
                    style: TextStyle(color: Colors.red.shade400)),
                onTap: () {
                  Navigator.pop(ctx);
                  _dlgReset();
                },
              ),
            ])));
  }

  void _sheetSubjectDetail(Subject sub) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => SafeArea(
            child: StatefulBuilder(
                builder: (ctx, ss) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(sub.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text(sub.statusMessage,
                        style: TextStyle(
                            color: sub.percentage >= sub.criteria
                                ? Colors.green
                                : Colors.red,
                            fontSize: 13)),
                    const SizedBox(height: 16),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _editStat(
                              'Att',
                              sub.attended,
                              Colors.green,
                                  () {
                                ss(() => sub.attended++);
                                setState(() {});
                                _persist();
                              },
                                  () {
                                if (sub.attended > 0)
                                  ss(() => sub.attended--);
                                setState(() {});
                                _persist();
                              }),
                          _editStat(
                              'Miss',
                              sub.missed,
                              Colors.red,
                                  () {
                                ss(() => sub.missed++);
                                setState(() {});
                                _persist();
                              },
                                  () {
                                if (sub.missed > 0) ss(() => sub.missed--);
                                setState(() {});
                                _persist();
                              }),
                          _editStat(
                              'Off',
                              sub.off,
                              Colors.orange,
                                  () {
                                ss(() => sub.off++);
                                setState(() {});
                                _persist();
                              },
                                  () {
                                if (sub.off > 0) ss(() => sub.off--);
                                setState(() {});
                                _persist();
                              }),
                        ]),
                    const SizedBox(height: 12),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => showDialog(
                                context: ctx,
                                builder: (c) => AlertDialog(
                                  title: Text('Delete ${sub.name}?'),
                                  content: const Text(
                                      'Removes the subject and all its data.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(c),
                                        child: const Text('Cancel')),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                          foregroundColor: Colors.red),
                                      onPressed: () {
                                        setState(() =>
                                            _subjects.remove(sub));
                                        _persist();
                                        Navigator.pop(c);
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                )),
                            child: const Text('Delete',
                                style: TextStyle(color: Colors.red)),
                          ),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Done')),
                        ]),
                  ]),
                ))));
  }

  Widget _editStat(String label, int value, Color color, VoidCallback inc,
      VoidCallback dec) =>
      Column(children: [
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: dec,
              iconSize: 20,
              color: Colors.grey.shade600),
          Text('$value',
              style:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: inc,
              iconSize: 20,
              color: Colors.grey.shade600),
        ]),
      ]);
}

// ═════════════════════════════════════════════
//  TIMETABLE EDIT SHEET
// ═════════════════════════════════════════════

class _TimetableEditSheet extends StatefulWidget {
  final Map<int, List<String>> timetable;
  final List<String> subjectNames;
  final void Function(Map<int, List<String>>) onSave;

  const _TimetableEditSheet({
    required this.timetable,
    required this.subjectNames,
    required this.onSave,
  });

  @override
  State<_TimetableEditSheet> createState() => _TimetableEditSheetState();
}

class _TimetableEditSheetState extends State<_TimetableEditSheet> {
  late Map<int, List<String>> _tt;
  int _selectedDay = 1;

  // Controllers keyed by a unique ID per slot so they survive reorders/deletions
  // Key = unique slot id (increments), Value = TextEditingController
  final Map<int, TextEditingController> _controllers = {};
  // Parallel list of unique IDs for the current day's slots
  final List<int> _slotIds = [];
  int _nextId = 0;

  static const _dayNames = [
    '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _dayShort = [
    '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now().weekday;
    _tt = Map<int, List<String>>.fromEntries(
      List.generate(7, (i) {
        final d = i + 1;
        return MapEntry(d, List<String>.from(widget.timetable[d] ?? []));
      }),
    );
    _rebuildControllers();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Sync _slotIds + _controllers whenever day or data changes ──────────────

  void _rebuildControllers() {
    // Dispose controllers that are no longer needed
    for (final id in List<int>.from(_slotIds)) {
      _controllers[id]?.dispose();
      _controllers.remove(id);
    }
    _slotIds.clear();

    final slots = _tt[_selectedDay] ?? [];
    for (final name in slots) {
      final id = _nextId++;
      _slotIds.add(id);
      _controllers[id] = TextEditingController(text: name);
    }
  }

  // ── Flush controller text → _tt before any structural change ──────────────

  void _flushToData() {
    final slots = <String>[];
    for (final id in _slotIds) {
      slots.add(_controllers[id]?.text.trim().toUpperCase() ?? '');
    }
    _tt[_selectedDay] = slots;
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  void _switchDay(int d) {
    _flushToData();
    setState(() {
      _selectedDay = d;
      _rebuildControllers();
    });
  }

  void _addSlot() {
    _flushToData();
    setState(() {
      _tt[_selectedDay]!.add('');
      final id = _nextId++;
      _slotIds.add(id);
      _controllers[id] = TextEditingController(text: '');
    });
  }

  void _removeSlot(int listIndex) {
    _flushToData();
    setState(() {
      final id = _slotIds[listIndex];
      _controllers[id]?.dispose();
      _controllers.remove(id);
      _slotIds.removeAt(listIndex);
      _tt[_selectedDay]!.removeAt(listIndex);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    _flushToData();
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      // Reorder the ID list
      final id = _slotIds.removeAt(oldIndex);
      _slotIds.insert(newIndex, id);
      // Reorder the data list to match
      final name = _tt[_selectedDay]!.removeAt(oldIndex);
      _tt[_selectedDay]!.insert(newIndex, name);
    });
  }

  void _appendSubject(String name) {
    _flushToData();
    setState(() {
      _tt[_selectedDay]!.add(name);
      final id = _nextId++;
      _slotIds.add(id);
      _controllers[id] = TextEditingController(text: name);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title + Save
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Text('Edit Timetable',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Save'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.teal.shade700),
                onPressed: () {
                  _flushToData();
                  widget.onSave(_tt);
                },
              ),
            ]),
          ),
          // Day selector
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 7,
              itemBuilder: (ctx, i) {
                final d = i + 1;
                final active = _selectedDay == d;
                return GestureDetector(
                  onTap: () => _switchDay(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.teal.shade700
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _dayShort[d],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: active
                            ? Colors.white
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Divider(color: Colors.grey.shade200),
          // Hint row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text(_dayNames[_selectedDay],
                  style: TextStyle(
                      color: Colors.teal.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const Spacer(),
              Icon(Icons.drag_handle, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text('Hold & drag to reorder',
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]),
          ),
          // Slot list (ReorderableListView + scrollable)
          Expanded(
            child: _slotIds.isEmpty
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('No classes — tap + to add',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 13)),
                  const SizedBox(height: 16),
                  _addButton(),
                  const SizedBox(height: 16),
                  _quickFillSection(),
                ],
              ),
            )
                : ReorderableListView.builder(
              scrollController: scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              onReorder: _onReorder,
              // Disable default drag handle so we provide our own
              buildDefaultDragHandles: false,
              itemCount: _slotIds.length,
              itemBuilder: (ctx, idx) {
                final id = _slotIds[idx];
                final ctrl = _controllers[id]!;
                return _slotRow(key: ValueKey(id), idx: idx, id: id, ctrl: ctrl);
              },
              footer: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _addButton(),
                    const SizedBox(height: 20),
                    _quickFillSection(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton() => OutlinedButton.icon(
    onPressed: _addSlot,
    icon: const Icon(Icons.add, size: 18),
    label: Text('Add slot ${_slotIds.length + 1}'),
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.teal.shade700,
      side: BorderSide(color: Colors.teal.shade300),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );

  Widget _quickFillSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Quick fill from subjects',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: widget.subjectNames
            .map((name) => GestureDetector(
          onTap: () => _appendSubject(name),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(6),
              border:
              Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Text(name,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey.shade700)),
          ),
        ))
            .toList(),
      ),
    ],
  );

  Widget _slotRow({
    required Key key,
    required int idx,
    required int id,
    required TextEditingController ctrl,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 3)
        ],
      ),
      child: Row(children: [
        // Slot number badge
        Container(
          width: 36,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              bottomLeft: Radius.circular(8),
            ),
          ),
          child: Center(
            child: Text('${idx + 1}',
                style: TextStyle(
                    color: Colors.teal.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
        ),
        // Text field with autocomplete
        Expanded(
          child: Autocomplete<String>(
            initialValue: TextEditingValue(text: ctrl.text),
            optionsBuilder: (tv) {
              if (tv.text.isEmpty) return widget.subjectNames;
              return widget.subjectNames.where(
                      (n) => n.toLowerCase().contains(tv.text.toLowerCase()));
            },
            onSelected: (val) {
              ctrl.text = val.toUpperCase();
              _flushToData();
            },
            fieldViewBuilder: (ctx, autoCtrl, fn, onSub) {
              // Sync the autocomplete's internal controller with our keyed one
              // by keeping the autoCtrl in sync on focus
              autoCtrl.text = ctrl.text;
              autoCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: autoCtrl.text.length));
              return TextField(
                controller: autoCtrl,
                focusNode: fn,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Subject name',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 14),
                onChanged: (v) {
                  ctrl.text = v.toUpperCase();
                },
              );
            },
          ),
        ),
        // Drag handle
        ReorderableDragStartListener(
          index: idx,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.drag_handle,
                color: Colors.grey.shade400, size: 20),
          ),
        ),
        // Delete
        IconButton(
          icon: Icon(Icons.close, size: 18, color: Colors.red.shade300),
          onPressed: () => _removeSlot(idx),
          tooltip: 'Remove slot',
        ),
      ]),
    );
  }
}