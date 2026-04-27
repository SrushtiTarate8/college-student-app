import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'attendance_screen.dart';
import 'planner_screen.dart';
import 'notes_screen.dart';
import 'result_screen.dart';
import 'productivity_engine.dart';
import 'pomodoro_screen.dart';
import 'theme_provider.dart';
import 'package:provider/provider.dart';
import 'chatbot_screen.dart';

class HomeScreen extends StatefulWidget {
  final String studentName;
  final String studentBranch;
  final String studentEmail;

  const HomeScreen({
    super.key,
    this.studentName = "Student",
    this.studentBranch = "Computer Engineering",
    this.studentEmail = "student@college.edu",
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _headerController;
  late AnimationController _cardsController;
  late List<AnimationController> _cardControllers;

  // ── Productivity Engine ─────────────────────────────────────────────────────
  late final ProductivityEngine _productivityEngine;
  bool _engineReady = false;

  // ── Live stats ──────────────────────────────────────────────────────────────
  double _attendancePct = 0.0;
  bool   _attLoaded     = false;

  int    _tasksDue      = 0;
  int    _notesCount    = 0;
  double? _cgpa;

  @override
  void initState() {
    super.initState();

    _headerController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _cardsController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _cardControllers = List.generate(
      4,
          (i) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 500)),
    );

    _headerController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _cardsController.forward();
      for (int i = 0; i < 4; i++) {
        Future.delayed(Duration(milliseconds: 200 + i * 120), () {
          if (mounted) _cardControllers[i].forward();
        });
      }
    });

    // Init productivity engine
    _productivityEngine = ProductivityEngine();
    _productivityEngine.initialize().then((_) {
      if (mounted) setState(() => _engineReady = true);
    });

    // Load all live stats
    _loadAllStats();
  }

  // ── Load all stats at once ──────────────────────────────────────────────────
  void _loadAllStats() {
    _loadAttendance();
    _loadTasks();
    _loadNotes();
    _loadCGPA();
  }

  // ── Attendance ──────────────────────────────────────────────────────────────
  Future<void> _loadAttendance() async {
    try {
      final p  = await SharedPreferences.getInstance();
      final sr = p.getString('att_subjects');
      if (sr == null) {
        setState(() => _attLoaded = true);
        return;
      }
      final list = jsonDecode(sr) as List;
      int totalAtt = 0, totalLec = 0;
      for (final e in list) {
        final att  = (e['attended'] as int?) ?? 0;
        final miss = (e['missed']   as int?) ?? 0;
        totalAtt += att;
        totalLec += att + miss;
      }
      setState(() {
        _attendancePct = totalLec == 0 ? 0 : totalAtt / totalLec * 100;
        _attLoaded     = true;
      });
    } catch (_) {
      setState(() => _attLoaded = true);
    }
  }

  // ── Today's pending tasks (from Hive plannerBox) ────────────────────────────
  Future<void> _loadTasks() async {
    try {
      final box = await Hive.openBox<List>('plannerBox');
      final raw = box.get('tasks', defaultValue: []) ?? [];
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final pending = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((t) =>
      (t['dateKey'] as String?) == todayKey &&
          (t['isDone'] as bool?) != true)
          .length;

      if (mounted) setState(() => _tasksDue = pending);
    } catch (_) {}
  }

  // ── Total notes count (from SharedPreferences notes_data) ──────────────────
  Future<void> _loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('notes_data');
      if (raw == null) {
        if (mounted) setState(() => _notesCount = 0);
        return;
      }
      final data  = jsonDecode(raw) as Map<String, dynamic>;
      int total   = 0;
      data.forEach((_, notes) => total += (notes as List).length);
      if (mounted) setState(() => _notesCount = total);
    } catch (_) {}
  }

  // ── CGPA from result_prediction_data ───────────────────────────────────────
  Future<void> _loadCGPA() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('result_prediction_data');
      if (raw == null) return;

      final data             = jsonDecode(raw) as Map<String, dynamic>;
      final subjects         = (data['subjects'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final prevCGPA         = (data['previousCGPA']    as num?)?.toDouble() ?? 0.0;
      final completedCredits = (data['completedCredits'] as num?)?.toDouble() ?? 0.0;

      double totalWeighted = 0, totalCredits = 0;
      for (final s in subjects) {
        final useExp   = s['useExpected'] as bool? ?? false;
        final internal = useExp
            ? (s['expectedInternalMarks'] as num?)?.toDouble()
            : (s['internalMarks']         as num?)?.toDouble();
        final endSem   = useExp
            ? (s['expectedEndSemMarks'] as num?)?.toDouble()
            : (s['endSemMarks']         as num?)?.toDouble();
        if (internal == null || endSem == null) continue;

        final total = (internal + endSem).clamp(0.0, 100.0);

        double gp = 0;
        if      (total >= 91) gp = 10;
        else if (total >= 81) gp = 9;
        else if (total >= 71) gp = 8;
        else if (total >= 61) gp = 7;
        else if (total >= 57) gp = 6;
        else if (total >= 50) gp = 5;

        final credits = (s['credits'] as num).toDouble();
        totalWeighted += credits * gp;
        totalCredits  += credits;
      }

      if (totalCredits == 0) return;
      final sgpa = totalWeighted / totalCredits;

      double cgpa;
      if (completedCredits > 0) {
        cgpa = (prevCGPA * completedCredits + sgpa * totalCredits) /
            (completedCredits + totalCredits);
      } else {
        cgpa = sgpa;
      }

      if (mounted) setState(() => _cgpa = cgpa);
    } catch (_) {}
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String get _attendanceLabel =>
      _attLoaded ? '${_attendancePct.toStringAsFixed(1)}%' : '...';

  String get _cgpaLabel => _cgpa != null ? _cgpa!.toStringAsFixed(2) : '--';

  /// Navigate to a screen and reload all stats when we come back.
  Future<void> _pushAndRefresh(Widget screen) async {
    await Navigator.push(context, _route(screen));
    _loadAllStats();
  }

  @override
  void dispose() {
    _headerController.dispose();
    _cardsController.dispose();
    for (var c in _cardControllers) c.dispose();
    _productivityEngine.dispose();
    super.dispose();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning";
    if (hour < 17) return "Good Afternoon";
    return "Good Evening";
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark        = themeProvider.isDarkMode;

    final bgColor       = isDark ? const Color(0xFF0F0E17) : const Color(0xFFF5F4FB);
    final cardBg        = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final primaryText   = isDark ? Colors.white : const Color(0xFF1A1535);
    final secondaryText = isDark
        ? Colors.white.withOpacity(0.55)
        : const Color(0xFF1A1535).withOpacity(0.5);
    final borderColor   = isDark
        ? Colors.white.withOpacity(0.06)
        : const Color(0xFF6C63FF).withOpacity(0.08);

    return Scaffold(
      backgroundColor: bgColor,

      // ✅ Chatbot
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatbotScreen(
              studentName:   widget.studentName,
              studentBranch: widget.studentBranch,
            ),
          ),
        ),
        backgroundColor: const Color(0xFF6C63FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tooltip: 'AI Assistant',
        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
      ),

      body: Stack(
        children: [
          // ── Decorative blobs ──────────────────────────────────────────────
          Positioned(
            top: -100, right: -80,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF6C63FF).withOpacity(isDark ? 0.3 : 0.12),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            top: 80, left: -60,
            child: Container(
              width: 180, height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF43E97B).withOpacity(isDark ? 0.15 : 0.1),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [

                // ── AppBar ──────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 20, 0),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                          parent: _headerController, curve: Curves.easeOut),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C63FF), Color(0xFF43E97B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [BoxShadow(
                                color: const Color(0xFF6C63FF).withOpacity(0.3),
                                blurRadius: 12, offset: const Offset(0, 4),
                              )],
                            ),
                            child: const Icon(Icons.school_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Text("CampusMate", style: TextStyle(
                            color: primaryText, fontSize: 20,
                            fontWeight: FontWeight.w800, letterSpacing: 0.3,
                          )),
                          const Spacer(),

                          // Dark-mode toggle
                          GestureDetector(
                            onTap: () => themeProvider.toggleTheme(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 52, height: 28,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: isDark
                                    ? const LinearGradient(colors: [
                                  Color(0xFF6C63FF), Color(0xFF9B59B6)
                                ])
                                    : LinearGradient(colors: [
                                  Colors.grey.shade300,
                                  Colors.grey.shade200,
                                ]),
                                boxShadow: [BoxShadow(
                                  color: isDark
                                      ? const Color(0xFF6C63FF).withOpacity(0.35)
                                      : Colors.black.withOpacity(0.1),
                                  blurRadius: 8, offset: const Offset(0, 2),
                                )],
                              ),
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                alignment: isDark
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  width: 22, height: 22,
                                  decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle),
                                  child: Center(child: Icon(
                                    isDark
                                        ? Icons.dark_mode_rounded
                                        : Icons.wb_sunny_rounded,
                                    color: isDark
                                        ? const Color(0xFF6C63FF)
                                        : Colors.amber,
                                    size: 13,
                                  )),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Profile avatar
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileScreen(
                                  studentName:   widget.studentName,
                                  studentBranch: widget.studentBranch,
                                  studentEmail:  widget.studentEmail,
                                ),
                              ),
                            ),
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                  color: const Color(0xFF6C63FF).withOpacity(0.4),
                                  blurRadius: 12, offset: const Offset(0, 4),
                                )],
                              ),
                              child: Center(child: Text(
                                widget.studentName.isNotEmpty
                                    ? widget.studentName[0].toUpperCase()
                                    : "S",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700),
                              )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Greeting ─────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                    child: SlideTransition(
                      position: Tween<Offset>(
                          begin: const Offset(0, 0.2), end: Offset.zero)
                          .animate(CurvedAnimation(
                          parent: _headerController,
                          curve: Curves.easeOut)),
                      child: FadeTransition(
                        opacity: _headerController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("$_greeting,", style: TextStyle(
                                color: secondaryText, fontSize: 16,
                                fontWeight: FontWeight.w400)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(widget.studentName, style: TextStyle(
                                  color: primaryText, fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5)),
                              const SizedBox(width: 8),
                              const Text("👋", style: TextStyle(fontSize: 26)),
                            ]),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C63FF).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(widget.studentBranch,
                                  style: const TextStyle(
                                      color: Color(0xFF6C63FF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Quick Stats bar ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                          parent: _cardsController, curve: Curves.easeOut),
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF9B59B6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [BoxShadow(
                            color: const Color(0xFF6C63FF).withOpacity(0.35),
                            blurRadius: 24, offset: const Offset(0, 10),
                          )],
                        ),
                        child: Row(children: [
                          Expanded(child: _statItem(
                              _attendanceLabel,
                              "Attendance",
                              Icons.bar_chart_rounded)),
                          Container(width: 1, height: 40,
                              color: Colors.white.withOpacity(0.2)),
                          Expanded(child: _statItem(
                              '$_tasksDue',
                              "Tasks Due",
                              Icons.task_alt_rounded)),
                          Container(width: 1, height: 40,
                              color: Colors.white.withOpacity(0.2)),
                          Expanded(child: AnimatedBuilder(
                            animation: _productivityEngine,
                            builder: (_, __) {
                              final streak = _engineReady
                                  ? _productivityEngine.streak.currentStreak
                                  : null;
                              final label = streak == null
                                  ? '–'
                                  : streak == streak.roundToDouble()
                                  ? '${streak.round()}🔥'
                                  : '${streak.toStringAsFixed(1)}🔥';
                              return _statItem(
                                  label, "Streak",
                                  Icons.local_fire_department_rounded);
                            },
                          )),
                        ]),
                      ),
                    ),
                  ),
                ),

                // ── Productivity Hero Banner ──────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                          parent: _cardsController, curve: Curves.easeOut),
                      child: _ProductivityBanner(
                        engine:      _productivityEngine,
                        engineReady: _engineReady,
                        isDark:      isDark,
                        onTap: () => _pushAndRefresh(
                            PomodoroScreen(engine: _productivityEngine)),
                      ),
                    ),
                  ),
                ),

                // ── Section title ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                          parent: _cardsController, curve: Curves.easeOut),
                      child: Text("Quick Access", style: TextStyle(
                          color: primaryText, fontSize: 20,
                          fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                    ),
                  ),
                ),

                // ── Feature Cards Grid ────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  sliver: SliverGrid(
                    delegate: SliverChildListDelegate([
                      _buildCard(
                        index: 0,
                        title: "Attendance",
                        subtitle: "Track your presence",
                        icon: Icons.bar_chart_rounded,
                        gradientColors: const [
                          Color(0xFF6C63FF), Color(0xFF9B59B6)
                        ],
                        badgeText: _attendanceLabel,
                        cardBg: cardBg, borderColor: borderColor,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        onTap: () => _pushAndRefresh(const AttendanceScreen()),
                      ),
                      _buildCard(
                        index: 1,
                        title: "Study Planner",
                        subtitle: "Plan your sessions",
                        icon: Icons.calendar_today_rounded,
                        gradientColors: const [
                          Color(0xFF43E97B), Color(0xFF38F9D7)
                        ],
                        badgeText: _tasksDue == 0
                            ? 'No tasks'
                            : '$_tasksDue pending',
                        cardBg: cardBg, borderColor: borderColor,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        onTap: () => _pushAndRefresh(PlannerHomeScreen()),
                      ),
                      _buildCard(
                        index: 2,
                        title: "Notes",
                        subtitle: "Your study notes",
                        icon: Icons.sticky_note_2_rounded,
                        gradientColors: const [
                          Color(0xFFFFA751), Color(0xFFFFE259)
                        ],
                        badgeText: '$_notesCount notes',
                        cardBg: cardBg, borderColor: borderColor,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        onTap: () => _pushAndRefresh(const NotesScreen()),
                      ),
                      _buildCard(
                        index: 3,
                        title: "Result Predictor",
                        subtitle: "Predict your score",
                        icon: Icons.auto_graph_rounded,
                        gradientColors: const [
                          Color(0xFFFF6B6B), Color(0xFFFF8E53)
                        ],
                        badgeText: 'CGPA $_cgpaLabel',
                        cardBg: cardBg, borderColor: borderColor,
                        primaryText: primaryText,
                        secondaryText: secondaryText,
                        onTap: () => _pushAndRefresh(const ResultScreen()),
                      ),
                    ]),
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.9,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label, IconData icon) {
    return Column(children: [
      Icon(icon, color: Colors.white.withOpacity(0.85), size: 20),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
          color: Colors.white.withOpacity(0.65), fontSize: 11)),
    ]);
  }

  Widget _buildCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required String badgeText,
    required Color cardBg,
    required Color borderColor,
    required Color primaryText,
    required Color secondaryText,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _cardControllers[index],
      builder: (context, child) {
        final anim = CurvedAnimation(
            parent: _cardControllers[index], curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: _cardControllers[index],
          child: SlideTransition(
            position: Tween<Offset>(
                begin: const Offset(0, 0.25), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [BoxShadow(
              color: gradientColors[0].withOpacity(0.08),
              blurRadius: 20, offset: const Offset(0, 6),
            )],
          ),
          child: Stack(children: [
            Positioned(
              top: -20, right: -20,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    gradientColors[0].withOpacity(0.12),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                        color: gradientColors[0].withOpacity(0.35),
                        blurRadius: 12, offset: const Offset(0, 4),
                      )],
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const Spacer(),
                  Text(title, style: TextStyle(
                      color: primaryText, fontSize: 15,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(
                      color: secondaryText, fontSize: 11.5)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        gradientColors[0].withOpacity(0.15),
                        gradientColors[1].withOpacity(0.1),
                      ]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: gradientColors[0].withOpacity(0.3),
                          width: 1),
                    ),
                    child: Text(badgeText, style: TextStyle(
                        color: gradientColors[0],
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  PageRouteBuilder _route(Widget page) => PageRouteBuilder(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 400),
    transitionsBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
            begin: const Offset(0.05, 0), end: Offset.zero)
            .animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PRODUCTIVITY HERO BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _ProductivityBanner extends StatefulWidget {
  final ProductivityEngine engine;
  final bool engineReady;
  final bool isDark;
  final VoidCallback onTap;

  const _ProductivityBanner({
    required this.engine,
    required this.engineReady,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_ProductivityBanner> createState() => _ProductivityBannerState();
}

class _ProductivityBannerState extends State<_ProductivityBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  static const _gradStart = Color(0xFFFF6B9D);
  static const _gradEnd   = Color(0xFFC44DFF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: widget.engine,
        builder: (context, _) {
          final streak = widget.engineReady
              ? widget.engine.streak.currentStreak
              : 0.0;
          final weeklyPct = widget.engineReady
              ? widget.engine.streak.weeklyConsistency
              : 0.0;
          final goalPct = widget.engineReady
              ? widget.engine.dailyGoal.completionPercentage()
              : 0.0;

          final CharacterState char = widget.engineReady
              ? widget.engine.characterState()
              : const CharacterState(
              mood: CharacterMood.neutral,
              emoji: '🌿',
              message: 'Ready to focus?');

          final tree = widget.engineReady ? widget.engine.treeResult : null;
          const treeEngine = TreeGrowthEngine();

          final streakLabel = streak == streak.roundToDouble()
              ? '${streak.round()}'
              : streak.toStringAsFixed(1);

          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_gradStart, _gradEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(
                color: _gradStart.withOpacity(0.38),
                blurRadius: 28, offset: const Offset(0, 12),
              )],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -30, right: -30,
                  child: Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.07)),
                  ),
                ),
                Positioned(
                  bottom: -20, left: -20,
                  child: Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.05)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Row 1: label + character emoji
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_rounded,
                                  color: Colors.white, size: 12),
                              SizedBox(width: 5),
                              Text('PRODUCTIVITY',
                                  style: TextStyle(
                                    color: Colors.white, fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  )),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.15),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 1.5),
                          ),
                          child: Center(child: Text(
                            char.emoji,
                            style: const TextStyle(fontSize: 22),
                          )),
                        ),
                      ]),

                      const SizedBox(height: 16),

                      // Row 2: streak + tree
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$streakLabel 🔥',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  )),
                              const SizedBox(height: 2),
                              Text('day streak',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  )),
                            ],
                          ),
                          const Spacer(),
                          if (tree != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.25)),
                              ),
                              child: Column(children: [
                                Text(_treeEmoji(tree.stage),
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(height: 2),
                                Text(
                                  treeEngine.stageLabel(tree.stage),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ]),
                            ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Daily goal progress bar
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("Today's goal",
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                              Text('${(goalPct * 100).round()}%',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: goalPct),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOut,
                              builder: (_, v, __) => LinearProgressIndicator(
                                value: v,
                                minHeight: 7,
                                backgroundColor:
                                Colors.white.withOpacity(0.2),
                                valueColor:
                                const AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Row 3: weekly dots + Start Focus CTA
                      Row(children: [
                        _WeeklyDots(consistency: weeklyPct),
                        const Spacer(),
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (_, child) => Transform.scale(
                            scale: 1.0 + _pulseCtrl.value * 0.04,
                            child: child,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8, offset: const Offset(0, 3),
                              )],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Start Focus',
                                    style: TextStyle(
                                      color: _gradStart,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    )),
                                SizedBox(width: 5),
                                Icon(Icons.arrow_forward_rounded,
                                    color: _gradStart, size: 15),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _treeEmoji(TreeStage s) {
    switch (s) {
      case TreeStage.seed:    return '🌰';
      case TreeStage.sprout:  return '🌱';
      case TreeStage.plant:   return '🌿';
      case TreeStage.tree:    return '🌳';
      case TreeStage.bigTree: return '🌲';
    }
  }
}

// ── Weekly consistency dots ───────────────────────────────────────────────────

class _WeeklyDots extends StatelessWidget {
  final double consistency;
  const _WeeklyDots({required this.consistency});

  @override
  Widget build(BuildContext context) {
    final filled = (consistency * 7).round().clamp(0, 7);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(7, (i) {
        final active = i < filled;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width:  active ? 10 : 8,
            height: active ? 10 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white : Colors.white.withOpacity(0.25),
              boxShadow: active
                  ? [BoxShadow(
                  color: Colors.white.withOpacity(0.5), blurRadius: 4)]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}
