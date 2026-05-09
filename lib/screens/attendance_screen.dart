// attendance_screen.dart
//
// Add this to pubspec.yaml dependencies:
//   shared_preferences: ^2.2.2
//   provider: ^6.1.1
//
// Then run: flutter pub get

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';

// ─── BRAND COLORS ────────────────────────────────────────────────────────────
class _C {
  static const primary   = Color(0xFF6C63FF);
  static const primaryDk = Color(0xFF9B59B6);
  static const green     = Color(0xFF43E97B);
  static const red       = Color(0xFFFF6B6B);
  static const orange    = Color(0xFFFFA751);
  static const purple    = Color(0xFF9B59B6);
  static const darkBg      = Color(0xFF0F0E17);
  static const darkSurface = Color(0xFF1A1A2E);
  static const darkCard    = Color(0xFF1E1E32);
  static const lightBg     = Color(0xFFF5F4FB);
}

// ─── MODELS ──────────────────────────────────────────────────────────────────
enum AttendanceMark { notMarked, off, missed, attended, mixed }

class Subject {
  String name;
  int attended, missed, off, criteria;

  Subject({required this.name, this.attended = 0, this.missed = 0,
    this.off = 0, this.criteria = 75});

  int    get total      => attended + missed;
  double get percentage => total == 0 ? 0 : attended / total * 100;

  int get lecturesNeeded {
    if (percentage >= criteria) return 0;
    if (criteria >= 100) return -1;
    return ((criteria / 100 * total - attended) / (1 - criteria / 100)).ceil().clamp(0, 9999);
  }

  int get canSkip {
    if (percentage < criteria || criteria == 0) return percentage < criteria ? 0 : 9999;
    final x = (attended * 100 / criteria) - total;
    return x <= 0 ? 0 : x.floor();
  }

  String get statusMessage {
    if (total == 0) return 'no lectures yet';
    if (lecturesNeeded > 0) return 'need to attend $lecturesNeeded lectures';
    if (canSkip > 0) return 'can skip $canSkip lectures';
    return "can't miss the next lecture";
  }

  Map<String, dynamic> toJson() => {
    'name': name, 'attended': attended, 'missed': missed,
    'off': off, 'criteria': criteria,
  };

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
    name: j['name'], attended: j['attended'], missed: j['missed'],
    off: j['off'], criteria: j['criteria'],
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
    return vals.length == 1 ? vals.first : AttendanceMark.mixed;
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'marks': subjectMarks.map((k, v) => MapEntry(k, v.index)),
  };

  factory DayLog.fromJson(Map<String, dynamic> j) => DayLog(
    date: DateTime.parse(j['date']),
    subjectMarks: (j['marks'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, AttendanceMark.values[v as int])),
  );
}

// ─── PERSISTENCE ─────────────────────────────────────────────────────────────
class _Store {
  static const _kS = 'att_subjects', _kD = 'att_daylogs',
      _kC = 'att_criteria', _kT = 'att_timetable';

  static Future<void> save({
    required List<Subject> subjects,
    required Map<String, DayLog> dayLogs,
    required int criteria,
    required Map<int, List<String>> timetable,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kS, jsonEncode(subjects.map((s) => s.toJson()).toList()));
    await p.setString(_kD, jsonEncode(dayLogs.map((k, v) => MapEntry(k, v.toJson()))));
    await p.setInt(_kC, criteria);
    await p.setString(_kT, jsonEncode(timetable.map((k, v) => MapEntry(k.toString(), v))));
  }

  static Future<Map<String, dynamic>> load() async {
    final p = await SharedPreferences.getInstance();
    final sr = p.getString(_kS);
    final lr = p.getString(_kD);
    final tr = p.getString(_kT);
    return {
      'subjects': sr == null
          ? <Subject>[]
          : (jsonDecode(sr) as List).map((e) => Subject.fromJson(e)).toList(),
      'dayLogs': lr == null
          ? <String, DayLog>{}
          : (jsonDecode(lr) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, DayLog.fromJson(v))),
      'criteria': p.getInt(_kC) ?? 75,
      'timetable': tr == null
          ? _defaultTT()
          : (jsonDecode(tr) as Map<String, dynamic>)
          .map((k, v) => MapEntry(int.parse(k), List<String>.from(v))),
    };
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([p.remove(_kS), p.remove(_kD), p.remove(_kC), p.remove(_kT)]);
  }

  static Map<int, List<String>> _defaultTT() => {
    1: ['PSDL', 'Devops', 'DE', 'ICS', 'CC'],
    2: ['EBI', 'CC', 'FSD', 'ICS', 'FSDL'],
    3: ['DEL', 'Devops', 'ICS', 'CC', 'DE'],
    4: ['FSD', 'EBI', 'CCL', '', ''],
    5: ['Devops', 'DE', 'PSDL', 'FSD', ''],
    6: [], 7: [],
  };
}

// ─── SCREEN ───────────────────────────────────────────────────────────────────
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  int      _tab      = 0;
  int      _criteria = 75;
  bool     _loading  = true;

  List<Subject>            _subjects  = [];
  Map<String, DayLog>      _dayLogs   = {};
  Map<int, List<String>>   _timetable = {};
  DateTime _calMonth    = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  static const _defaultNames = [
    'DEL','Devops','ICS','CC','CCL','DE','EBI','FSD','PSDL','FSDL'
  ];

  // ── Theme helpers ──────────────────────────────────────────────────────────
  bool get _isDark => Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
  Color get _bg       => _isDark ? _C.darkBg      : _C.lightBg;
  Color get _surface  => _isDark ? _C.darkSurface  : Colors.white;
  Color get _card     => _isDark ? _C.darkCard     : Colors.white;
  Color get _pt       => _isDark ? Colors.white    : const Color(0xFF1A1535);
  Color get _st       => _isDark ? Colors.white54  : const Color(0xFF1A1535).withOpacity(0.5);
  Color get _div      => _isDark ? Colors.white12  : _C.primary.withOpacity(0.1);

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final data = await _Store.load();
    setState(() {
      _criteria  = data['criteria'];
      _dayLogs   = data['dayLogs'];
      _timetable = data['timetable'];
      final saved = data['subjects'] as List<Subject>;
      _subjects = saved.isNotEmpty
          ? saved
          : _defaultNames.map((n) => Subject(name: n, criteria: _criteria)).toList();
      _loading = false;
    });
  }

  Future<void> _persist() => _Store.save(
      subjects: _subjects, dayLogs: _dayLogs,
      criteria: _criteria, timetable: _timetable);

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _dk(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  DayLog _logOf(DateTime d) =>
      _dayLogs.putIfAbsent(_dk(d), () => DayLog(date: d));

  Subject? _sub(String name) {
    try { return _subjects.firstWhere((s) => s.name == name); } catch (_) { return null; }
  }

  double get _overallPct {
    final a = _subjects.fold(0, (s, e) => s + e.attended);
    final t = _subjects.fold(0, (s, e) => s + e.total);
    return t == 0 ? 0 : a / t * 100;
  }

  int get _overallNeeded {
    final a = _subjects.fold(0, (s, e) => s + e.attended);
    final t = _subjects.fold(0, (s, e) => s + e.total);
    if (_criteria >= 100) return -1;
    final x = (_criteria / 100 * t - a) / (1 - _criteria / 100);
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

  Color _dotColor(AttendanceMark m) => switch (m) {
    AttendanceMark.attended => _C.green,
    AttendanceMark.missed   => _C.red,
    AttendanceMark.off      => _C.orange,
    AttendanceMark.mixed    => _C.purple,
    _                       => Colors.grey.shade400,
  };

  static const _wds = ['','Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  static const _mns = ['','January','February','March','April','May','June',
    'July','August','September','October','November','December'];
  String _wd(int w) => _wds[w];
  String _mn(int m) => _mns[m];

  int get _maxSlots {
    int max = 0;
    for (int d = 1; d <= 7; d++) {
      final s = (_timetable[d] ?? []).where((s) => s.isNotEmpty).length;
      if (s > max) max = s;
    }
    return max < 1 ? 1 : max;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tp = Provider.of<ThemeProvider>(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: tp.isDarkMode ? _C.darkBg : _C.lightBg,
        body: const Center(child: CircularProgressIndicator(color: _C.primary)),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(tp),
      body: _body(),
      bottomNavigationBar: SafeArea(top: false, child: _bottomNav(tp.isDarkMode)),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _appBar(ThemeProvider tp) {
    final isDark = tp.isDarkMode;
    String title;
    final actions = <Widget>[
      // Dark mode toggle
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        // child:
        // GestureDetector(
        //   onTap: tp.toggleTheme,
        //   child: AnimatedContainer(
        //     duration: const Duration(milliseconds: 300),
        //     width: 48, height: 28,
        //     padding: const EdgeInsets.all(3),
        //     decoration: BoxDecoration(
        //       borderRadius: BorderRadius.circular(20),
        //       gradient: isDark
        //           ? const LinearGradient(colors: [_C.primary, _C.primaryDk])
        //           : LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade200]),
        //       boxShadow: [BoxShadow(
        //         color: isDark ? _C.primary.withOpacity(0.35) : Colors.black.withOpacity(0.1),
        //         blurRadius: 8, offset: const Offset(0, 2),
        //       )],
        //     ),
        //     child: AnimatedAlign(
        //       duration: const Duration(milliseconds: 300),
        //       curve: Curves.easeInOut,
        //       alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
        //       child: Container(
        //         width: 22, height: 22,
        //         decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        //         child: Center(child: Icon(
        //           isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
        //           color: isDark ? _C.primary : Colors.amber, size: 13,
        //         )),
        //       ),
        //     ),
        //   ),
        // ),
      ),
      // Overall % badge
      if (_tab != 4)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _C.primary.withOpacity(0.15), _C.primaryDk.withOpacity(0.1)
            ]),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _C.primary.withOpacity(0.4)),
          ),
          child: Text('${_overallPct.toStringAsFixed(2)} | $_criteria',
              style: const TextStyle(color: _C.primary, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
    ];

    switch (_tab) {
      case 0:
        final d = _selectedDate;
        title = '${_wd(d.weekday)}, ${d.day} ${_mn(d.month)} ${d.year}';
        actions.add(IconButton(icon: const Icon(Icons.add, color: _C.primary), onPressed: _dlgAddSubject));
      case 1:
        title = 'Timetable';
        actions.add(IconButton(
          icon: const Icon(Icons.edit_outlined, color: _C.primary),
          tooltip: 'Edit Timetable', onPressed: _sheetEditTimetable,
        ));
      case 2: title = 'Calendar';
      case 3:
        title = 'Subjects';
        actions.add(IconButton(icon: const Icon(Icons.add, color: _C.primary), onPressed: _dlgAddSubject));
        actions.add(IconButton(icon: const Icon(Icons.more_vert, color: _C.primary), onPressed: _sheetSubjectsMenu));
      case 4: title = 'Settings';
      default: title = 'Attendance';
    }

    return AppBar(
      backgroundColor: isDark ? _C.darkSurface : Colors.white,
      elevation: 0, shadowColor: Colors.transparent, surfaceTintColor: Colors.transparent,
      leading: Navigator.canPop(context)
          ? IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : const Color(0xFF1A1535)),
          onPressed: () => Navigator.pop(context))
          : null,
      title: Text(title, style: TextStyle(
          fontSize: 15, color: isDark ? Colors.white : const Color(0xFF1A1535),
          fontWeight: FontWeight.w600)),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_C.primary, _C.primaryDk]),
        )),
      ),
    );
  }

  Widget _body() => switch (_tab) {
    0 => _tabToday(),
    1 => _tabTimetable(),
    2 => _tabCalendar(),
    3 => _tabSubjects(),
    4 => _tabSettings(),
    _ => _tabToday(),
  };

  // ═══ TODAY TAB ════════════════════════════════════════════════════════════
  Widget _tabToday() {
    final log  = _logOf(_selectedDate);
    final subs = (_timetable[_selectedDate.weekday] ?? [])
        .where((n) => n.isNotEmpty).map(_sub).whereType<Subject>().toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_C.primary, _C.primaryDk],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: _C.primary.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Day status:', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(_statusLabel(log.dayStatus), style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ])),
            _bulkBtn(Icons.block,                'Clear', () => _markAll(AttendanceMark.notMarked, _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.remove_circle_outline,'Off',   () => _markAll(AttendanceMark.off,       _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.close,                'Miss',  () => _markAll(AttendanceMark.missed,    _selectedDate)),
            const SizedBox(width: 8),
            _bulkBtn(Icons.check,                'Att',   () => _markAll(AttendanceMark.attended,  _selectedDate), active: true),
          ]),
        ),
        const SizedBox(height: 10),
        if (subs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('No classes today', style: TextStyle(color: _st))),
          ),
        ...subs.map((s) => _cardToday(s, log.subjectMarks[s.name] ?? AttendanceMark.notMarked)),
      ],
    );
  }

  String _statusLabel(AttendanceMark m) => switch (m) {
    AttendanceMark.attended => 'All Attended',
    AttendanceMark.missed   => 'All Missed',
    AttendanceMark.off      => 'Holiday / Off',
    AttendanceMark.mixed    => 'Mixed',
    _                       => 'Not marked',
  };

  Widget _bulkBtn(IconData icon, String label, VoidCallback cb, {bool active = false}) =>
      GestureDetector(
        onTap: cb,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: active ? _C.green.withOpacity(0.9) : Colors.white24),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ]),
      );

  Widget _cardToday(Subject sub, AttendanceMark cur) {
    final ok = sub.percentage >= sub.criteria;
    final pc = ok ? _C.green : _C.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: _C.primary.withOpacity(0.5), width: 3)),
        boxShadow: [BoxShadow(color: _C.primary.withOpacity(_isDark ? 0.08 : 0.05), blurRadius: 8)],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            _pctBadge(sub.percentage, sub.criteria, pc),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sub.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _pt)),
              Text(sub.statusMessage, style: TextStyle(color: pc, fontSize: 12)),
            ])),
          ]),
        ),
        Divider(height: 1, color: _div),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _mkBtn(Icons.block,                AttendanceMark.notMarked, cur, sub),
            const SizedBox(width: 12),
            _mkBtn(Icons.remove_circle_outline,AttendanceMark.off,       cur, sub),
            const SizedBox(width: 12),
            _mkBtn(Icons.close,                AttendanceMark.missed,    cur, sub),
            const SizedBox(width: 12),
            _mkBtn(Icons.check,                AttendanceMark.attended,  cur, sub),
          ]),
        ),
      ]),
    );
  }

  Widget _mkBtn(IconData icon, AttendanceMark mark, AttendanceMark cur, Subject sub) {
    final on = cur == mark;
    final c = switch (mark) {
      AttendanceMark.attended => _C.green,
      AttendanceMark.missed   => _C.red,
      AttendanceMark.off      => _C.orange,
      _                       => Colors.grey,
    };
    return GestureDetector(
      onTap: () => _mark(sub, mark, _selectedDate),
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? c : Colors.transparent,
          border: Border.all(color: on ? c : (_isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        child: Icon(icon, size: 16, color: on ? Colors.white : (_isDark ? Colors.white38 : Colors.grey.shade400)),
      ),
    );
  }

  // ═══ TIMETABLE TAB ════════════════════════════════════════════════════════
  Widget _tabTimetable() {
    final today   = DateTime.now().weekday;
    final days    = List.generate(7, (i) => i + 1);
    final maxRows = _maxSlots;
    return Column(children: [
      Container(
        color: _surface,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: days.map((d) {
          final isToday = d == today;
          return Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_wd(d), style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                color: isToday ? _C.primary : _st)),
            if (isToday)
              Container(margin: const EdgeInsets.only(top: 2), height: 2, width: 20,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_C.primary, _C.primaryDk]),
                    borderRadius: BorderRadius.circular(1),
                  )),
          ]));
        }).toList()),
      ),
      Divider(height: 1, color: _div),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: days.map((d) {
            final slots   = (_timetable[d] ?? []).where((s) => s.isNotEmpty).toList();
            final isToday = d == today;
            return Expanded(child: Column(children: List.generate(maxRows, (i) {
              final name = i < slots.length ? slots[i] : '';
              if (name.isEmpty) return Container(margin: const EdgeInsets.all(2), height: 72);
              return GestureDetector(
                onTap: () {
                  final now    = DateTime.now();
                  final target = now.add(Duration(days: d - now.weekday));
                  setState(() {
                    _selectedDate = DateTime(target.year, target.month, target.day);
                    _tab = 0;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.all(2), height: 72,
                  decoration: BoxDecoration(
                    gradient: isToday
                        ? const LinearGradient(colors: [_C.primary, _C.primaryDk],
                        begin: Alignment.topLeft, end: Alignment.bottomRight)
                        : LinearGradient(colors: _isDark
                        ? [const Color(0xFF2A2A45), const Color(0xFF1E1E38)]
                        : [Colors.blueGrey.shade700, Colors.blueGrey.shade800]),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isToday ? [BoxShadow(color: _C.primary.withOpacity(0.3),
                        blurRadius: 8, offset: const Offset(0, 3))] : null,
                  ),
                  child: Stack(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 4, 4),
                      child: Text(name, style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    if (_sub(name) != null)
                      Positioned(
                        bottom: 4, right: 4,
                        child: Builder(builder: (_) {
                          final s  = _sub(name)!;
                          final ok = s.percentage >= s.criteria;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: ok ? _C.green.withOpacity(0.9) : _C.red.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('${s.percentage.toStringAsFixed(0)}%',
                                style: const TextStyle(color: Colors.white, fontSize: 9)),
                          );
                        }),
                      ),
                  ]),
                ),
              );
            })));
          }).toList()),
        ),
      ),
      Container(
        color: _surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          _legend(_C.primary, "Today's classes"),
          const SizedBox(width: 16),
          _legend(_isDark ? const Color(0xFF2A2A45) : Colors.blueGrey.shade700, 'Other days'),
          const Spacer(),
          Icon(Icons.edit_outlined, size: 14, color: _st),
          const SizedBox(width: 3),
          Text('Tap ✏ to edit', style: TextStyle(fontSize: 11, color: _st)),
        ]),
      ),
    ]);
  }

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 11, color: _st)),
  ]);

  void _sheetEditTimetable() {
    final editTT = Map<int, List<String>>.fromEntries(
      List.generate(7, (i) => MapEntry(i + 1, List<String>.from(_timetable[i + 1] ?? []))),
    );
    showModalBottomSheet(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: _isDark ? _C.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _TimetableEditSheet(
        timetable: editTT,
        subjectNames: _subjects.map((s) => s.name).toList(),
        isDark: _isDark,
        onSave: (updated) {
          setState(() => _timetable = updated);
          _persist();
          Navigator.pop(ctx);
          _snack('Timetable saved!');
        },
      ),
    );
  }

  // ═══ CALENDAR TAB ══════════════════════════════════════════════════════════
  Widget _tabCalendar() {
    final now   = DateTime.now();
    final first = DateTime(_calMonth.year, _calMonth.month, 1);
    final days  = DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final offset = first.weekday - 1;
    int nm = 0, off = 0, miss = 0, att = 0, mix = 0;
    for (int d = 1; d <= days; d++) {
      switch (_dayLogs[_dk(DateTime(_calMonth.year, _calMonth.month, d))]?.dayStatus
          ?? AttendanceMark.notMarked) {
        case AttendanceMark.attended: att++;  break;
        case AttendanceMark.missed:   miss++; break;
        case AttendanceMark.off:      off++;  break;
        case AttendanceMark.mixed:    mix++;  break;
        default:                      nm++;
      }
    }
    final ta = _subjects.fold(0, (s, e) => s + e.attended);
    final tm = _subjects.fold(0, (s, e) => s + e.missed);
    final to = _subjects.fold(0, (s, e) => s + e.off);
    final tt = _subjects.fold(0, (s, e) => s + e.total);
    return SingleChildScrollView(
      child: Column(children: [
        Container(
          color: _surface, padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(icon: const Icon(Icons.chevron_left, color: _C.primary),
                onPressed: () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month - 1))),
            Text('${_mn(_calMonth.month)} ${_calMonth.year}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _pt)),
            IconButton(icon: const Icon(Icons.chevron_right, color: _C.primary),
                onPressed: () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month + 1))),
          ]),
        ),
        Container(
          color: _surface, padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']
              .map((d) => Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, color: _st)))))
              .toList()),
        ),
        Container(
          color: _surface, padding: const EdgeInsets.only(bottom: 10),
          child: GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, childAspectRatio: 0.85),
            itemCount: offset + days,
            itemBuilder: (ctx, i) {
              if (i < offset) return const SizedBox();
              final day  = i - offset + 1;
              final date = DateTime(_calMonth.year, _calMonth.month, day);
              final log  = _dayLogs[_dk(date)];
              final mark = (log != null && log.subjectMarks.isNotEmpty)
                  ? log.dayStatus : AttendanceMark.notMarked;
              final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
              final isSel   = date.year == _selectedDate.year && date.month == _selectedDate.month && date.day == _selectedDate.day;
              return GestureDetector(
                onTap: () => setState(() { _selectedDate = date; _tab = 0; }),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: isToday ? Border.all(color: _C.primary, width: 2) : null,
                      color: isSel && !isToday ? _C.primary.withOpacity(0.15) : null,
                    ),
                    child: Center(child: Text('$day', style: TextStyle(
                        fontSize: 12,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? _C.primary : _pt))),
                  ),
                  const SizedBox(height: 2),
                  Container(width: 5, height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _dotColor(mark))),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _smCard(children: [
          _calStat('$nm',   'Not marked', Colors.grey.shade400),
          _calStat('$off',  'Off',        _C.orange),
          _calStat('$miss', 'Missed',     _C.red),
          _calStat('$att',  'Attended',   _C.green),
          _calStat('$mix',  'Mixed',      _C.purple),
        ], footer: 'Days'),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _calStat('$to',  'Off',     Colors.grey),
            _calStat('$tm',  'Missed',  Colors.grey),
            _calStat('$ta',  'Attended',Colors.grey),
            _calStat('$tt',  'Total',   Colors.grey),
            _calStat('${_overallPct.toStringAsFixed(2)}%','Percent',Colors.grey),
          ]),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _smCard({required List<Widget> children, required String footer}) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: children),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_C.primary, _C.primaryDk]),
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
            ),
            child: Center(child: Text(footer, style: const TextStyle(color: Colors.white, fontSize: 12))),
          ),
        ]),
      );

  Widget _calStat(String v, String label, Color dot) => Column(children: [
    Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
      const SizedBox(width: 3),
      Text(v, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _pt)),
    ]),
    Text(label, style: TextStyle(color: _st, fontSize: 10)),
  ]);

  // ═══ SUBJECTS TAB ══════════════════════════════════════════════════════════
  Widget _tabSubjects() {
    final ta = _subjects.fold(0, (s, e) => s + e.attended);
    final tm = _subjects.fold(0, (s, e) => s + e.missed);
    final to = _subjects.fold(0, (s, e) => s + e.off);
    final tt = _subjects.fold(0, (s, e) => s + e.total);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _subCard(
          name: 'Overall', pct: _overallPct, criteria: _criteria,
          msg: _overallNeeded > 0 ? 'need to attend $_overallNeeded lectures'
              : tt == 0 ? 'no lectures yet' : 'on track',
          att: ta, miss: tm, off: to, tot: tt, onTap: () {},
        ),
        ..._subjects.map((s) => _subCard(
          name: s.name, pct: s.percentage, criteria: s.criteria, msg: s.statusMessage,
          att: s.attended, miss: s.missed, off: s.off, tot: s.total,
          onTap: () => _sheetSubjectDetail(s),
        )),
      ],
    );
  }

  Widget _subCard({
    required String name, required double pct, required int criteria,
    required String msg, required int att, required int miss,
    required int off, required int tot, required VoidCallback onTap,
  }) {
    final ok = pct >= criteria;
    final c  = ok ? _C.green : _C.red;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: _C.primary.withOpacity(_isDark ? 0.08 : 0.05), blurRadius: 8)],
          border: Border(left: BorderSide(color: _C.primary.withOpacity(0.6), width: 4)),
        ),
        child: Row(children: [
          _pctBadge(pct, criteria, c),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _pt)),
            const SizedBox(height: 2),
            Text(msg, style: TextStyle(color: c, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Att: $att  Miss: $miss  Off: $off  Tot: $tot',
                style: TextStyle(color: _st, fontSize: 12)),
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

  // ═══ SETTINGS TAB ══════════════════════════════════════════════════════════
  Widget _tabSettings() => ListView(children: [
    _sSection('General'),
    _sTile(icon: Icons.track_changes, title: 'Set criteria',
        subtitle: '$_criteria%', onTap: _dlgCriteria),
    _sSection('Database'),
    _sTile(icon: Icons.description_outlined, title: 'Export data as CSV',
        subtitle: 'Preview a CSV summary of all subjects.', onTap: _exportCsv),
    _sSection('Attendance'),
    _sTile(icon: Icons.restart_alt, title: 'Reset all attendance',
        subtitle: 'Clears every subject back to 0 and deletes all day logs.',
        onTap: _dlgReset, titleColor: _C.red),
    const SizedBox(height: 20),
  ]);

  Widget _sSection(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
    child: Text(t, style: const TextStyle(color: _C.primary, fontWeight: FontWeight.w600, fontSize: 13)),
  );

  Widget _sTile({
    required IconData icon, required String title,
    String? subtitle, required VoidCallback onTap, Color? titleColor,
  }) => ListTile(
    tileColor: _card,
    leading: Icon(icon, color: titleColor ?? _C.primary.withOpacity(0.7)),
    title: Text(title, style: TextStyle(fontSize: 14, color: titleColor ?? _pt)),
    subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 12, color: _st)) : null,
    onTap: onTap,
  );

  // ═══ BOTTOM NAV ════════════════════════════════════════════════════════════
  Widget _bottomNav(bool isDark) {
    const items = [
      (Icons.view_day_outlined,     'Today'),
      (Icons.view_column_outlined,  'Timetable'),
      (Icons.calendar_month_outlined,'Calendar'),
      (Icons.list_alt_outlined,     'Subjects'),
      (Icons.settings_outlined,     'Settings'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _div)),
        boxShadow: [BoxShadow(color: _C.primary.withOpacity(0.08), blurRadius: 12)],
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
                    width: 38, height: 26,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_C.primary, _C.primaryDk]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: _C.primary.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Icon(items[i].$1, color: Colors.white, size: 16),
                  )
                else
                  Icon(items[i].$1, color: isDark ? Colors.white38 : Colors.grey.shade400, size: 22),
                const SizedBox(height: 2),
                Text(items[i].$2, style: TextStyle(
                    fontSize: 10,
                    color: active ? _C.primary : (isDark ? Colors.white38 : Colors.grey.shade500),
                    fontWeight: active ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ═══ DIALOGS ═══════════════════════════════════════════════════════════════
  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _C.primary,
          duration: const Duration(seconds: 2)));

  void _dlgCriteria() {
    int tmp = _criteria;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Set Attendance Criteria', style: TextStyle(color: _pt)),
        content: StatefulBuilder(
          builder: (ctx, ss) => Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$tmp%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _C.primary)),
            SliderTheme(
              data: SliderTheme.of(ctx).copyWith(
                  activeTrackColor: _C.primary, thumbColor: _C.primary,
                  overlayColor: _C.primary.withOpacity(0.2)),
              child: Slider(
                value: tmp.toDouble(), min: 0, max: 100, divisions: 20,
                label: '$tmp%', onChanged: (v) => ss(() => tmp = v.round()),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _st))),
          TextButton(
            onPressed: () {
              setState(() { _criteria = tmp; for (final s in _subjects) s.criteria = tmp; });
              _persist(); Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: _C.primary)),
          ),
        ],
      ),
    );
  }

  void _exportCsv() {
    final sb = StringBuffer('Subject,Attended,Missed,Off,Total,Percentage\n');
    for (final s in _subjects) {
      sb.writeln('${s.name},${s.attended},${s.missed},${s.off},${s.total},${s.percentage.toStringAsFixed(2)}%');
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('CSV Export Preview', style: TextStyle(color: _pt)),
        content: SingleChildScrollView(child: SelectableText(sb.toString(),
            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: _pt))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: _C.primary)))],
      ),
    );
  }

  void _dlgReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Reset All Attendance', style: TextStyle(color: _pt)),
        content: Text(
            'This will permanently delete all attendance records and reset every subject to 0.\n\nThis cannot be undone.',
            style: TextStyle(color: _st)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _st))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _C.red),
            onPressed: () async {
              await _Store.clear();
              setState(() {
                for (final s in _subjects) { s.attended = 0; s.missed = 0; s.off = 0; }
                _dayLogs.clear();
              });
              await _persist();
              if (mounted) { Navigator.pop(ctx); _snack('All attendance data has been reset.'); }
            },
            child: const Text('Reset Everything'),
          ),
        ],
      ),
    );
  }

  void _dlgAddSubject() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Add Subject', style: TextStyle(color: _pt)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: TextStyle(color: _pt),
          decoration: InputDecoration(
            hintText: 'Subject name (e.g. MATH)',
            hintStyle: TextStyle(color: _st),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _C.primary.withOpacity(0.4))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _C.primary)),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _st))),
          TextButton(
            onPressed: () {
              final n = ctrl.text.trim().toUpperCase();
              if (n.isNotEmpty && !_subjects.any((s) => s.name == n)) {
                setState(() => _subjects.add(Subject(name: n, criteria: _criteria)));
                _persist();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add', style: TextStyle(color: _C.primary)),
          ),
        ],
      ),
    );
  }

  void _sheetSubjectsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _isDark ? _C.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.add, color: _C.primary),
          title: Text('Add Subject', style: TextStyle(color: _pt)),
          onTap: () { Navigator.pop(ctx); _dlgAddSubject(); },
        ),
        ListTile(
          leading: Icon(Icons.restart_alt, color: _C.red),
          title: Text('Reset All Attendance', style: TextStyle(color: _C.red)),
          onTap: () { Navigator.pop(ctx); _dlgReset(); },
        ),
      ])),
    );
  }

  void _sheetSubjectDetail(Subject sub) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: _isDark ? _C.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, ss) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(sub.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _pt)),
              const SizedBox(height: 4),
              Text(sub.statusMessage, style: TextStyle(
                  color: sub.percentage >= sub.criteria ? _C.green : _C.red, fontSize: 13)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _editStat('Att',  sub.attended, _C.green,
                        () { ss(() => sub.attended++); setState(() {}); _persist(); },
                        () { if (sub.attended > 0) ss(() => sub.attended--); setState(() {}); _persist(); }),
                _editStat('Miss', sub.missed,   _C.red,
                        () { ss(() => sub.missed++);   setState(() {}); _persist(); },
                        () { if (sub.missed > 0)   ss(() => sub.missed--);   setState(() {}); _persist(); }),
                _editStat('Off',  sub.off,      _C.orange,
                        () { ss(() => sub.off++);      setState(() {}); _persist(); },
                        () { if (sub.off > 0)      ss(() => sub.off--);      setState(() {}); _persist(); }),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(
                  onPressed: () => showDialog(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      backgroundColor: _card,
                      title: Text('Delete ${sub.name}?', style: TextStyle(color: _pt)),
                      content: Text('Removes the subject and all its data.', style: TextStyle(color: _st)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c),
                            child: Text('Cancel', style: TextStyle(color: _st))),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: _C.red),
                          onPressed: () {
                            setState(() => _subjects.remove(sub));
                            _persist(); Navigator.pop(c); Navigator.pop(ctx);
                          },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                  child: Text('Delete', style: TextStyle(color: _C.red)),
                ),
                TextButton(onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done', style: TextStyle(color: _C.primary))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _editStat(String label, int value, Color color,
      VoidCallback inc, VoidCallback dec) =>
      Column(children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(icon: const Icon(Icons.remove_circle_outline),
              onPressed: dec, iconSize: 20, color: _st),
          Text('$value', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _pt)),
          IconButton(icon: const Icon(Icons.add_circle_outline),
              onPressed: inc, iconSize: 20, color: _st),
        ]),
      ]);
}

// ═══ TIMETABLE EDIT SHEET ══════════════════════════════════════════════════════
class _TimetableEditSheet extends StatefulWidget {
  final Map<int, List<String>> timetable;
  final List<String>           subjectNames;
  final bool                   isDark;
  final void Function(Map<int, List<String>>) onSave;

  const _TimetableEditSheet({
    required this.timetable, required this.subjectNames,
    required this.isDark,    required this.onSave,
  });

  @override
  State<_TimetableEditSheet> createState() => _TimetableEditSheetState();
}

class _TimetableEditSheetState extends State<_TimetableEditSheet> {
  late Map<int, List<String>>          _tt;
  int                                  _selectedDay = 1;
  final Map<int, TextEditingController> _controllers = {};
  final List<int>                       _slotIds     = [];
  int                                   _nextId      = 0;

  static const _dayNames  = ['','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  static const _dayShort  = ['','Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  Color get _pt  => widget.isDark ? Colors.white : const Color(0xFF1A1535);
  Color get _st  => widget.isDark ? Colors.white54 : const Color(0xFF1A1535).withOpacity(0.5);
  Color get _cardColor  => widget.isDark ? _C.darkCard : Colors.white;
  Color get _div => widget.isDark ? Colors.white12 : _C.primary.withOpacity(0.1);

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now().weekday;
    _tt = Map<int, List<String>>.fromEntries(
      List.generate(7, (i) => MapEntry(i + 1, List<String>.from(widget.timetable[i + 1] ?? []))),
    );
    _rebuildControllers();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  void _rebuildControllers() {
    for (final id in List<int>.from(_slotIds)) { _controllers[id]?.dispose(); _controllers.remove(id); }
    _slotIds.clear();
    for (final name in _tt[_selectedDay] ?? []) {
      final id = _nextId++;
      _slotIds.add(id);
      _controllers[id] = TextEditingController(text: name);
    }
  }

  void _flushToData() {
    _tt[_selectedDay] = [for (final id in _slotIds) _controllers[id]?.text.trim().toUpperCase() ?? ''];
  }

  void _switchDay(int d) { _flushToData(); setState(() { _selectedDay = d; _rebuildControllers(); }); }

  void _addSlot() {
    _flushToData();
    setState(() {
      _tt[_selectedDay]!.add('');
      final id = _nextId++;
      _slotIds.add(id);
      _controllers[id] = TextEditingController(text: '');
    });
  }

  void _removeSlot(int idx) {
    _flushToData();
    setState(() {
      final id = _slotIds[idx];
      _controllers[id]?.dispose(); _controllers.remove(id);
      _slotIds.removeAt(idx); _tt[_selectedDay]!.removeAt(idx);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    _flushToData();
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final id   = _slotIds.removeAt(oldIndex); _slotIds.insert(newIndex, id);
      final name = _tt[_selectedDay]!.removeAt(oldIndex); _tt[_selectedDay]!.insert(newIndex, name);
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.92, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36, height: 4,
          decoration: BoxDecoration(color: _C.primary.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text('Edit Timetable', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _pt)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.check, size: 18, color: _C.primary),
              label: const Text('Save', style: TextStyle(color: _C.primary)),
              onPressed: () { _flushToData(); widget.onSave(_tt); },
            ),
          ]),
        ),
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: 7,
            itemBuilder: (ctx, i) {
              final d      = i + 1;
              final active = _selectedDay == d;
              return GestureDetector(
                onTap: () => _switchDay(d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: active ? const LinearGradient(colors: [_C.primary, _C.primaryDk]) : null,
                    color: active ? null : (widget.isDark ? _C.darkCard : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: active ? [BoxShadow(color: _C.primary.withOpacity(0.3),
                        blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  child: Text(_dayShort[d], style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active ? Colors.white : _st)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Divider(color: _div),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Text(_dayNames[_selectedDay],
                style: const TextStyle(color: _C.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            Icon(Icons.drag_handle, size: 14, color: _st),
            const SizedBox(width: 4),
            Text('Hold & drag to reorder', style: TextStyle(fontSize: 11, color: _st)),
          ]),
        ),
        Expanded(
          child: _slotIds.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('No classes — tap + to add', style: TextStyle(color: _st, fontSize: 13)),
            const SizedBox(height: 16),
            _addButton(),
            const SizedBox(height: 16),
            _quickFillSection(),
          ]))
              : ReorderableListView.builder(
            scrollController: scroll,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            onReorder: _onReorder,
            buildDefaultDragHandles: false,
            itemCount: _slotIds.length,
            itemBuilder: (ctx, idx) => _slotRow(
                key: ValueKey(_slotIds[idx]), idx: idx,
                id: _slotIds[idx], ctrl: _controllers[_slotIds[idx]]!),
            footer: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _addButton(),
                const SizedBox(height: 20),
                _quickFillSection(),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _addButton() => OutlinedButton.icon(
    onPressed: _addSlot,
    icon: const Icon(Icons.add, size: 18, color: _C.primary),
    label: Text('Add slot ${_slotIds.length + 1}', style: const TextStyle(color: _C.primary)),
    style: OutlinedButton.styleFrom(
      side: BorderSide(color: _C.primary.withOpacity(0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );

  Widget _quickFillSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Quick fill from subjects', style: TextStyle(color: _st, fontSize: 12)),
    const SizedBox(height: 8),
    Wrap(
      spacing: 6, runSpacing: 6,
      children: widget.subjectNames.map((name) => GestureDetector(
        onTap: () => _appendSubject(name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _C.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _C.primary.withOpacity(0.3)),
          ),
          child: Text(name, style: const TextStyle(fontSize: 12, color: _C.primary)),
        ),
      )).toList(),
    ),
  ]);

  Widget _slotRow({required Key key, required int idx, required int id, required TextEditingController ctrl}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _cardColor, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.primary.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: _C.primary.withOpacity(0.05), blurRadius: 4)],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 52,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_C.primary, _C.primaryDk],
                begin: Alignment.topCenter, end: Alignment.bottomCenter),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
          ),
          child: Center(child: Text('${idx + 1}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
        ),
        Expanded(
          child: Autocomplete<String>(
            initialValue: TextEditingValue(text: ctrl.text),
            optionsBuilder: (tv) => tv.text.isEmpty
                ? widget.subjectNames
                : widget.subjectNames.where((n) => n.toLowerCase().contains(tv.text.toLowerCase())),
            onSelected: (val) { ctrl.text = val.toUpperCase(); _flushToData(); },
            fieldViewBuilder: (ctx, autoCtrl, fn, onSub) {
              autoCtrl.text = ctrl.text;
              autoCtrl.selection = TextSelection.fromPosition(TextPosition(offset: autoCtrl.text.length));
              return TextField(
                controller: autoCtrl, focusNode: fn,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: _pt),
                decoration: InputDecoration(
                  border: InputBorder.none, hintText: 'Subject name',
                  hintStyle: TextStyle(color: _st),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onChanged: (v) => ctrl.text = v.toUpperCase(),
              );
            },
          ),
        ),
        ReorderableDragStartListener(
          index: idx,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.drag_handle, color: _st, size: 20),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, size: 18, color: _C.red.withOpacity(0.7)),
          onPressed: () => _removeSlot(idx),
          tooltip: 'Remove slot',
        ),
      ]),
    );
  }
}
